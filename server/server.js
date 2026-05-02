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
  TOKEN_EXPIRE_MS: 5 * 60 * 1000, // 5分钟
  HEARTBEAT_MS: 30000,
  // OpenCode Serve API 配置
  OPENCODE_API_URL: process.env.OPENCODE_API_URL || 'http://127.0.0.1:4096',
  OPENCODE_USERNAME: process.env.OPENCODE_SERVER_USERNAME || 'devcode',
  OPENCODE_PASSWORD: process.env.OPENCODE_SERVER_PASSWORD || 'devcode123'
};

// 状态管理
const state = {
  pendingTokens: new Map(), // token -> { expire, ws }
  authenticatedClients: new Set(), // 已认证的 WebSocket 连接
  pendingPermRequests: new Map(), // requestId -> { ws }
  fileWatcher: null,
  currentSessionId: null, // 当前 OpenCode session ID
  eventSource: null // SSE 连接
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
    console.log('[OpenCode] 服务器健康检查:', result);
    return result.healthy === true;
  } catch (err) {
    console.error('[OpenCode] 服务器未响应:', err.message);
    return false;
  }
}

/**
 * 获取或创建 session
 */
async function getOrCreateSession() {
  try {
    // 获取现有 sessions
    const sessions = await callOpenCodeAPI('GET', '/session');
    
    if (sessions && sessions.length > 0) {
      // 使用最近的 session
      const latest = sessions.sort((a, b) => b.time.updated - a.time.updated)[0];
      state.currentSessionId = latest.id;
      console.log('[OpenCode] 使用现有 session:', latest.id, latest.title);
      return latest.id;
    }

    // 创建新 session
    const newSession = await callOpenCodeAPI('POST', '/session', { title: 'DevCode Remote' });
    state.currentSessionId = newSession.id;
    console.log('[OpenCode] 创建新 session:', newSession.id);
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
  // 先检查 OpenCode 是否运行
  const healthy = await checkOpenCodeServer();
  if (!healthy) {
    console.error('[OpenCode] 服务器未运行，无法发送消息');
    return false;
  }

  if (!state.currentSessionId) {
    try {
      await getOrCreateSession();
    } catch (err) {
      console.error('[OpenCode] 获取 session 失败:', err.message);
      return false;
    }
  }

  try {
    // 使用 prompt_async 异步发送（不等待响应）
    await callOpenCodeAPI('POST', `/session/${state.currentSessionId}/prompt_async`, {
      parts: [{ type: 'text', text: content }]
    });
    console.log('[OpenCode] 消息已发送:', content.substring(0, 50));
    return true;
  } catch (err) {
    console.error('[OpenCode] 发送消息失败:', err.message);
    return false;
  }
}

/**
 * 获取消息列表
 */
async function getMessages(sessionId) {
  try {
    const messages = await callOpenCodeAPI('GET', `/session/${sessionId}/message?limit=20`);
    return messages;
  } catch (err) {
    console.error('[OpenCode] 获取消息失败:', err.message);
    return [];
  }
}

/**
 * 启动 SSE 事件监听
 */
function startEventListener() {
  if (state.eventSource) {
    console.log('[OpenCode] SSE 已连接');
    return;
  }

  console.log('[OpenCode] 启动 SSE 事件监听...');

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
    let buffer = '';
    
    res.on('data', (chunk) => {
      buffer += chunk.toString();
      
      // 解析 SSE 事件
      const lines = buffer.split('\n');
      buffer = '';
      
      for (const line of lines) {
        // SSE 格式可能是 "data:" 或 "data: "（有空格）
        if (line.startsWith('data:')) {
          const jsonStr = line.startsWith('data: ') ? line.substring(6) : line.substring(5);
          if (!jsonStr.trim()) continue; // 空数据跳过
          
          try {
            const event = JSON.parse(jsonStr);
            handleOpenCodeEvent(event);
          } catch (e) {
            // 不完整的 JSON，保存到 buffer
            buffer = line + '\n';
          }
        }
      }
    });

    res.on('error', (err) => {
      console.error('[OpenCode] SSE 错误:', err.message);
      state.eventSource = null;
    });

    res.on('end', () => {
      console.log('[OpenCode] SSE 连接关闭');
      state.eventSource = null;
      // 5秒后重连
      setTimeout(startEventListener, 5000);
    });
  });

  req.on('error', (err) => {
    console.error('[OpenCode] SSE 连接失败:', err.message);
    state.eventSource = null;
    setTimeout(startEventListener, 5000);
  });

  req.end();
  state.eventSource = req;
}

