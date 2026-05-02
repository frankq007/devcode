/**
 * OpenCode Remote Control Proxy Server
 * 
 * 功能：
 * - WebSocket 服务器：处理手机指令和权限转发
 * - Express 文件服务器：提供文件下载/上传
 * - 文件监控：监听目录变化，通知新文件
 * - 二维码生成：扫码配对认证
 * - OpenCode Serve API 连接：通过 HTTP API 与 OpenCode 通信
 */

const WebSocket = require('ws');
const express = require('express');
const chokidar = require('chokidar');
const QRCode = require('qrcode');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const http = require('http');

// 配置
const CONFIG = {
  WS_PORT: 8080,
  HTTP_PORT: 8081,
  FILE_DIR: path.join(process.env.HOME || process.env.USERPROFILE, 'opencode_output'),
  TOKEN_EXPIRE_MS: 5 * 60 * 1000,
  HEARTBEAT_MS: 30000,
  OPENCODE_API_URL: process.env.OPENCODE_API_URL || 'http://127.0.0.1:4096',
  OPENCODE_USERNAME: process.env.OPENCODE_SERVER_USERNAME || 'devcode',
  OPENCODE_PASSWORD: process.env.OPENCODE_SERVER_PASSWORD || 'devcode123',
  // 默认模型配置
  DEFAULT_MODEL: {
    providerID: process.env.OPENCODE_PROVIDER || 'alibaba-cn',
    modelID: process.env.OPENCODE_MODEL || 'glm-5'
  }
};

// 状态管理
const state = {
  pendingTokens: new Map(),
  authenticatedClients: new Set(),
  pendingPermRequests: new Map(),
  fileWatcher: null,
  currentSessionId: null,
  eventSource: null,
  lastSentMessageId: null,
  isSessionIdle: false,
  pendingMessageContent: '',
  lastSentResponseId: null, // 已发送的响应消息 ID，防止重复
  sseReconnectTimer: null, // SSE 重连 timer
  isSendingMessage: false // 是否正在发送消息
};

// ==================== OpenCode API 客户端 ====================
/**
 * 获取 Basic Auth 头
 */
function getAuthHeader() {
  const credentials = Buffer.from(`${CONFIG.OPENCODE_USERNAME}:${CONFIG.OPENCODE_PASSWORD}`).toString('base64');
  return `Basic ${credentials}`;
}

/**
 * 调用 OpenCode API
 */
