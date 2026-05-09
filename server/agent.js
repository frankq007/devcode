const WebSocket = require('ws');
const http = require('http');
const config = require('./agent-config');

const state = {
  relayWs: null,
  connectedClients: new Map(),
  currentSessionId: null,
  eventSource: null,
  lastSentMessageId: null,
  isSessionIdle: true,
  lastSentResponseId: null,
  sseReconnectTimer: null,
  reconnectTimer: null
};

function getAuthHeader() {
  const credentials = Buffer.from(`${config.OPENCODE_USERNAME}:${config.OPENCODE_PASSWORD}`).toString('base64');
  return `Basic ${credentials}`;
}

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

async function checkOpenCodeServer() {
  try {
    const result = await callOpenCodeAPI('GET', '/global/health');
    return result.healthy === true;
  } catch {
    return false;
  }
}

async function getOrCreateSession() {
  try {
    const sessions = await callOpenCodeAPI('GET', '/session');
    
    if (sessions && sessions.length > 0) {
      const latest = sessions.sort((a, b) => b.time.updated - a.time.updated)[0];
      state.currentSessionId = latest.id;
      return latest.id;
    }

    const newSession = await callOpenCodeAPI('POST', '/session', { title: 'DevCode Cloud' });
    state.currentSessionId = newSession.id;
    return newSession.id;
  } catch (err) {
    console.error('[OpenCode] Session error:', err.message);
    throw err;
  }
}

async function sendMessageToOpenCode(content, clientId) {
  if (!state.currentSessionId) {
    try {
      await getOrCreateSession();
    } catch {
      sendToRelay({ type: 'task_status', status: 'error', message: 'OpenCode 连接失败', clientId });
      return false;
    }
  }

  try {
    await callOpenCodeAPI('POST', `/session/${state.currentSessionId}/prompt_async`, {
      parts: [{ type: 'text', text: content }],
      model: config.DEFAULT_MODEL
    });
    state.lastSentResponseId = null;
    
    state.connectedClients.forEach((c, id) => {
      if (id === clientId || !clientId) {
        sendToRelay({ type: 'task_status', status: 'running', message: '正在处理...', clientId: id });
      }
    });
    
    return true;
  } catch (err) {
    console.error('[OpenCode] Send failed:', err.message);
    sendToRelay({ type: 'task_status', status: 'error', message: '发送失败', clientId });
    return false;
  }
}

function startEventListener() {
  if (state.eventSource) {
    return;
  }

  if (state.sseReconnectTimer) {
    clearTimeout(state.sseReconnectTimer);
    state.sseReconnectTimer = null;
  }

  console.log('[OpenCode] Starting SSE...');

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
      buffer = lines.pop() || '';
      
      for (const line of lines) {
        if (line.startsWith('data:')) {
          const jsonStr = line.substring(5).trim();
          if (!jsonStr) continue;
          
          try {
            const event = JSON.parse(jsonStr);
            handleOpenCodeEvent(event);
          } catch (e) {}
        }
      }
    });

    res.on('error', (err) => {
      console.error('[OpenCode] SSE error:', err.message);
      state.eventSource = null;
      scheduleSseReconnect();
    });

    res.on('end', () => {
      console.log('[OpenCode] SSE closed');
      state.eventSource = null;
      scheduleSseReconnect();
    });
  });

  req.on('error', (err) => {
    console.error('[OpenCode] SSE failed:', err.message);
    state.eventSource = null;
    scheduleSseReconnect();
  });

  req.end();
}

function scheduleSseReconnect() {
  if (state.sseReconnectTimer) return;
  
  state.sseReconnectTimer = setTimeout(() => {
    state.sseReconnectTimer = null;
    if (state.connectedClients.size > 0) {
      startEventListener();
    }
  }, 10000);
}