/**
 * 处理 OpenCode 事件
 */
function handleOpenCodeEvent(event) {
  const eventType = event.type || event.name;
  console.log('[OpenCode] 事件:', eventType);

  // 根据事件类型处理
  if (eventType === 'server.connected') {
    broadcastToClients({ type: 'task_status', status: 'ready', message: 'OpenCode 已连接' });
  } else if (eventType === 'message.updated' || eventType === 'message.part.updated') {
    // 消息更新事件 - 获取最新消息内容
    if (event.data?.sessionID && event.data?.messageID) {
      handleNewMessage(event.data);
    }
  } else if (eventType === 'session.message') {
    // 旧版事件名称（兼容）
    handleNewMessage(event.data);
  } else if (eventType === 'permission.request') {
    // 权限请求
    handlePermissionEvent(event.data);
  } else if (eventType === 'session.status' || eventType === 'session.idle') {
    // Session 状态变化
    broadcastToClients({ 
      type: 'task_status', 
      status: eventType === 'session.idle' ? 'idle' : 'running',
      message: `Session 状态: ${eventType}`
    });
  } else if (eventType === 'session.error') {
    // 错误事件
    broadcastToClients({ 
      type: 'task_status', 
      status: 'error',
      message: 'Session 错误: ' + (event.data?.error || 'Unknown')
    });
  } else if (eventType === 'tui.toast.show') {
    // Toast 通知
    if (event.data?.message) {
      broadcastToClients({ 
        type: 'task_status', 
        status: 'info',
        message: event.data.message
      });
    }
  }
}

/**
 * 处理新消息
 */
async function handleNewMessage(data) {
  if (!data?.sessionID || !data?.messageID) return;

  try {
    // 获取消息详情
    const msgDetail = await callOpenCodeAPI('GET', `/session/${data.sessionID}/message/${data.messageID}`);
    
    if (msgDetail?.parts) {
      // 提取文本内容
      const textParts = msgDetail.parts
        .filter(p => p.type === 'text')
        .map(p => p.text)
        .join('\n');

      if (textParts) {
        broadcastToClients({ 
          type: 'task_status', 
          status: 'response',
          content: textParts,
          messageID: data.messageID
        });
      }
    }
  } catch (err) {
    console.error('[OpenCode] 获取消息详情失败:', err.message);
  }
}

/**
 * 处理权限请求事件
 */
function handlePermissionEvent(data) {
  const requestId = data.id || uuidv4();
  
  const permRequest = {
    type: 'permission_request',
    id: requestId,
    command: data.permission || data.tool || 'Unknown',
    explanation: data.message || '需要您的授权才能继续执行',
    raw: JSON.stringify(data)
  };

  state.pendingPermRequests.set(requestId, { data });

  console.log('[WS] 权限请求:', requestId, permRequest.command);
  broadcastToClients(permRequest);
}

/**
 * 响应权限请求
 */
async function respondToPermission(sessionId, permissionId, response) {
  try {
    await callOpenCodeAPI('POST', `/session/${sessionId}/permissions/${permissionId}`, {
      response: response // 'allow' or 'deny'
    });
    console.log('[OpenCode] 权限响应已发送:', response);
    return true;
  } catch (err) {
    console.error('[OpenCode] 权限响应失败:', err.message);
    return false;
  }
}

// ==================== WebSocket 服务器 ====================
const wss = new WebSocket.Server({ port: CONFIG.WS_PORT });

wss.on('connection', (ws) => {
  console.log('[WS] 新连接建立');

  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      handleWebSocketMessage(ws, msg);
    } catch (err) {
      console.error('[WS] 消息解析错误:', err);
      ws.send(JSON.stringify({ type: 'error', message: 'Invalid message format' }));
    }
  });

  ws.on('close', () => {
    console.log('[WS] 连接关闭');
    state.authenticatedClients.delete(ws);
  });

  ws.on('error', (err) => {
    console.error('[WS] 连接错误:', err);
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
  console.log('[WS] 收到消息:', msg.type);

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
    default:
      ws.send(JSON.stringify({ type: 'error', message: 'Unknown message type' }));
  }
}