async function callOpenCodeAPI(method, path, body = null) {
  const options = {
    hostname: '127.0.0.1',
    port: 4096,
    path: path,
    method: method,
    headers: {
      'Authorization': getAuthHeader(),
      'Content-Type': 'application/json'
    }
  };

  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(data));
          } catch {
            resolve(data);
          }
        } else {
          reject(new Error(`API error: ${res.statusCode} - ${data}`));
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

/**
 * 检查 OpenCode Serve 是否运行
 */
async function checkOpenCodeServer() {
  try {
    const result = await callOpenCodeAPI('GET', '/global/health');
    return result.healthy === true;
  } catch (err) {
    return false;
  }
}

/**
 * 获取或创建 session
 */
async function getOrCreateSession() {
  try {
    const sessions = await callOpenCodeAPI('GET', '/session');
    
    if (sessions && sessions.length > 0) {
      const latest = sessions.sort((a, b) => b.time.updated - a.time.updated)[0];
      state.currentSessionId = latest.id;
      return latest.id;
    }

    const newSession = await callOpenCodeAPI('POST', '/session', { title: 'DevCode Remote' });
    state.currentSessionId = newSession.id;
    return newSession.id;
  } catch (err) {
    console.error('[OpenCode] Session 操作失败:', err.message);
    throw err;
  }
}

/**
 * 发送消息到 OpenCode
 */
async function sendMessageToOpenCode(content) {
  if (!state.currentSessionId) {
    try {
      await getOrCreateSession();
    } catch {
      return false;
    }
  }

  try {
    await callOpenCodeAPI('POST', `/session/${state.currentSessionId}/prompt_async`, {
      parts: [{ type: 'text', text: content }],
      model: CONFIG.DEFAULT_MODEL
    });
    state.lastSentResponseId = null;
    return true;
  } catch (err) {
    console.error('[OpenCode] 发送失败:', err.message);
    return false;
  }
}

/**
 * 启动 SSE 事件监听
 */
function startEventListener() {
  if (state.eventSource) {
    return;
  }

  // 清除可能存在的重连 timer
  if (state.sseReconnectTimer) {
    clearTimeout(state.sseReconnectTimer);
    state.sseReconnectTimer = null;
  }

  console.log('[OpenCode] 启动 SSE 连接...');

  const options = {
    hostname: '127.0.0.1',
    port: 4096,
    path: '/event',
    method: 'GET',
    headers: {
      'Authorization': getAuthHeader(),
      'Accept': 'text/event-stream'
    }
  };

  const req = http.request(options, (res) => {
    state.eventSource = req;
    let buffer = '';
    
    res.on('data', (chunk) => {
      buffer += chunk.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() || ''; // 保存最后一个不完整的行
      
      for (const line of lines) {
        if (line.startsWith('data:')) {
          const jsonStr = line.substring(5).trim();
          if (!jsonStr) continue;
          
          try {
            const event = JSON.parse(jsonStr);
            handleOpenCodeEvent(event);
          } catch (e) {
            // JSON 解析失败，忽略
          }
        }
      }
    });

    res.on('error', (err) => {
      console.error('[OpenCode] SSE 错误:', err.message);
      state.eventSource = null;
      scheduleSseReconnect();
    });

    res.on('end', () => {
      console.log('[OpenCode] SSE 连接关闭');
      state.eventSource = null;
      scheduleSseReconnect();
    });
  });

  req.on('error', (err) => {
    console.error('[OpenCode] SSE 连接失败:', err.message);
    state.eventSource = null;
    scheduleSseReconnect();
  });

  req.end();
}

function scheduleSseReconnect() {
  if (state.sseReconnectTimer) return;
  
  state.sseReconnectTimer = setTimeout(() => {
    state.sseReconnectTimer = null;
    if (state.authenticatedClients.size > 0) {
      startEventListener();
    }
  }, 10000); // 10秒后重连，且只在有客户端时重连
}

/**
 * 处理 OpenCode 事件
 */
function handleOpenCodeEvent(event) {
  const eventType = event.type || event.name;
  
  if (eventType !== 'message.part.delta') {
    console.log('[OpenCode] 事件:', eventType);
  }

  if (eventType === 'server.connected') {
    broadcastToClients({ type: 'task_status', status: 'ready', message: 'OpenCode 已连接' });
    state.isSessionIdle = true;
  } else if (eventType === 'message.updated') {
    const props = event.properties || {};
    const info = props.info || {};
    // 只记录 assistant 消息的 ID
    if (props.sessionID && info.id && info.role === 'assistant') {
      state.lastSentMessageId = info.id;
      
      // 实时发送执行状态（如果有正在执行的工具）
      if (props.parts) {
        const runningTools = props.parts.filter(p => p.type === 'tool' && p.state?.status === 'running');
        if (runningTools.length > 0) {
          const cmd = runningTools[0].state?.input?.command || '';
          broadcastToClients({ 
            type: 'task_status', 
            status: 'running',
            message: `正在执行: ${cmd}`
          });
        }
      }
    }
  } else if (eventType === 'message.part.delta') {
    state.isSessionIdle = false;
    state.isSendingMessage = true;
  } else if (eventType === 'session.message') {
    handleNewMessage(event.data);
  } else if (eventType === 'permission.request') {
    handlePermissionEvent(event.data);
  } else if (eventType === 'session.status') {
    const status = event.data?.status || 'running';
    if (status !== 'idle') {
      state.isSessionIdle = false;
      state.isSendingMessage = true;
    }
  } else if (eventType === 'session.idle') {
    state.isSessionIdle = true;
    state.isSendingMessage = false;
    
    // 只在 idle 时发送 assistant 消息
    if (state.lastSentMessageId && state.currentSessionId) {
      if (state.lastSentResponseId !== state.lastSentMessageId) {
        state.lastSentResponseId = state.lastSentMessageId;
        sendCompletedMessage(state.currentSessionId, state.lastSentMessageId);
      }
    }
  } else if (eventType === 'session.error') {
    state.isSessionIdle = true;
    state.isSendingMessage = false;
    broadcastToClients({ 
      type: 'task_status', 
      status: 'error',
      message: 'Session 错误'
    });
  }
}

/**
 * 发送完成的消息给手机（只在 session.idle 时调用）
 */
async function sendCompletedMessage(sessionId, messageId) {
  if (!sessionId || !messageId) return;
  
  try {
    const msgDetail = await callOpenCodeAPI('GET', `/session/${sessionId}/message/${messageId}`);
    
    if (msgDetail?.parts) {
      // 提取文本内容
      const textParts = msgDetail.parts
        .filter(p => p.type === 'text')
        .map(p => p.text)
        .join('\n');

      // 提取 tool/bash 执行结果
      const toolParts = msgDetail.parts
        .filter(p => p.type === 'tool' && p.tool === 'bash' && p.state?.status === 'completed')
        .map(p => {
          const cmd = p.state?.input?.command || '';
          const output = p.state?.output || '';
          return `[执行: ${cmd}]\n${output}`;
        })
        .join('\n');

      // 合并发送
      const fullContent = (textParts + '\n' + toolParts).trim();
      
      if (fullContent) {
        broadcastToClients({ 
          type: 'ai_response', 
          content: fullContent,
          messageID: messageId
        });
      }
    }
  } catch (err) {
    console.error('[OpenCode] 获取消息失败:', err.message);
  }
}

/**
 * 处理新消息（旧版兼容）
 */
async function handleNewMessage(data) {
  if (!data?.sessionID || !data?.messageID) return;
  
  // 防止重复
  if (state.lastSentResponseId === data.messageID) return;
  state.lastSentResponseId = data.messageID;
  
  try {
    const msgDetail = await callOpenCodeAPI('GET', `/session/${data.sessionID}/message/${data.messageID}`);
    if (msgDetail?.parts) {
      const textParts = msgDetail.parts.filter(p => p.type === 'text').map(p => p.text).join('\n');
      const toolParts = msgDetail.parts
        .filter(p => p.type === 'tool' && p.tool === 'bash' && p.state?.status === 'completed')
        .map(p => `[执行: ${p.state?.input?.command || ''}]\n${p.state?.output || ''}`)
        .join('\n');
      const fullContent = (textParts + '\n' + toolParts).trim();
      if (fullContent) {
        broadcastToClients({ type: 'ai_response', content: fullContent, messageID: data.messageID });
      }
    }
  } catch {}
}

/**
 * 处理权限请求事件
 */
function handlePermissionEvent(data) {
  const requestId = data.id || uuidv4();
  state.pendingPermRequests.set(requestId, { data });
  broadcastToClients({
    type: 'permission_request',
    id: requestId,
    command: data.permission || data.tool || 'Unknown',
    explanation: data.message || '需要授权'
  });
}

// ==================== WebSocket 服务器 ====================
const wss = new WebSocket.Server({ port: CONFIG.WS_PORT });

wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      handleWebSocketMessage(ws, msg);
    } catch {}
  });

  ws.on('close', () => {
    state.authenticatedClients.delete(ws);
  });
});

