/**
 * WebSocket 测试客户端
 * 用于验证服务器功能
 */

const WebSocket = require('ws');

const WS_URL = 'ws://localhost:8080';

console.log('=== DevCode WebSocket 测试客户端 ===\n');

// 连接服务器
const ws = new WebSocket(WS_URL);

ws.on('open', () => {
  console.log('[✓] 已连接到服务器');
  
  // 发送认证消息（使用测试 token）
  // 实际 token 需要从 /qrcode 接口获取
  const testToken = 'test-token-' + Date.now();
  
  console.log('[→] 发送认证请求...');
  ws.send(JSON.stringify({
    type: 'auth',
    token: testToken
  }));
});

ws.on('message', (data) => {
  try {
    const msg = JSON.parse(data.toString());
    console.log('[←] 收到消息:', msg.type);
    
    switch (msg.type) {
      case 'auth_result':
        if (msg.success) {
          console.log('[✓] 认证成功');
          console.log('[i] 消息:', msg.message);
          
          // 认证成功后发送测试指令
          setTimeout(() => {
            console.log('\n[→] 发送测试指令...');
            ws.send(JSON.stringify({
              type: 'exec',
              content: '# 创建一个测试文件 hello.txt'
            }));
          }, 1000);
          
        } else {
          console.log('[✗] 认证失败');
          console.log('[i] 原因:', msg.message);
          console.log('\n提示: 请先访问 http://localhost:8081/qrcode 获取有效 token');
        }
        break;
        
      case 'task_status':
        console.log('[i] 任务状态:', msg.status);
        if (msg.content) {
          console.log('[i] 内容:', msg.content.substring(0, 100));
        }
        break;
        
      case 'permission_request':
        console.log('[⚠] 权限请求:', msg.id);
        console.log('[i] 命令:', msg.command);
        console.log('[i] 解释:', msg.explanation);
        
        // 自动允许（测试用）
        console.log('[→] 自动允许...');
        ws.send(JSON.stringify({
          type: 'permission_response',
          id: msg.id,
          answer: 'y'
        }));
        break;
        
      case 'file_added':
        console.log('[i] 新文件:', msg.filename);
        console.log('[i] URL:', msg.url);
        break;
        
      case 'file_list':
        console.log('[i] 文件列表:', msg.files.length, '个文件');
        break;
        
      case 'error':
        console.log('[✗] 错误:', msg.message);
        break;
        
      default:
        console.log('[i] 消息:', msg);
    }
  } catch (e) {
    console.log('[←] 收到数据:', data.toString().substring(0, 100));
  }
});

ws.on('close', (code, reason) => {
  console.log('\n[✗] 连接关闭');
  console.log('[i] Code:', code);
  console.log('[i] Reason:', reason.toString());
});

ws.on('error', (err) => {
  console.log('\n[✗] 连接错误:', err.message);
});

// 处理用户输入
process.stdin.on('data', (data) => {
  const input = data.toString().trim();
  
  if (input === 'exit' || input === 'quit') {
    console.log('[i] 退出...');
    ws.close();
    process.exit(0);
  }
  
  if (input.startsWith('exec ')) {
    const command = input.substring(5);
    console.log('[→] 发送指令:', command);
    ws.send(JSON.stringify({
      type: 'exec',
      content: command
    }));
  }
  
  if (input === 'files') {
    console.log('[→] 请求文件列表...');
    ws.send(JSON.stringify({
      type: 'list_files'
    }));
  }
});

console.log('\n可用命令:');
console.log('  exec <命令>  - 发送指令');
console.log('  files        - 获取文件列表');
console.log('  exit         - 退出');