function handleOpenCodeEvent(event) {
  const eventType = event.type || event.name;
  
  if (eventType !== 'message.part.delta' && eventType !== 'server.heartbeat') {
    console.log('[OpenCode] Event:', eventType);
  }

  if (eventType === 'server.connected') {
    broadcastToClients({ type: 'task_status', status: 'ready', message: 'OpenCode 已连接' });
    state.isSessionIdle = true;
  } else if (eventType === 'message.updated') {
    const props = event.properties || {};
    const info = props.info || {};
    if (props.sessionID && info.id && info.role === 'assistant') {
      state.lastSentMessageId = info.id;
    }
  } else if (eventType === 'message.part.delta') {
    if (state.isSessionIdle) {
      state.isSessionIdle = false;
      broadcastToClients({ type: 'task_status', status: 'running', message: '正在处理...' });
    }
  } else if (eventType === 'session.idle') {
    if (!state.isSessionIdle) {
      broadcastToClients({ type: 'task_status', status: 'idle', message: '完成' });
    }
    state.isSessionIdle = true;
    
    if (state.lastSentMessageId && state.currentSessionId) {
      if (state.lastSentResponseId !== state.lastSentMessageId) {
        state.lastSentResponseId = state.lastSentMessageId;
        sendCompletedMessage(state.currentSessionId, state.lastSentMessageId);
      }
    }
  } else if (eventType === 'permission.request') {
    handlePermissionEvent(event.data);
  } else if (eventType === 'session.error') {
    broadcastToClients({ type: 'task_status', status: 'error', message: 'Session 错误' });
    state.isSessionIdle = true;
  }
}

async function sendCompletedMessage(sessionId, messageId) {
  if (!sessionId || !messageId) return;
  
  try {
    const msgDetail = await callOpenCodeAPI('GET', `/session/${sessionId}/message/${messageId}`);
    
    if (msgDetail?.parts) {
      const textParts = msgDetail.parts
        .filter(p => p.type === 'text')
        .map(p => p.text)
        .join('\n');

      const toolParts = msgDetail.parts
        .filter(p => p.type === 'tool' && p.tool === 'bash' && p.state?.status === 'completed')
        .map(p => {
          const cmd = p.state?.input?.command || '';
          const output = p.state?.output || '';
          return `[执行: ${cmd}]\n${output}`;
        })
        .join('\n');

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
    console.error('[OpenCode] Fetch message failed:', err.message);
  }
}

function handlePermissionEvent(data) {
  const requestId = data.id || Date.now().toString();
  broadcastToClients({
    type: 'permission_request',
    id: requestId,
    command: data.permission || data.tool || 'Unknown',
    explanation: data.message || '需要授权'
  });
}

async function respondToPermission(permissionId, answer, clientId) {
  if (!state.currentSessionId) {
    sendToRelay({ type: 'error', message: '无 session', clientId });
    return false;
  }
  
  try {
    await callOpenCodeAPI('POST', `/session/${state.currentSessionId}/permission/${permissionId}`, { answer });
    sendToRelay({ type: 'permission_ack', success: true, clientId });
    return true;
  } catch (err) {
    console.error('[OpenCode] Permission response failed:', err.message);
    sendToRelay({ type: 'error', message: '响应失败', clientId });
    return false;
  }
}

async function handleSlashCommand(command, clientId) {
  const cmd = command.toLowerCase().replace(/[,;:.]/g, '').trim().split(/\s+/)[0];
  
  switch (cmd) {
    case '/new':
      try {
        const newSession = await callOpenCodeAPI('POST', '/session', { title: 'DevCode Cloud' });
        state.currentSessionId = newSession.id;
        state.lastSentMessageId = null;
        state.lastSentResponseId = null;
        state.isSessionIdle = true;
        console.log('[OpenCode] New session:', newSession.id);
        sendToRelay({ type: 'task_status', status: 'ready', message: '新会话已创建', clientId });
        return { success: true, message: '新会话已创建' };
      } catch (err) {
        console.error('[OpenCode] Create session failed:', err.message);
        return { success: false, message: '创建失败: ' + err.message };
      }
    
    case '/help':
      return { success: true, message: '可用命令:\n/new - 创建新会话\n/help - 显示帮助' };
    
    default:
      const sent = await sendMessageToOpenCode(command, clientId);
      return { success: sent, message: sent ? '' : '发送失败' };
  }
}

function broadcastToClients(msg) {
  state.connectedClients.forEach((client, clientId) => {
    sendToRelay({ ...msg, clientId });
  });
}

function sendToRelay(msg) {
  if (state.relayWs && state.relayWs.readyState === WebSocket.OPEN) {
    state.relayWs.send(JSON.stringify(msg));
  }
}

function connectRelay() {
  console.log('[Relay] Connecting to:', config.RELAY_SERVER_URL);
  
  state.relayWs = new WebSocket(config.RELAY_SERVER_URL, {
    rejectUnauthorized: false
  });
  
  state.relayWs.on('open', async () => {
    console.log('[Relay] Connected');
    
    state.relayWs.send(JSON.stringify({
      type: 'agent_register',
      agentId: config.AGENT_ID,
      name: config.AGENT_NAME
    }));
    
    const healthy = await checkOpenCodeServer();
    if (!healthy) {
      console.warn('[OpenCode] OpenCode Serve not running');
    } else {
      try {
        await getOrCreateSession();
        startEventListener();
        console.log('[OpenCode] Connected, session:', state.currentSessionId);
      } catch (err) {
        console.error('[OpenCode] Connection failed:', err.message);
      }
    }
  });
  
  state.relayWs.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      handleRelayMessage(msg);
    } catch (e) {
      console.error('[Relay] Parse error:', e.message);
    }
  });
  
  state.relayWs.on('close', () => {
    console.log('[Relay] Disconnected');
    state.relayWs = null;
    scheduleReconnect();
  });
  
  state.relayWs.on('error', (err) => {
    console.error('[Relay] Error:', err.message);
  });
  
  const heartbeatInterval = setInterval(() => {
    if (state.relayWs && state.relayWs.readyState === WebSocket.OPEN) {
      state.relayWs.send(JSON.stringify({ type: 'ping' }));
    }
  }, config.HEARTBEAT_MS);
  
  state.relayWs.on('close', () => {
    clearInterval(heartbeatInterval);
  });
}