// 心跳检测
const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) {
      console.log('[WS] 心跳超时，终止连接');
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, CONFIG.HEARTBEAT_MS);

wss.on('close', () => {
  clearInterval(heartbeatInterval);
});

/**
 * 处理 WebSocket 消息
 */
function handleWebSocketMessage(ws, msg) {
  switch (msg.type) {
    case 'auth':
      handleAuth(ws, msg);
      break;
    case 'exec':
      handleExec(ws, msg);
      break;
    case 'permission_response':
      handlePermissionResponse(ws, msg);
      break;
    case 'list_files':
      handleListFiles(ws);
      break;
    case 'pong':
      ws.isAlive = true;
      break;
  }
}

/**
 * 处理认证
 */
async function handleAuth(ws, msg) {
  const { token } = msg;
  
  // DEBUG MODE
  if (token && token.startsWith('debug-')) {
    state.authenticatedClients.add(ws);
    ws.authenticated = true;
    ws.send(JSON.stringify({ type: 'auth_result', success: true }));
    
    // 检查并连接 OpenCode
    const serverRunning = await checkOpenCodeServer();
    if (!serverRunning) {
      ws.send(JSON.stringify({ type: 'task_status', status: 'warning', message: 'OpenCode Serve 未运行' }));
      return;
    }
    
    try {
      await getOrCreateSession();
      startEventListener();
      broadcastToClients({ type: 'task_status', status: 'ready', message: 'OpenCode 已连接' });
    } catch (err) {
      broadcastToClients({ type: 'error', message: '连接失败: ' + err.message });
    }
    return;
  }
  
  // 正常认证
  const tokenData = state.pendingTokens.get(token);
  if (!tokenData) {
    ws.send(JSON.stringify({ type: 'auth_result', success: false, message: 'Token 不存在' }));
    return;
  }
  if (Date.now() > tokenData.expire) {
    state.pendingTokens.delete(token);
    ws.send(JSON.stringify({ type: 'auth_result', success: false, message: 'Token 已过期' }));
    return;
  }

  state.pendingTokens.delete(token);
  state.authenticatedClients.add(ws);
  ws.authenticated = true;

  const serverRunning = await checkOpenCodeServer();
  if (!serverRunning) {
    ws.send(JSON.stringify({ type: 'auth_result', success: true, warning: 'OpenCode Serve 未运行' }));
    return;
  }

  ws.send(JSON.stringify({ type: 'auth_result', success: true }));
  
  try {
    await getOrCreateSession();
    startEventListener();
    broadcastToClients({ type: 'task_status', status: 'ready' });
  } catch (err) {
    broadcastToClients({ type: 'error', message: '连接失败' });
  }
}

