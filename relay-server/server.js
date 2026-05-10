const WebSocket = require('ws');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');
const config = require('./config');

const state = {
  agents: new Map(),
  clients: new Map(),
  pendingTokens: new Map()
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
  
  ws.on('error', (err) => {
    console.error('[Relay] Connection error:', err.message);
    cleanupConnection(ws);
  });
});

const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) {
      console.log('[Relay] Heartbeat timeout, terminating');
      cleanupConnection(ws);
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, config.HEARTBEAT_MS);

wss.on('close', () => {
  clearInterval(heartbeatInterval);
});

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
    case 'stream_start':
      handleStreamStart(ws, msg);
      break;
    case 'stream_delta':
      handleStreamDelta(ws, msg);
      break;
    case 'pong':
      ws.isAlive = true;
      break;
    case 'ping':
      ws.send(JSON.stringify({ type: 'pong' }));
      break;
    default:
      console.log('[Relay] Unknown message type:', msg.type);
  }
}

function handleAgentRegister(ws, msg) {
  const agentId = msg.agentId || uuidv4();
  const agentName = msg.name || 'Unnamed Agent';
  
  ws.type = 'agent';
  ws.id = agentId;
  ws.name = agentName;
  ws.isAlive = true;
  
  state.agents.set(agentId, {
    ws,
    name: agentName,
    connectedAt: Date.now()
  });
  
  ws.send(JSON.stringify({
    type: 'agent_registered',
    success: true,
    agentId: agentId
  }));
  
  console.log(`[Relay] Agent registered: ${agentId} (${agentName})`);
  broadcastAgentList();
}

function handleClientConnect(ws, msg) {
  const agentId = msg.agentId;
  
  if (!agentId || !state.agents.has(agentId)) {
    ws.send(JSON.stringify({
      type: 'client_connected',
      success: false,
      message: 'Agent not found'
    }));
    return;
  }
  
  const clientId = uuidv4();
  ws.type = 'client';
  ws.id = clientId;
  ws.linkedAgentId = agentId;
  ws.isAlive = true;
  
  state.clients.set(clientId, {
    ws,
    linkedAgentId: agentId,
    connectedAt: Date.now()
  });
  
  ws.send(JSON.stringify({
    type: 'client_connected',
    success: true,
    clientId: clientId,
    agentName: state.agents.get(agentId).name
  }));
  
  const agentWs = state.agents.get(agentId).ws;
  if (agentWs && agentWs.readyState === WebSocket.OPEN) {
    agentWs.send(JSON.stringify({
      type: 'client_attached',
      clientId: clientId
    }));
  }
  
  console.log(`[Relay] Client connected: ${clientId} -> Agent ${agentId}`);
}

function handleExec(ws, msg) {
  if (ws.type !== 'client' || !ws.linkedAgentId) {
    ws.send(JSON.stringify({ type: 'error', message: 'Not connected to agent' }));
    return;
  }
  
  const agentWs = state.agents.get(ws.linkedAgentId)?.ws;
  if (!agentWs || agentWs.readyState !== WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'error', message: 'Agent disconnected' }));
    return;
  }
  
  agentWs.send(JSON.stringify({
    type: 'exec',
    content: msg.content,
    requestId: msg.requestId || uuidv4(),
    clientId: ws.id
  }));
  
  console.log(`[Relay] Exec forwarded: Client ${ws.id} -> Agent ${ws.linkedAgentId}`);
}

function handleAiResponse(ws, msg) {
  if (ws.type !== 'agent') {
    console.log('[Relay] ai_response from non-agent, ignored');
    return;
  }
  
  const clientId = msg.clientId;
  if (!clientId || !state.clients.has(clientId)) {
    console.log('[Relay] Client not found for ai_response');
    return;
  }
  
  const clientWs = state.clients.get(clientId).ws;
  if (clientWs && clientWs.readyState === WebSocket.OPEN) {
    clientWs.send(JSON.stringify({
      type: 'ai_response',
      content: msg.content,
      messageID: msg.messageID,
      requestId: msg.requestId
    }));
  }
  
  console.log(`[Relay] AI response forwarded: Agent ${ws.id} -> Client ${clientId}`);
}

function handleTaskStatus(ws, msg) {
  if (ws.type !== 'agent') {
    return;
  }
  
  const clientId = msg.clientId;
  if (!clientId || !state.clients.has(clientId)) {
    return;
  }
  
  const clientWs = state.clients.get(clientId).ws;
  if (clientWs && clientWs.readyState === WebSocket.OPEN) {
    clientWs.send(JSON.stringify({
      type: 'task_status',
      status: msg.status,
      message: msg.message
    }));
  }
}