/**
 * 处理认证
 */
async function handleAuth(ws, msg) {
  const { token } = msg;
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

  // 认证成功
  state.pendingTokens.delete(token);
  state.authenticatedClients.add(ws);
  ws.authenticated = true;

  console.log('[WS] 认证成功');

  // 检查 OpenCode Serve 是否运行
  const serverRunning = await checkOpenCodeServer();
  
  if (!serverRunning) {
    ws.send(JSON.stringify({ 
      type: 'auth_result', 
      success: true, 
      message: '配对成功，但 OpenCode Serve 未运行',
      warning: '请运行: opencode serve --port 4096'
    }));
    broadcastToClients({ 
      type: 'task_status', 
      status: 'warning', 
      message: '请启动 OpenCode Serve: opencode serve --port 4096' 
    });
    return;
  }

  ws.send(JSON.stringify({ type: 'auth_result', success: true, message: '配对成功，OpenCode 已连接' }));

  // 获取或创建 session
  try {
    await getOrCreateSession();
    
    // 启动 SSE 事件监听
    startEventListener();

    broadcastToClients({ 
      type: 'task_status', 
      status: 'ready', 
      message: 'OpenCode Serve 已连接，Session: ' + state.currentSessionId 
    });
  } catch (err) {
    broadcastToClients({ 
      type: 'error', 
      message: 'OpenCode Session 创建失败: ' + err.message 
    });
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
  console.log('[WS] 执行指令:', content);

  // 发送消息到 OpenCode
  const sent = await sendMessageToOpenCode(content);
  
  if (!sent) {
    ws.send(JSON.stringify({ type: 'error', message: 'OpenCode 消息发送失败' }));
  } else {
    ws.send(JSON.stringify({ type: 'exec_ack', success: true, message: '消息已发送到 OpenCode' }));
  }
}

/**
 * 处理权限响应
 */
async function handlePermissionResponse(ws, msg) {
  const { id, answer } = msg;

  console.log('[WS] 权限响应:', id, answer);

  if (!state.currentSessionId) {
    ws.send(JSON.stringify({ type: 'error', message: '没有活跃的 session' }));
    return;
  }

  // 发送权限响应到 OpenCode API
  const responded = await respondToPermission(state.currentSessionId, id, answer);
  
  if (responded) {
    state.pendingPermRequests.delete(id);
    ws.send(JSON.stringify({ type: 'permission_ack', success: true }));
  } else {
    ws.send(JSON.stringify({ type: 'error', message: '权限响应失败' }));
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

    // 获取本机 Tailscale IP 或本地 IP
    const localIP = getLocalIP();
    const connectUrl = `devcode://connect?token=${token}&expire=${expire}&ip=${localIP}&wsPort=${CONFIG.WS_PORT}&httpPort=${CONFIG.HTTP_PORT}`;

    const qrImage = await QRCode.toDataURL(connectUrl, {
      width: 300,
      margin: 2
    });

    res.json({
      success: true,
      token,
      expire,
      connectUrl,
      qrImage,
      ip: localIP,
      wsPort: CONFIG.WS_PORT,
      httpPort: CONFIG.HTTP_PORT,
      opencodeUsername: CONFIG.OPENCODE_USERNAME,
      opencodePassword: CONFIG.OPENCODE_PASSWORD
    });
  } catch (err) {
    console.error('[HTTP] 二维码生成错误:', err);
    res.status(500).json({ success: false, message: '二维码生成失败' });
  }
});

// 文件上传
app.post('/upload', express.raw({ type: '*/*', limit: '100mb' }), (req, res) => {
  const filename = req.query.filename || 'uploaded_file';
  const filepath = path.join(CONFIG.FILE_DIR, filename);

  fs.writeFile(filepath, req.body, (err) => {
    if (err) {
      console.error('[HTTP] 文件上传错误:', err);
      return res.status(500).json({ success: false, message: '上传失败' });
    }
    res.json({ success: true, filename, path: filepath });
  });
});