/**
 * 处理执行指令
 */
async function handleExec(ws, msg) {
  if (!ws.authenticated) {
    ws.send(JSON.stringify({ type: 'error', message: '未认证' }));
    return;
  }

  const { content } = msg;
  const sent = await sendMessageToOpenCode(content);
  
  ws.send(JSON.stringify({ type: 'exec_ack', success: sent }));
}

/**
 * 处理权限响应
 */
async function handlePermissionResponse(ws, msg) {
  const { id, answer } = msg;
  if (!state.currentSessionId) {
    ws.send(JSON.stringify({ type: 'error', message: '无 session' }));
    return;
  }
  
  const responded = await respondToPermission(state.currentSessionId, id, answer);
  if (responded) {
    state.pendingPermRequests.delete(id);
    ws.send(JSON.stringify({ type: 'permission_ack', success: true }));
  } else {
    ws.send(JSON.stringify({ type: 'error', message: '响应失败' }));
  }
}

/**
 * 处理文件列表请求
 */
function handleListFiles(ws) {
  if (!ws.authenticated) {
    ws.send(JSON.stringify({ type: 'error', message: '未认证' }));
    return;
  }

  const files = listFiles(CONFIG.FILE_DIR);
  ws.send(JSON.stringify({ type: 'file_list', files }));
}

// ==================== HTTP 文件服务器 ====================
const app = express();
app.use(cors());

// 确保文件目录存在
if (!fs.existsSync(CONFIG.FILE_DIR)) {
  fs.mkdirSync(CONFIG.FILE_DIR, { recursive: true });
}

// 静态文件服务
app.use('/files', express.static(CONFIG.FILE_DIR));

// 配对页面
app.use('/public', express.static(path.join(__dirname, 'public')));
app.get('/', (req, res) => {
  res.redirect('/public/index.html');
});

// 文件列表
app.get('/list', (req, res) => {
  const files = listFiles(CONFIG.FILE_DIR);
  res.json({ files });
});

