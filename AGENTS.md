# DevCode Agent Guide

Two-part remote control system for OpenCode AI:
- `server/` - Node.js WebSocket + HTTP proxy server
- `entry/` - HarmonyOS mobile app (API 23 / HarmonyOS 6.1)

## Commands

### Server (Node.js)
```bash
cd server && npm start              # Start proxy server
cd server && npm run dev            # Development mode (same as start)
node server/test-client.js          # Test WebSocket client
```

### HarmonyOS App (ArkTS)
```bash
# Build via DevEco Studio or Hvigor CLI
hvigorw clean                       # Clean build artifacts
hvigorw assembleHap                 # Build HAP package (debug)
hvigorw assembleHap --mode release  # Build HAP package (release)

# Run tests
hvigorw test@entry                  # Run all unit tests in entry module
hvigorw test@entry --module entry@ohosTest  # Run instrumented tests

# Run single test file (via hypium)
# Modify entry/src/test/List.test.ets to import specific test suite
hvigorw test@entry
```

### Testing Framework
- Unit tests: `entry/src/test/*.test.ets` (local unit tests)
- Instrumented tests: `entry/src/ohosTest/ets/test/*.test.ets` (device tests)
- Framework: `@ohos/hypium` with `describe`, `it`, `expect` pattern
- Mocking: `@ohos/hamock` available for mocks

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

## Code Style Guidelines

### ArkTS (HarmonyOS) - STRICT TYPE SAFETY

**Imports:**
```typescript
// Use @kit.* for HarmonyOS APIs
import { webSocket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';

// Use 'import type' for type-only imports
import type { ServerConfig } from './Types';

// Relative imports for local modules
import { WebSocketService } from '../common/WebSocketService';
```

**Types:**
- NEVER use `any` or `unknown` - use explicit types
- NEVER use `as` type assertions - let compiler infer
- NEVER use structural typing - use explicit `interface` or `class`
- NEVER use dynamic property access (e.g., `obj[dynamicKey]`)
- Object literals MUST have explicit type context (typed variable or typed function parameter)
- Use `ESObject` for external/unknown structures when unavoidable

**Interfaces:**
```typescript
export interface ServerConfig {
  id: string;
  name: string;
  port: number;
  isDefault: boolean;
}
```

**Components:**
```typescript
@Entry
@Component
struct MyPage {
  @State message: string = '';       // Reactive state
  @Prop config: ServerConfig;        // Immutable prop from parent
  
  // Function callbacks WITHOUT decorators
  onConfirm: () => void = () => {};
  
  build() {
    Column() {
      Text(this.message)
    }
  }
}
```

**Naming Conventions:**
- Files: `PascalCase.ets` for components, `camelCase.ets` for services
- Classes/Components: `PascalCase`
- Functions/Methods: `camelCase`
- Constants: `UPPER_SNAKE_CASE` or `camelCase`
- Private members: No prefix, just use `private` keyword

**Error Handling:**
```typescript
// Use try-catch for async operations
try {
  await someAsyncOperation();
} catch (e) {
  hilog.error(DOMAIN, TAG, 'Error: %{public}s', JSON.stringify(e));
}

// Use Promise with explicit error handling
return new Promise<boolean>((resolve, reject) => {
  // ...
});
```

**Logging:**
```typescript
const DOMAIN = 0xFF00;
const TAG = 'MyComponent';

hilog.info(DOMAIN, TAG, 'Message: %{public}s', value);
hilog.error(DOMAIN, TAG, 'Error: %{public}s', err.message);
```

### Node.js (Server)

**Style:**
- CommonJS modules (`require` / `module.exports`)
- Async/await for asynchronous operations
- Descriptive function and variable names
- JSDoc comments for public functions

**Error Handling:**
```javascript
try {
  await operation();
} catch (error) {
  console.error('Context:', error);
  // Handle or rethrow
}
```

## HarmonyOS Specific Notes

- Uses `@kit.NetworkKit` for WebSocket (not a third-party library)
- Linter config: `code-linter.json5` (TypeScript ESLint + security rules)
- Build system: Hvigor
- Main entry: `entry/src/main/ets/entryability/EntryAbility.ets`
- Target SDK: 6.1.0(23)
- Strict mode enabled: case-sensitive checks, normalized OHM URLs

## Linting Rules

Configured in `code-linter.json5`:
- TypeScript ESLint recommended rules
- Performance plugin recommended rules
- Security rules (error level):
  - `@security/no-unsafe-aes`
  - `@security/no-unsafe-hash`
  - `@security/no-unsafe-rsa-*`
  - `@security/no-unsafe-3des`

## Testing Best Practices

**Unit Test Structure:**
```typescript
import { describe, beforeAll, it, expect } from '@ohos/hypium';

export default function myTestSuite() {
  describe('MyFeature', () => {
    beforeAll(() => {
      // Setup
    });
    
    it('should work correctly', 0, () => {
      const result = someFunction();
      expect(result).assertEqual(expected);
    });
  });
}
```

**Test Organization:**
- Group related tests in `describe` blocks
- Use `beforeAll`/`beforeEach` for setup
- Use `afterAll`/`afterEach` for cleanup
- Test file naming: `*.test.ets`

## Common Patterns

**Service Pattern:**
```typescript
export class MyService {
  private static instance: MyService | null = null;
  
  static getInstance(): MyService {
    if (!MyService.instance) {
      MyService.instance = new MyService();
    }
    return MyService.instance;
  }
}
```

**Component Communication:**
- Parent to child: `@Prop` decorated properties
- Child to parent: Callback functions (no decorators)
- Global state: Service singleton pattern