// 状态查询
app.get('/status', async (req, res) => {
  const opencodeHealthy = await checkOpenCodeServer();
  res.json({
    wsPort: CONFIG.WS_PORT,
    httpPort: CONFIG.HTTP_PORT,
    fileDir: CONFIG.FILE_DIR,
    clients: state.authenticatedClients.size,
    opencodeHealthy,
    currentSessionId: state.currentSessionId,
    pendingTokens: state.pendingTokens.size,
    opencodeApiUrl: CONFIG.OPENCODE_API_URL
  });
});

app.listen(CONFIG.HTTP_PORT, () => {
  console.log(`[HTTP] 文件服务器启动: http://localhost:${CONFIG.HTTP_PORT}`);
  console.log(`[HTTP] 二维码地址: http://localhost:${CONFIG.HTTP_PORT}/qrcode`);
  console.log(`[HTTP] 文件目录: ${CONFIG.FILE_DIR}`);
});

// ==================== 文件监控 ====================
state.fileWatcher = chokidar.watch(CONFIG.FILE_DIR, {
  ignored: /(^|[\/\\])\../,
  persistent: true,
  ignoreInitial: true
});

state.fileWatcher.on('add', (filepath) => {
  console.log('[Watcher] 新文件:', filepath);
  const relativePath = path.relative(CONFIG.FILE_DIR, filepath);
  const fileInfo = getFileInfo(filepath);

  broadcastToClients({
    type: 'file_added',
    filename: relativePath,
    url: `/files/${relativePath}`,
    ...fileInfo
  });
});

state.fileWatcher.on('change', (filepath) => {
  console.log('[Watcher] 文件变化:', filepath);
  const relativePath = path.relative(CONFIG.FILE_DIR, filepath);
  const fileInfo = getFileInfo(filepath);

  broadcastToClients({
    type: 'file_updated',
    filename: relativePath,
    url: `/files/${relativePath}`,
    ...fileInfo
  });
});

state.fileWatcher.on('unlink', (filepath) => {
  console.log('[Watcher] 文件删除:', filepath);
  const relativePath = path.relative(CONFIG.FILE_DIR, filepath);

  broadcastToClients({
    type: 'file_removed',
    filename: relativePath
  });
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

/**
 * 获取文件信息
 */
function getFileInfo(filepath) {
  const stat = fs.statSync(filepath);
  return {
    size: stat.size,
    modified: stat.mtime,
    mimeType: getMimeType(filepath)
  };
}

/**
 * 获取 MIME 类型
 */
function getMimeType(filepath) {
  const ext = path.extname(filepath).toLowerCase();
  const mimeTypes = {
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.svg': 'image/svg+xml',
    '.md': 'text/markdown',
    '.txt': 'text/plain',
    '.json': 'application/json',
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.ts': 'application/javascript',
    '.pdf': 'application/pdf',
    '.zip': 'application/zip',
    '.log': 'text/plain'
  };
  return mimeTypes[ext] || 'application/octet-stream';
}

// ==================== 启动完成 ====================
console.log('\n========================================');
console.log('  OpenCode Remote Control Proxy Server');
console.log('========================================');
console.log(`WebSocket 端口: ${CONFIG.WS_PORT}`);
console.log(`HTTP 端口: ${CONFIG.HTTP_PORT}`);
console.log(`文件目录: ${CONFIG.FILE_DIR}`);
console.log(`OpenCode API: ${CONFIG.OPENCODE_API_URL}`);
console.log(`OpenCode 认证: ${CONFIG.OPENCODE_USERNAME}:${CONFIG.OPENCODE_PASSWORD}`);
console.log('扫码配对: 访问 http://localhost:' + CONFIG.HTTP_PORT + '/qrcode');
console.log('========================================');
console.log('\n请确保 OpenCode Serve 正在运行:');
console.log('  opencode serve --port 4096');
console.log('  或设置环境变量:');
console.log('  $env:OPENCODE_SERVER_PASSWORD="devcode123"; $env:OPENCODE_SERVER_USERNAME="devcode"; opencode serve --port 4096');
console.log('========================================\n');