// 二维码生成
app.get('/qrcode', async (req, res) => {
  try {
    const token = uuidv4();
    const expire = Date.now() + CONFIG.TOKEN_EXPIRE_MS;
    state.pendingTokens.set(token, { expire });

    const localIP = getLocalIP();
    const connectUrl = `devcode://connect?token=${token}&expire=${expire}&ip=${localIP}&wsPort=${CONFIG.WS_PORT}&httpPort=${CONFIG.HTTP_PORT}`;

    const qrImage = await QRCode.toDataURL(connectUrl, { width: 300, margin: 2 });

    res.json({ success: true, token, qrImage, ip: localIP, wsPort: CONFIG.WS_PORT, httpPort: CONFIG.HTTP_PORT });
  } catch {
    res.status(500).json({ success: false });
  }
});

// 文件上传
app.post('/upload', express.raw({ type: '*/*', limit: '100mb' }), (req, res) => {
  const filename = req.query.filename || 'uploaded_file';
  const filepath = path.join(CONFIG.FILE_DIR, filename);
  fs.writeFile(filepath, req.body, (err) => {
    if (err) return res.status(500).json({ success: false });
    res.json({ success: true, filename });
  });
});

// 状态查询
app.get('/status', async (req, res) => {
  const opencodeHealthy = await checkOpenCodeServer();
  res.json({
    wsPort: CONFIG.WS_PORT,
    httpPort: CONFIG.HTTP_PORT,
    clients: state.authenticatedClients.size,
    opencodeHealthy,
    currentSessionId: state.currentSessionId
  });
});

app.listen(CONFIG.HTTP_PORT, () => {
  console.log(`[HTTP] http://localhost:${CONFIG.HTTP_PORT}`);
});

// ==================== 文件监控 ====================
state.fileWatcher = chokidar.watch(CONFIG.FILE_DIR, {
  ignored: /(^|[\/\\])\../,
  persistent: true,
  ignoreInitial: true
});

state.fileWatcher.on('add', (filepath) => {
  const relativePath = path.relative(CONFIG.FILE_DIR, filepath);
  broadcastToClients({ type: 'file_added', filename: relativePath, url: `/files/${relativePath}` });
});

state.fileWatcher.on('change', (filepath) => {
  const relativePath = path.relative(CONFIG.FILE_DIR, filepath);
  broadcastToClients({ type: 'file_updated', filename: relativePath, url: `/files/${relativePath}` });
});

state.fileWatcher.on('unlink', (filepath) => {
  const relativePath = path.relative(CONFIG.FILE_DIR, filepath);
  broadcastToClients({ type: 'file_removed', filename: relativePath });
});

// ==================== 辅助函数 ====================
/**
 * 广播消息给所有已认证客户端
 */
function broadcastToClients(msg) {
  const data = JSON.stringify(msg);
  state.authenticatedClients.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(data);
    }
  });
}

/**
 * 获取本地 IP
 */
function getLocalIP() {
  const interfaces = require('os').networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      // 优先返回 Tailscale IP (100.64.x.x)
      if (iface.address.startsWith('100.64.')) {
        return iface.address;
      }
      // 否则返回普通局域网 IP
      if (iface.family === 'IPv4' && !iface.internal && !iface.address.startsWith('169.254.')) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
}

/**
 * 列出文件
 */
function listFiles(dir) {
  if (!fs.existsSync(dir)) return [];

  const files = [];
  const items = fs.readdirSync(dir);

  for (const item of items) {
    const filepath = path.join(dir, item);
    const stat = fs.statSync(filepath);

    if (stat.isFile()) {
      files.push({
        name: item,
        path: item,
        size: stat.size,
        modified: stat.mtime,
        url: `/files/${item}`
      });
    }
  }

  return files;
}

// ==================== 启动完成 ====================
console.log('\n========================================');
console.log('  DevCode Proxy Server');
console.log('========================================');
console.log(`WebSocket: ${CONFIG.WS_PORT}`);
console.log(`HTTP: ${CONFIG.HTTP_PORT}`);
console.log(`Model: ${CONFIG.DEFAULT_MODEL.providerID}/${CONFIG.DEFAULT_MODEL.modelID}`);
console.log('\n请先运行: opencode serve --port 4096');
console.log('\n可选: 设置模型环境变量');
console.log('  OPENCODE_PROVIDER=alibaba-cn');
console.log('  OPENCODE_MODEL=glm-5');
console.log('========================================\n');