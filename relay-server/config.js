module.exports = {
  RELAY_PORT: 8080,
  HEARTBEAT_MS: 30000,
  HEARTBEAT_TIMEOUT_MS: 60000,
  AGENT_TIMEOUT_MS: 300000,
  SSL: {
    KEY_PATH: './cert/server.key',
    CERT_PATH: './cert/server.crt'
  }
};