#!/bin/bash

# DevCode 云中转服务器一键部署脚本
# 服务器 IP: 39.106.208.57

set -e

echo "========================================"
echo "  DevCode Relay Server Deployment"
echo "========================================"

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 或 sudo 执行此脚本"
  exit 1
fi

# 1. 安装依赖
echo "[1/6] 安装 Node.js 和 Nginx..."
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

if ! command -v nginx &> /dev/null; then
  apt install -y nginx
fi

# 2. 创建目录
echo "[2/6] 创建部署目录..."
mkdir -p /opt/devcode/relay-server
mkdir -p /opt/devcode/cert

# 3. 生成 SSL 证书 (自签名)
echo "[3/6] 生成 SSL 证书..."
openssl genrsa -out /opt/devcode/cert/server.key 2048
openssl req -new -x509 -days 365 -key /opt/devcode/cert/server.key \
  -out /opt/devcode/cert/server.crt \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=DevCode/OU=Relay/CN=39.106.208.57"

# 4. 创建服务文件
echo "[4/6] 创建中转服务器文件..."

# package.json
cat > /opt/devcode/relay-server/package.json << 'PKGJSON'
{
  "name": "relay-server",
  "version": "1.0.0",
  "dependencies": {
    "ws": "^8.18.0",
    "uuid": "^9.0.0"
  }
}
PKGJSON

# config.js
cat > /opt/devcode/relay-server/config.js << 'CONFIGJS'
module.exports = {
  RELAY_PORT: 8080,
  HEARTBEAT_MS: 30000,
  HEARTBEAT_TIMEOUT_MS: 60000,
  AGENT_TIMEOUT_MS: 300000
};
CONFIGJS

# server.js
cat > /opt/devcode/relay-server/server.js << 'SERVERJS'
const WebSocket = require('ws');
const { v4: uuidv4 } = require('uuid');
const config = require('./config');

const state = {
  agents: new Map(),
  clients: new Map()
};

const wss = new WebSocket.Server({ port: config.RELAY_PORT });

console.log(`[Relay] Server started on port ${config.RELAY_PORT}`);

wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.type = null;
  ws.id = null;
  ws.linkedAgentId = null;
  
  ws.on('pong', () => { ws.isAlive = true; });
  
  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      handleMessage(ws, msg);
    } catch (e) {
      console.error('[Relay] Parse error:', e.message);
    }
  });
  
  ws.on('close', () => {
    cleanupConnection(ws);
  });
});

const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) {
      cleanupConnection(ws);
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, config.HEARTBEAT_MS);

function handleMessage(ws, msg) {
  switch (msg.type) {
    case 'agent_register':
      handleAgentRegister(ws, msg);
      break;
    case 'client_connect':
      handleClientConnect(ws, msg);
      break;
    case 'exec':
      handleExec(ws, msg);
      break;
    case 'ai_response':
      handleAiResponse(ws, msg);
      break;
    case 'task_status':
      handleTaskStatus(ws, msg);
      break;
    case 'permission_request':
      handlePermissionRequest(ws, msg);
      break;
    case 'permission_response':
      handlePermissionResponse(ws, msg);
      break;
    case 'pong':
      ws.isAlive = true;
      break;
    case 'ping':
      ws.send(JSON.stringify({ type: 'pong' }));
      break;
  }
}

function handleAgentRegister(ws, msg) {
  const agentId = msg.agentId || uuidv4();
  const agentName = msg.name || 'Unnamed Agent';
  
  ws.type = 'agent';
  ws.id = agentId;
  ws.name = agentName;
  ws.isAlive = true;
  
  state.agents.set(agentId, { ws, name: agentName, connectedAt: Date.now() });
  
  ws.send(JSON.stringify({ type: 'agent_registered', success: true, agentId }));
  console.log(`[Relay] Agent registered: ${agentId} (${agentName})`);
}

function handleClientConnect(ws, msg) {
  const agentId = msg.agentId;
  
  if (!agentId || !state.agents.has(agentId)) {
    ws.send(JSON.stringify({ type: 'client_connected', success: false, message: 'Agent not found' }));
    return;
  }
  
  const clientId = uuidv4();
  ws.type = 'client';
  ws.id = clientId;
  ws.linkedAgentId = agentId;
  ws.isAlive = true;
  
  state.clients.set(clientId, { ws, linkedAgentId: agentId, connectedAt: Date.now() });
  
  ws.send(JSON.stringify({ type: 'client_connected', success: true, clientId, agentName: state.agents.get(agentId).name }));
  
  const agentWs = state.agents.get(agentId).ws;
  if (agentWs && agentWs.readyState === WebSocket.OPEN) {
    agentWs.send(JSON.stringify({ type: 'client_attached', clientId }));
  }
  
  console.log(`[Relay] Client connected: ${clientId} -> Agent ${agentId}`);
}