function handlePermissionRequest(ws, msg) {
  if (ws.type !== 'agent') {
    return;
  }
  
  const clientId = msg.clientId;
  if (!clientId || !state.clients.has(clientId)) {
    return;
  }
  
  const clientWs = state.clients.get(clientId).ws;
  if (clientWs && clientWs.readyState === WebSocket.OPEN) {
    clientWs.send(JSON.stringify({
      type: 'permission_request',
      id: msg.id,
      command: msg.command,
      explanation: msg.explanation
    }));
  }
  
  console.log(`[Relay] Permission request forwarded: Agent ${ws.id} -> Client ${clientId}`);
}

function handlePermissionResponse(ws, msg) {
  if (ws.type !== 'client' || !ws.linkedAgentId) {
    return;
  }
  
  const agentWs = state.agents.get(ws.linkedAgentId)?.ws;
  if (!agentWs || agentWs.readyState !== WebSocket.OPEN) {
    return;
  }
  
  agentWs.send(JSON.stringify({
    type: 'permission_response',
    id: msg.id,
    answer: msg.answer,
    clientId: ws.id
  }));
  
  console.log(`[Relay] Permission response forwarded: Client ${ws.id} -> Agent ${ws.linkedAgentId}`);
}

function handleStreamStart(ws, msg) {
  if (ws.type !== 'agent') {
    return;
  }
  
  const clientId = msg.clientId;
  if (!clientId || !state.clients.has(clientId)) {
    return;
  }
  
  const clientWs = state.clients.get(clientId).ws;
  if (clientWs && clientWs.readyState === WebSocket.OPEN) {
    clientWs.send(JSON.stringify({
      type: 'stream_start',
      messageID: msg.messageID
    }));
  }
  
  console.log(`[Relay] Stream start forwarded: Agent ${ws.id} -> Client ${clientId}`);
}

function handleStreamDelta(ws, msg) {
  if (ws.type !== 'agent') {
    return;
  }
  
  const clientId = msg.clientId;
  if (!clientId || !state.clients.has(clientId)) {
    return;
  }
  
  const clientWs = state.clients.get(clientId).ws;
  if (clientWs && clientWs.readyState === WebSocket.OPEN) {
    clientWs.send(JSON.stringify({
      type: 'stream_delta',
      deltaType: msg.deltaType,
      content: msg.content,
      toolId: msg.toolId,
      toolName: msg.toolName,
      toolInput: msg.toolInput,
      toolOutput: msg.toolOutput,
      toolStatus: msg.toolStatus,
      progress: msg.progress
    }));
  }
}

function cleanupConnection(ws) {
  if (ws.type === 'agent') {
    state.agents.delete(ws.id);
    console.log(`[Relay] Agent disconnected: ${ws.id}`);
    broadcastAgentList();
    
    state.clients.forEach((client, clientId) => {
      if (client.linkedAgentId === ws.id) {
        if (client.ws && client.ws.readyState === WebSocket.OPEN) {
          client.ws.send(JSON.stringify({
            type: 'error',
            message: 'Agent disconnected'
          }));
        }
        state.clients.delete(clientId);
      }
    });
  } else if (ws.type === 'client') {
    state.clients.delete(ws.id);
    console.log(`[Relay] Client disconnected: ${ws.id}`);
    
    if (ws.linkedAgentId && state.agents.has(ws.linkedAgentId)) {
      const agentWs = state.agents.get(ws.linkedAgentId).ws;
      if (agentWs && agentWs.readyState === WebSocket.OPEN) {
        agentWs.send(JSON.stringify({
          type: 'client_detached',
          clientId: ws.id
        }));
      }
    }
  }
}

function broadcastAgentList() {
  const agentList = [];
  state.agents.forEach((agent, agentId) => {
    agentList.push({
      agentId: agentId,
      name: agent.name,
      connectedAt: agent.connectedAt
    });
  });
  
  state.clients.forEach((client) => {
    if (client.ws && client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(JSON.stringify({
        type: 'agent_list',
        agents: agentList
      }));
    }
  });
}

setInterval(() => {
  const now = Date.now();
  
  state.agents.forEach((agent, agentId) => {
    if (now - agent.connectedAt > config.AGENT_TIMEOUT_MS) {
      if (!agent.ws.isAlive) {
        console.log(`[Relay] Agent timeout: ${agentId}`);
        cleanupConnection(agent.ws);
        agent.ws.terminate();
      }
    }
  });
}, config.HEARTBEAT_TIMEOUT_MS);

console.log('========================================');
console.log('  Relay Server for DevCode');
console.log('========================================');
console.log(`Port: ${config.RELAY_PORT}`);
console.log('Waiting for agents and clients...');
console.log('========================================');