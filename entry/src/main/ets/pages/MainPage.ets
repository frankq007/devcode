/**
 * 主控页面 (ArkTS 兼容版本)
 */
 
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { wsService } from '../common/WebSocketService';
import { PermissionDialog } from '../components/PermissionDialog';
import type { FileInfo, TaskMessage, ConnectionConfig } from '../common/Types';
 
const DOMAIN = 0xFF00;
const TAG = 'MainPage';

// DEBUG: 固定配置 - 使用 ConnectionConfig 类型
const DEBUG_CONFIG: ConnectionConfig = {
  ip: '100.117.37.34',
  wsPort: 8080,
  httpPort: 8081,
  token: 'debug-token-' + Date.now().toString(),
  expire: Date.now() + 5 * 60 * 1000
};

@Entry
@Component
struct MainPage {
  @State messages: TaskMessage[] = [];
  @State files: FileInfo[] = [];
  @State inputText: string = '';
  @State showPermissionDialog: boolean = false;
  @State currentPermissionId: string = '';
  @State currentPermissionCommand: string = '';
  @State currentPermissionExplanation: string = '';
  @State connectionStatus: string = '连接中...';
  @State serverIp: string = DEBUG_CONFIG.ip;
  @State httpPort: number = DEBUG_CONFIG.httpPort;
  @State isRecording: boolean = false;
  @State lastAiMessageId: string = '';

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, '=== MainPage aboutToAppear (DEBUG MODE) ===');
    hilog.info(DOMAIN, TAG, 'Server IP: %{public}s', this.serverIp);
    hilog.info(DOMAIN, TAG, 'HTTP Port: %{public}d', this.httpPort);

    // DEBUG: 直接连接
    this.connectionStatus = '正在连接...';
    wsService.connect(DEBUG_CONFIG).then((success: boolean) => {
      hilog.info(DOMAIN, TAG, 'Connect result: %{public}s', success ? 'SUCCESS' : 'FAILED');
      if (success) {
        this.connectionStatus = '已连接(调试模式)';
        hilog.info(DOMAIN, TAG, 'WebSocket connected, waiting for auth...');
      } else {
        this.connectionStatus = '连接失败';
        hilog.error(DOMAIN, TAG, 'WebSocket connect failed');
      }
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'Connect error: %{public}s', e.message);
      this.connectionStatus = '连接错误: ' + e.message;
    });

    wsService.onMessage((msg: ESObject) => {
      hilog.info(DOMAIN, TAG, '>>> Received WS message type: %{public}s', msg['type'] as string);
      this.handleMessage(msg);
    });

    wsService.onStatusChange((connected: boolean) => {
      hilog.info(DOMAIN, TAG, '>>> Status changed: %{public}s', connected ? 'CONNECTED' : 'DISCONNECTED');
      this.connectionStatus = connected ? '已连接' : '已断开';
    });

    hilog.info(DOMAIN, TAG, 'MainPage initialized (DEBUG)');
  }
 
  build() {
    Stack() {
      // 主内容
      Column() {
        Row() {
          Text($r('app.string.main_title'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold);
 
          Blank()
 
          Row() {
            Circle()
              .width(10)
              .height(10)
              .fill(this.connectionStatus === '已连接' ? '#4CAF50' : '#FF5722');
 
            Text(this.connectionStatus)
              .fontSize(14)
              .fontColor('#888888')
              .margin({ left: 5 })
          }
        }
        .width('100%')
        .height(50)
        .padding({ left: 20, right: 20 })
        .backgroundColor('#FFFFFF')
 
        List() {
          ForEach(this.messages, (msg: TaskMessage) => {
            ListItem() {
              MessageItem({ message: msg })
            }
          }, (msg: TaskMessage) => msg.id)
        }
        .width('100%')
        .height('50%')
        .backgroundColor('#F5F5F5')
        .divider({ strokeWidth: 1, color: '#EEEEEE', startMargin: 10, endMargin: 10 })
 
        Column() {
          Text($r('app.string.files_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 10 })
 
          if (this.files.length > 0) {
            List() {
              ForEach(this.files, (file: FileInfo) => {
                ListItem() {
                  FileItem({ file: file, serverIp: this.serverIp, httpPort: this.httpPort })
                }
              }, (file: FileInfo) => file.path)
            }
            .width('100%')
            .height(120)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
          } else {
            Text('暂无文件')
              .fontSize(14)
              .fontColor('#888888')
              .height(120)
          }
        }
        .width('100%')
        .padding(20)
        .backgroundColor('#FFFFFF')
 
        Row() {
          Column() {
            Image($r('app.media.startIcon'))
              .width(30)
              .height(30)
              .fillColor(this.isRecording ? '#FF5722' : '#4CAF50')
 
            Text($r('app.string.voice_hint'))
              .fontSize(12)
              .fontColor(this.isRecording ? '#FF5722' : '#888888')
          }
          .width(60)
          .height(60)
          .borderRadius(8)
          .backgroundColor('#EEEEEE')
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.toggleRecording()
          })
 
          TextInput({ placeholder: '输入指令...', text: this.inputText })
            .width('60%')
            .height(50)
            .margin({ left: 10 })
            .onChange((value: string) => {
              this.inputText = value
            })
 
          Button($r('app.string.send_command'))
            .width('20%')
            .height(50)
            .backgroundColor('#4CAF50')
            .margin({ left: 10 })
            .onClick(() => {
              this.sendCommand()
            })
        }
        .width('100%')
        .height(80)
        .padding({ left: 10, right: 10 })
        .backgroundColor('#FFFFFF')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F5F5')
 
      // 权限弹窗覆盖层
      if (this.showPermissionDialog) {
        PermissionDialog({
          requestId: this.currentPermissionId,
          command: this.currentPermissionCommand,
          explanation: this.currentPermissionExplanation,
          onAllow: () => {
            this.replyPermission('y')
          },
          onDeny: () => {
            this.replyPermission('n')
          },
          onModify: (newCmd: string) => {
            this.replyPermission(newCmd)
          },
          onClose: () => {
            this.showPermissionDialog = false
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
 
handleMessage(msg: ESObject): void {
    const msgType: string = msg['type'] as string
    hilog.info(DOMAIN, TAG, '>>> handleMessage: type=%{public}s', msgType)

    if (msgType === 'ai_response') {
      hilog.info(DOMAIN, TAG, '>>> AI_RESPONSE received!');
      this.handleAiResponse(msg)
    } else if (msgType === 'task_status') {
      hilog.info(DOMAIN, TAG, '>>> TASK_STATUS: %{public}s', msg['status'] as string);
      this.handleTaskStatus(msg)
    } else if (msgType === 'permission_request') {
      hilog.info(DOMAIN, TAG, '>>> PERMISSION_REQUEST');
      this.handlePermissionRequest(msg)
    } else if (msgType === 'auth_result') {
      hilog.info(DOMAIN, TAG, '>>> AUTH_RESULT: %{public}s', msg['success'] as boolean ? 'SUCCESS' : 'FAILED');
    } else if (msgType === 'exec_ack') {
      hilog.info(DOMAIN, TAG, '>>> EXEC_ACK');
    } else if (msgType === 'file_added') {
      this.handleFileAdded(msg)
    } else if (msgType === 'file_updated') {
      this.handleFileUpdated(msg)
    } else if (msgType === 'file_removed') {
      this.handleFileRemoved(msg)
    } else if (msgType === 'file_list') {
      this.handleFileList(msg)
    } else if (msgType === 'error') {
      hilog.error(DOMAIN, TAG, '>>> ERROR: %{public}s', msg['message'] as string);
      this.handleError(msg)
    } else {
      hilog.warn(DOMAIN, TAG, '>>> UNKNOWN message type: %{public}s', msgType);
    }
  }

  handleAiResponse(msg: ESObject): void {
    const content: string = msg['content'] as string || ''
    const messageId: string = msg['messageID'] as string || ''
    
    hilog.info(DOMAIN, TAG, '>>> handleAiResponse: contentLen=%{public}d, msgId=%{public}s', content.length, messageId);
    
    // 移除运行状态消息
    this.messages = this.messages.filter((m: TaskMessage) => m.status !== 'running')
    
    if (messageId.length > 0 && messageId === this.lastAiMessageId) {
      hilog.info(DOMAIN, TAG, '>>> Updating existing message');
      for (let i = 0; i < this.messages.length; i++) {
        if (this.messages[i].id === 'ai-' + messageId) {
          this.messages[i].content = content
          this.messages[i].status = 'completed'
          return
        }
      }
    }
    
    const newMsg: TaskMessage = {
      id: 'ai-' + messageId,
      type: 'ai',
      content: content,
      timestamp: Date.now(),
      status: 'completed'
    }
    hilog.info(DOMAIN, TAG, '>>> Adding new AI message to list');
    this.messages.push(newMsg)
    this.lastAiMessageId = messageId
  }
 
  handleTaskStatus(msg: ESObject): void {
    const statusStr: string = msg['status'] as string
    const messageText: string = msg['message'] as string || ''
    
    if (statusStr === 'running') {
      // 移除旧的运行状态消息，添加新的
      this.messages = this.messages.filter((m: TaskMessage) => m.status !== 'running')
      const newMsg: TaskMessage = {
        id: 'status-running',
        type: 'system',
        content: messageText.length > 0 ? messageText : '任务执行中...',
        timestamp: Date.now(),
        status: 'running'
      }
      this.messages.push(newMsg)
    } else if (statusStr === 'idle' || statusStr === 'ready' || statusStr === 'completed') {
      // 移除运行状态消息
      this.messages = this.messages.filter((m: TaskMessage) => m.status !== 'running')
    }
  }
 
  handlePermissionRequest(msg: ESObject): void {
    this.currentPermissionId = msg['id'] as string
    this.currentPermissionCommand = msg['command'] as string
    this.currentPermissionExplanation = msg['explanation'] as string || '需要授权'
    this.showPermissionDialog = true
    
    const permMsg: TaskMessage = {
      id: 'perm-' + this.currentPermissionId,
      type: 'permission',
      content: '需要授权: ' + this.currentPermissionCommand,
      timestamp: Date.now(),
      status: 'pending'
    }
    this.messages.push(permMsg)
  }
 
  handleFileAdded(msg: ESObject): void {
    const file: FileInfo = {
      name: msg['filename'] as string,
      path: msg['filename'] as string,
      size: msg['size'] as number,
      modified: msg['modified'] as string,
      url: msg['url'] as string
    }
    this.files.push(file)
  }
 
  handleFileUpdated(msg: ESObject): void {
    const filename: string = msg['filename'] as string
    for (let i = 0; i < this.files.length; i++) {
      if (this.files[i].path === filename) {
        this.files[i] = {
          name: filename,
          path: filename,
          size: msg['size'] as number,
          modified: msg['modified'] as string,
          url: msg['url'] as string
        }
        break
      }
    }
  }
 
  handleFileRemoved(msg: ESObject): void {
    const filename: string = msg['filename'] as string
    const newFiles: FileInfo[] = []
    for (let i = 0; i < this.files.length; i++) {
      if (this.files[i].path !== filename) {
        newFiles.push(this.files[i])
      }
    }
    this.files = newFiles
  }
 
  handleFileList(msg: ESObject): void {
    const filesArray: ESObject[] = msg['files'] as ESObject[]
    const newFiles: FileInfo[] = []
    for (let i = 0; i < filesArray.length; i++) {
      const f: ESObject = filesArray[i]
      newFiles.push({
        name: f['name'] as string,
        path: f['path'] as string,
        size: f['size'] as number,
        modified: f['modified'] as string,
        url: f['url'] as string
      })
    }
    this.files = newFiles
  }
 
  handleError(msg: ESObject): void {
    const errMsg: TaskMessage = {
      id: 'err-' + Date.now().toString(),
      type: 'system',
      content: '错误: ' + (msg['message'] as string || '未知错误'),
      timestamp: Date.now(),
      status: 'error'
    }
    this.messages.push(errMsg)
  }
 
  sendCommand(): void {
    if (this.inputText.trim().length === 0) {
      return
    }
 
    const userMsg: TaskMessage = {
      id: 'user-' + Date.now().toString(),
      type: 'user',
      content: this.inputText,
      timestamp: Date.now(),
      status: 'pending'
    }
    this.messages.push(userMsg)
    wsService.execCommand(this.inputText)
    this.inputText = ''
  }
 
  replyPermission(answer: string): void {
    if (this.currentPermissionId.length > 0) {
      wsService.replyPermission(this.currentPermissionId, answer)
      this.showPermissionDialog = false
      
      const permMsgId: string = 'perm-' + this.currentPermissionId
      for (let i = 0; i < this.messages.length; i++) {
        if (this.messages[i].id === permMsgId) {
          this.messages[i].status = answer === 'y' ? 'completed' : 'error'
          break
        }
      }
    }
  }
 
  toggleRecording(): void {
    this.isRecording = !this.isRecording
    if (this.isRecording) {
      hilog.info(DOMAIN, TAG, 'Start recording')
    } else {
      hilog.info(DOMAIN, TAG, 'Stop recording')
    }
  }
}
 
@Component
struct MessageItem {
  @Prop message: TaskMessage
 
  build() {
    Row() {
      Column() {
        if (this.message.type === 'user') {
          Text('👤')
            .fontSize(20)
        } else if (this.message.type === 'ai') {
          Text('🤖')
            .fontSize(20)
        } else if (this.message.type === 'permission') {
          Text('⚠️')
            .fontSize(20)
        } else {
          Text('🔧')
            .fontSize(20)
        }
      }
      .width(40)
      .height(40)
      .backgroundColor('#EEEEEE')
      .borderRadius(20)
      .justifyContent(FlexAlign.Center)
 
      Column() {
        Text(this.message.content)
          .fontSize(14)
          .maxLines(10)
 
        Row() {
          if (this.message.status === 'running') {
            Progress({ value: 0, total: 100, type: ProgressType.Linear })
              .width(50)
              .height(4)
              .color('#4CAF50')
          }
 
          Text(this.formatTime(this.message.timestamp))
            .fontSize(12)
            .fontColor('#888888')
        }
        .margin({ top: 5 })
      }
      .margin({ left: 10 })
      .layoutWeight(1)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.message.type === 'user' ? '#E3F2FD' : '#FFFFFF')
    .borderRadius(8)
  }
 
  formatTime(timestamp: number): string {
    const date: Date = new Date(timestamp)
    const hours: number = date.getHours()
    const minutes: number = date.getMinutes()
    const hoursStr: string = hours < 10 ? '0' + hours.toString() : hours.toString()
    const minutesStr: string = minutes < 10 ? '0' + minutes.toString() : minutes.toString()
    return hoursStr + ':' + minutesStr
  }
}
 
@Component
struct FileItem {
  @Prop file: FileInfo
  @Prop serverIp: string = ''
  @Prop httpPort: number = 8081
 
  build() {
    Row() {
      Column() {
        if (this.file.name.endsWith('.png') || this.file.name.endsWith('.jpg')) {
          Text('🖼️')
            .fontSize(20)
        } else if (this.file.name.endsWith('.md') || this.file.name.endsWith('.txt')) {
          Text('📄')
            .fontSize(20)
        } else if (this.file.name.endsWith('.json')) {
          Text('📋')
            .fontSize(20)
        } else {
          Text('📁')
            .fontSize(20)
        }
      }
      .width(40)
      .height(40)
      .backgroundColor('#EEEEEE')
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
 
      Column() {
        Text(this.file.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
 
        Text(this.formatSize(this.file.size))
          .fontSize(12)
          .fontColor('#888888')
      }
      .margin({ left: 10 })
      .layoutWeight(1)
 
      Button('查看')
        .width(60)
        .height(35)
        .backgroundColor('#4CAF50')
        .onClick(() => {
          this.openFile()
        })
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }
 
  openFile(): void {
    hilog.info(DOMAIN, TAG, `Open file: http://${this.serverIp}:${this.httpPort}${this.file.url}`)
  }
 
  formatSize(size: number): string {
    if (size < 1024) {
      return size.toString() + ' B'
    } else if (size < 1024 * 1024) {
      const kb: number = size / 1024
      return kb.toFixed(1) + ' KB'
    } else {
      const mb: number = size / 1024 / 1024
      return mb.toFixed(1) + ' MB'
    }
  }
}