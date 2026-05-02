# DevCode Agent Guide

Two-part remote control system for OpenCode AI:
- `server/` - Node.js WebSocket + HTTP proxy server
- `entry/` - HarmonyOS mobile app (API 23 / HarmonyOS 6.1)

## Commands

### Server
```bash
cd server && npm start      # Start proxy server
node test-client.js         # Test client (from server/)
```

### HarmonyOS App
Build and run in DevEco Studio. Target SDK: 6.1.0(23).

## Prerequisites

OpenCode Serve must be running before starting the server:
```bash
opencode serve --port 4096
```

## Environment Variables (server)

| Variable | Default |
|----------|---------|
| `OPENCODE_API_URL` | `http://127.0.0.1:4096` |
| `OPENCODE_SERVER_USERNAME` | `devcode` |
| `OPENCODE_SERVER_PASSWORD` | `devcode123` |
| `OPENCODE_PROVIDER` | `alibaba-cn` |
| `OPENCODE_MODEL` | `glm-5` |

## Ports

- WebSocket: 8080
- HTTP: 8081
- OpenCode API: 4096

## File Output

Server monitors `~/opencode_output` for generated files.

## Architecture

1. Phone app connects via WebSocket to server (port 8080)
2. Server proxies commands to OpenCode Serve API (port 4096)
3. Server uses SSE to receive OpenCode events
4. Permission requests flow: OpenCode -> Server -> Phone -> User approval -> Server -> OpenCode

## HarmonyOS Notes

- Uses `@kit.NetworkKit` for WebSocket (not a third-party library)
- Linter config: `code-linter.json5` (TypeScript ESLint + security rules)
- Build system: Hvigor
- Main entry: `entry/src/main/ets/entryability/EntryAbility.ets`