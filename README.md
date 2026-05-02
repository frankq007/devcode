# DevCode 测试指南

## 系统概述

DevCode 是一个手机远程控制办公室 OpenCode AI 编程助手的系统，包含：
- **电脑端代理服务** (server/): Node.js WebSocket + HTTP 服务
- **鸿蒙 App** (entry/): 手机端控制界面

## 快速启动

### 1. 启动电脑端服务

```bash
cd server
npm start
```

服务启动后：
- WebSocket 端口: 8080
- HTTP 端口: 8081
- 二维码地址: http://localhost:8081/qrcode

### 2. 获取二维码

访问 http://localhost:8081/qrcode，会返回：
```json
{
  "success": true,
  "token": "...",
  "qrImage": "data:image/png;base64,...",
  "ip": "100.64.0.2",  // Tailscale IP 或本地 IP
  "wsPort": 8080,
  "httpPort": 8081
}
```

### 3. 配对连接

方式一（扫码）：
- 在鸿蒙 App 中点击"开始扫码"
- 扫描电脑端显示的二维码

方式二（手动输入）：
- 点击"手动输入"
- 输入服务器地址: `IP:8080`

### 4. 发送指令

配对成功后进入主控页面：
- 文字输入: 输入框中输入指令，点击"发送"
- 语音输入: 长按语音按钮说话（需实现）

### 5. 处理权限请求

当 OpenCode 需要执行敏感操作时：
- 手机端弹出权限弹窗
- 显示操作解释和命令原文
- 选择: 允许 / 拒绝 / 修改命令

## 测试步骤

### 电脑端测试

1. 启动服务:
```bash
cd server
npm start
```

2. 检查服务状态:
```bash
curl http://localhost:8081/status
```

3. 获取二维码:
```bash
curl http://localhost:8081/qrcode
```

4. 创建测试文件:
```bash
# 在 ~/opencode_output 目录创建文件
mkdir -p ~/opencode_output
echo "test content" > ~/opencode_output/test.txt
```

### 鸜蒙 App 测试

1. 在 DevEco Studio 中打开项目
2. 配置设备或模拟器（API 23，HarmonyOS 6.1）
3. 构建并运行 App
4. 在扫码页面测试连接

### 模拟完整流程

由于扫码功能需要 Scan Kit 完整集成，测试时可使用模拟数据：

在 ScanPage.ets 中，`startScan()` 方法已提供模拟流程：
```typescript
const testConfig: ConnectionConfig = {
  token: 'test-token-' + Date.now(),
  expire: Date.now() + 5 * 60 * 1000,
  ip: '127.0.0.1',  // 替换为实际 IP
  wsPort: 8080,
  httpPort: 8081
};
```

修改 `ip` 为电脑端服务的实际 IP 地址进行测试。

## 文件结构

```
DevCode/
├── server/                    # 电脑端服务
│   ├── package.json
│   └── server.js              # 主服务文件
│
├── entry/                     # 鸿蒙 App
│   └── src/main/
│       ├── ets/
│       │   ├── common/
│       │   │   ├── Types.ets          # 类型定义
│       │   │    WebSocketService.ets # WebSocket 服务
│       │   ├── components/
│       │   │   └ PermissionDialog.ets # 权限弹窗
│       │   ├── pages/
│       │   │   ├── ScanPage.ets       # 扫码配对页面
│       │   │   ├── MainPage.ets       # 主控页面
│       │   └── entryability/
│       │       └ EntryAbility.ets
│       ├── resources/
│       │   └── base/
│       │       ├── element/string.json
│       │       └── profile/main_pages.json
│       └── module.json5
│
└── Devcode.md                 # 设计文档
```

## 待完成功能

以下功能已设计但需进一步实现：

1. **语音控制** (ets/common/VoiceService.ets)
   - 使用 @ohos.speech 模块
   - 实现语音识别和指令发送

2. **Markdown 渲染** (ets/components/MarkdownRenderer.ets)
   - 安装 @luvi/lv-markdown-in
   - 配置代码高亮 (highlight.js)
   - Mermaid 图表 (WebView)

3. **文件预览** (ets/pages/FilePreviewPage.ets)
   - 图片预览
   - Markdown/文本预览
   - PDF 系统打开

4. **Scan Kit 集成**
   - 完整实现扫码功能
   - 替换 ScanPage 中的模拟代码

## 注意事项

1. **OpenCode CLI**: 电脑端需安装 OpenCode CLI 并配置环境变量
2. **Tailscale**: 推荐使用 Tailscale 进行网络穿透
3. **文件目录**: 默认使用 `~/opencode_output`，可在 server.js 中修改
4. **权限**: 确保鸿蒙 App 的麦克风、相机、网络权限已正确配置