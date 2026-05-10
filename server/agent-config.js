module.exports = {
  RELAY_SERVER_URL: process.env.RELAY_SERVER_URL || process.env.RELAY_SERVER_URL_WSS || 'wss://39.106.208.57:9443',
  RELAY_SERVER_URL_WSS: process.env.RELAY_SERVER_URL_WSS || 'wss://39.106.208.57:9443',
  AGENT_ID: process.env.AGENT_ID || 'default-agent',
  AGENT_NAME: process.env.AGENT_NAME || 'DevCode Agent',
  HEARTBEAT_MS: 30000,
  RECONNECT_MS: 5000,
  
  OPENCODE_API_URL: process.env.OPENCODE_API_URL || 'http://127.0.0.1:4096',
  OPENCODE_USERNAME: process.env.OPENCODE_SERVER_USERNAME || 'devcode',
  OPENCODE_PASSWORD: process.env.OPENCODE_SERVER_PASSWORD || 'devcode123',
  
  DEFAULT_MODEL: {
    providerID: process.env.OPENCODE_PROVIDER || 'alibaba-cn',
    modelID: process.env.OPENCODE_MODEL || 'glm-5'
  }
};