function handleRelayMessage(msg) {
  switch (msg.type) {
    case 'agent_registered':
      console.log('[Relay] Registered:', msg.agentId);
      break;
      
    case 'client_attached':
      state.connectedClients.set(msg.clientId, { connectedAt: Date.now() });
      console.log('[Relay] Client attached:', msg.clientId);
      if (!state.eventSource && state.currentSessionId) {
        startEventListener();
      }
      break;
      
    case 'client_detached':
      state.connectedClients.delete(msg.clientId);
      console.log('[Relay] Client detached:', msg.clientId);
      break;
      
    case 'exec':
      handleExec(msg);
      break;
      
    case 'permission_response':
      respondToPermission(msg.id, msg.answer, msg.clientId);
      break;
      
    case 'pong':
      break;
      
    default:
      console.log('[Relay] Unknown message:', msg.type);
  }
}

async function handleExec(msg) {
  const { content, requestId, clientId } = msg;
  
  if (content.startsWith('/')) {
    const result = await handleSlashCommand(content, clientId);
    sendToRelay({ type: 'exec_ack', success: result.success, message: result.message, requestId, clientId });
    return;
  }
  
  const sent = await sendMessageToOpenCode(content, clientId);
  sendToRelay({ type: 'exec_ack', success: sent, requestId, clientId });
}

function scheduleReconnect() {
  if (state.reconnectTimer) return;
  
  state.reconnectTimer = setTimeout(() => {
    state.reconnectTimer = null;
    connectRelay();
  }, config.RECONNECT_MS);
}

console.log('========================================');
console.log('  DevCode Agent');
console.log('========================================');
console.log(`Relay: ${config.RELAY_SERVER_URL}`);
console.log(`Agent: ${config.AGENT_ID} (${config.AGENT_NAME})`);
console.log(`Model: ${config.DEFAULT_MODEL.providerID}/${config.DEFAULT_MODEL.modelID}`);
console.log('\n请先运行: opencode serve --port 4096');
console.log('========================================\n');

connectRelay();