function handleExec(ws, msg) {
  if (ws.type !== 'client' || !ws.linkedAgentId) return;
  
  const agentWs = state.agents.get(ws.linkedAgentId)?.ws;
  if (!agentWs || agentWs.readyState !== WebSocket.OPEN) return;
  
  agentWs.send(JSON.stringify({ type: 'exec', content: msg.content, requestId: msg.requestId || uuidv4(), clientId: ws.id }));
}

function handleAiResponse(ws, msg) {
  if (ws.type !== 'agent') return;
  
  const clientWs = state.clients.get(msg.clientId)?.ws;
  if (clientWs && clientWs.readyState === WebSocket.OPEN) {
    clientWs.send(JSON.stringify({ type: 'ai_response', content: msg.content, messageID: msg.messageID, requestId: msg.requestId }));
  }
}

function handleTaskStatus(ws, msg) {
  if (ws.type !== 'agent') return;
  
  const clientWs = state.clients.get(msg.clientId)?.ws;
  if (clientWs && clientWs.readyState === WebSocket.OPEN) {
    clientWs.send(JSON.stringify({ type: 'task_status', status: msg.status, message: msg.message }));
  }
}

function handlePermissionRequest(ws, msg) {
  if (ws.type !== 'agent') return;
  
  const clientWs = state.clients.get(msg.clientId)?.ws;
  if (clientWs && clientWs.readyState === WebSocket.OPEN) {
    clientWs.send(JSON.stringify({ type: 'permission_request', id: msg.id, command: msg.command, explanation: msg.explanation }));
  }
}

function handlePermissionResponse(ws, msg) {
  if (ws.type !== 'client' || !ws.linkedAgentId) return;
  
  const agentWs = state.agents.get(ws.linkedAgentId)?.ws;
  if (agentWs && agentWs.readyState === WebSocket.OPEN) {
    agentWs.send(JSON.stringify({ type: 'permission_response', id: msg.id, answer: msg.answer, clientId: ws.id }));
  }
}

function cleanupConnection(ws) {
  if (ws.type === 'agent') {
    state.agents.delete(ws.id);
    console.log(`[Relay] Agent disconnected: ${ws.id}`);
    
    state.clients.forEach((client, clientId) => {
      if (client.linkedAgentId === ws.id) {
        if (client.ws && client.ws.readyState === WebSocket.OPEN) {
          client.ws.send(JSON.stringify({ type: 'error', message: 'Agent disconnected' }));
        }
        state.clients.delete(clientId);
      }
    });
  } else if (ws.type === 'client') {
    state.clients.delete(ws.id);
    console.log(`[Relay] Client disconnected: ${ws.id}`);
  }
}

console.log('========================================');
console.log('  Relay Server Ready');
console.log('========================================');
SERVERJS

# 5. 安装依赖并启动服务
echo "[5/6] 安装 Node.js 依赖..."
cd /opt/devcode/relay-server
npm install

# 安装 PM2
npm install -g pm2

# 6. 配置 Nginx
echo "[6/6] 配置 Nginx SSL 代理..."

cat > /etc/nginx/sites-available/devcode-relay << 'NGINXCONF'
upstream relay_backend {
    server 127.0.0.1:8080;
}

server {
    listen 443 ssl;
    server_name 39.106.208.57;

    ssl_certificate /opt/devcode/cert/server.crt;
    ssl_certificate_key /opt/devcode/cert/server.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://relay_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }
}

server {
    listen 80;
    server_name 39.106.208.57;
    return 301 https://$server_name$request_uri;
}
NGINXCONF

ln -sf /etc/nginx/sites-available/devcode-relay /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl restart nginx

# 启动 Relay Server
pm2 start server.js --name relay-server
pm2 save
pm2 startup | tail -1 | bash

echo ""
echo "========================================"
echo "  部署完成!"
echo "========================================"
echo ""
echo "云中转服务器地址: wss://39.106.208.57"
echo ""
echo "本地 Agent 连接命令:"
echo "  RELAY_SERVER_URL=wss://39.106.208.57 AGENT_ID=my-agent AGENT_NAME=\"My Agent\" node agent.js"
echo ""
echo "手机 App 配置:"
echo "  云服务器: wss://39.106.208.57"
echo "  Agent ID: my-agent"
echo ""
echo "查看日志: pm2 logs relay-server"
echo "重启服务: pm2 restart relay-server"
echo "========================================"