/**
 * OpenCode Remote Control Proxy Server
 * 
 * 功能：
 * - WebSocket 服务器：处理手机指令和权限转发
 * - Express 文件服务器：提供文件下载/上传
 * - 文件监控：监听目录变化，通知新文件
 * - 二维码生成：扫码配对认证
 * - OpenCode CLI 子进程管理
 */

const WebSocket = require('ws');
const express = require('express');
const chokidar = require('chokidar');
const QRCode = require('qrcode');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');

// 配置
const CONFIG = {
  WS_PORT: 8080,
  HTTP_PORT: 8081,
  FILE_DIR: path.join(process.env.HOME || process.env.USERPROFILE, 'opencode_output'),
  TOKEN_EXPIRE_MS: 5 * 60 * 1000, // 5分钟
  HEARTBEAT_MS: 30000
};

// 状态管理
const state = {
  pendingTokens: new Map(), // token -> { expire, ws }
  authenticatedClients: new Set(), // 已认证的 WebSocket 连接
  pendingPermRequests: new Map(), // requestId -> { ws, process }
  openCodeProcess: null,
  fileWatcher: null
};

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
function handleAuth(ws, msg) {
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
  ws.send(JSON.stringify({ type: 'auth_result', success: true, message: '配对成功' }));

  // 启动 OpenCode CLI
  startOpenCodeProcess(ws);
}

/**
 * 处理执行指令
 */
function handleExec(ws, msg) {
  if (!ws.authenticated) {
    ws.send(JSON.stringify({ type: 'error', message: '未认证' }));
    return;
  }

  const { content } = msg;
  console.log('[WS] 执行指令:', content);

  if (state.openCodeProcess) {
    state.openCodeProcess.stdin.write(content + '\n');
  } else {
    ws.send(JSON.stringify({ type: 'error', message: 'OpenCode 进程未启动' }));
  }
}

/**
 * 处理权限响应
 */
function handlePermissionResponse(ws, msg) {
  const { id, answer } = msg;
  const requestData = state.pendingPermRequests.get(id);

  if (!requestData) {
    ws.send(JSON.stringify({ type: 'error', message: '权限请求不存在' }));
    return;
  }

  console.log('[WS] 权限响应:', id, answer);

  // 将响应写入 OpenCode stdin
  if (requestData.process) {
    requestData.process.stdin.write(answer + '\n');
  }

  state.pendingPermRequests.delete(id);
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

// ==================== OpenCode CLI 子进程 ====================
/**
 * 启动 OpenCode CLI 进程
 */
function startOpenCodeProcess(ws) {
  if (state.openCodeProcess) {
    return;
  }

  console.log('[OpenCode] 启动进程...');

  // 使用 --no-yolo 禁止自动批准敏感操作
  state.openCodeProcess = spawn('opencode', ['--no-yolo'], {
    cwd: CONFIG.FILE_DIR,
    shell: true
  });

  state.openCodeProcess.stdout.on('data', (data) => {
    const text = data.toString();
    processOpenCodeOutput(ws, text);
  });

  state.openCodeProcess.stderr.on('data', (data) => {
    const text = data.toString();
    console.error('[OpenCode] stderr:', text);
    broadcastToClients({ type: 'task_status', status: 'error', content: text });
  });

  state.openCodeProcess.on('close', (code) => {
    console.log('[OpenCode] 进程退出:', code);
    state.openCodeProcess = null;
    broadcastToClients({ type: 'task_status', status: 'terminated', code });
  });

  state.openCodeProcess.on('error', (err) => {
    console.error('[OpenCode] 进程错误:', err);
    broadcastToClients({ type: 'error', message: 'OpenCode 进程启动失败' });
  });
}

/**
 * 处理 OpenCode 输出
 */
function processOpenCodeOutput(ws, text) {
  // 检查是否包含权限请求
  if (text.includes('Permission required') || text.includes('Allow') || text.includes('[y/N]')) {
    handlePermissionRequest(ws, text);
  } else {
    // 正常输出
    broadcastToClients({ type: 'task_status', status: 'running', content: text });
  }
}

/**
 * 处理权限请求
 */
function handlePermissionRequest(ws, text) {
  const requestId = uuidv4();

  // 提取命令
  const cmdMatch = text.match(/(?:Command|Allow)[:\s]+(.+?)(?:\s*\[|$)/i);
  const command = cmdMatch ? cmdMatch[1].trim() : text;

  // 生成解释（简单模板映射）
  const explanation = generatePermissionExplanation(command);

  const permRequest = {
    type: 'permission_request',
    id: requestId,
    command: command,
    explanation: explanation,
    raw: text
  };

  state.pendingPermRequests.set(requestId, { ws, process: state.openCodeProcess });

  console.log('[WS] 权限请求:', requestId, command);
  broadcastToClients(permRequest);
}

/**
 * 生成权限解释
 */
function generatePermissionExplanation(command) {
  const explanations = {
    'rm': '即将删除文件或文件夹，此操作不可撤销',
    'rmdir': '即将删除文件夹',
    'del': '即将删除文件',
    'format': '即将格式化磁盘，数据将全部丢失',
    'shutdown': '即将关闭计算机',
    'reboot': '即将重启计算机',
    'npm install': '即将安装 npm 包',
    'npm uninstall': '即将卸载 npm 包',
    'git push': '即将推送代码到远程仓库',
    'git reset': '即将重置 Git 状态',
  };

  for (const [key, desc] of Object.entries(explanations)) {
    if (command.toLowerCase().includes(key.toLowerCase())) {
      return desc;
    }
  }

  return '需要您的授权才能继续执行';
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
      httpPort: CONFIG.HTTP_PORT
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
app.get('/status', (req, res) => {
  res.json({
    wsPort: CONFIG.WS_PORT,
    httpPort: CONFIG.HTTP_PORT,
    fileDir: CONFIG.FILE_DIR,
    clients: state.authenticatedClients.size,
    openCodeRunning: state.openCodeProcess !== null,
    pendingTokens: state.pendingTokens.size
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
console.log('扫码配对: 访问 http://localhost:' + CONFIG.HTTP_PORT + '/qrcode');
console.log('========================================\n');