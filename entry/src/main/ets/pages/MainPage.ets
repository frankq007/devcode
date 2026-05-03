/**
 * 主控页面
 */

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { wsService } from '../common/WebSocketService';
import { PermissionDialog } from '../components/PermissionDialog';
import type { FileInfo, TaskMessage, ConnectionConfig } from '../common/Types';

const DOMAIN = 0xFF00;
const TAG = 'MainPage';

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
  @State showMenu: boolean = false;
  @State showFilesPanel: boolean = false;

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, '=== MainPage aboutToAppear ===');

    this.connectionStatus = '正在连接...';
    wsService.connect(DEBUG_CONFIG).then((success: boolean) => {
      if (success) {
        this.connectionStatus = '已连接';
      } else {
        this.connectionStatus = '连接失败';
      }
    }).catch((e: Error) => {
      this.connectionStatus = '连接错误';
    });

    wsService.onMessage((msg: ESObject) => {
      this.handleMessage(msg);
    });

    wsService.onStatusChange((connected: boolean) => {
      this.connectionStatus = connected ? '已连接' : '已断开';
    });
  }

  build() {
    Stack() {
      Column() {
        // 顶部标题栏
        Row() {
          Blank()
          
          Text('DevCode')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
          
          Blank()
          
          // 圆圈加号按钮
          Stack() {
            Circle()
              .width(32)
              .height(32)
              .fill('#FFFFFF')
              .stroke('#4CAF50')
              .strokeWidth(2)
            
            Text('+')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#4CAF50')
          }
          .width(32)
          .height(32)
          .onClick(() => {
            this.showMenu = !this.showMenu
          })
        }
        .width('100%')
        .height(50)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#FFFFFF')
        .shadow({ radius: 2, color: '#EEEEEE', offsetY: 2 })

        // 下拉菜单
        if (this.showMenu) {
          Column() {
            Text('扫一扫')
              .fontSize(16)
              .padding(12)
              .width('100%')
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.showMenu = false
                router.pushUrl({ url: 'pages/ScanPage' })
              })

            Divider().color('#EEEEEE')

            Text('文件')
              .fontSize(16)
              .padding(12)
              .width('100%')
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.showMenu = false
                this.showFilesPanel = true
              })

            Divider().color('#EEEEEE')

            Text('设置')
              .fontSize(16)
              .padding(12)
              .width('100%')
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.showMenu = false
              })
          }
          .width(120)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .shadow({ radius: 4, color: '#CCCCCC', offsetY: 2 })
          .position({ x: '100%', y: 50 })
          .translate({ x: -136 })
          .zIndex(10)
        }

        // 连接状态指示
        Row() {
          Circle()
            .width(8)
            .height(8)
            .fill(this.connectionStatus === '已连接' ? '#4CAF50' : '#FF5722')
          
          Text(this.connectionStatus)
            .fontSize(12)
            .fontColor('#888888')
            .margin({ left: 4 })
        }
        .width('100%')
        .padding({ left: 16, top: 8, bottom: 8 })
        .backgroundColor('#F5F5F5')

        // 消息列表 - 填满剩余空间
        List() {
          ForEach(this.messages, (msg: TaskMessage) => {
            ListItem() {
              MessageItem({ message: msg })
            }
          }, (msg: TaskMessage) => msg.id)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#F5F5F5')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })

        // 输入区域
        Row() {
          TextInput({ placeholder: '输入指令...', text: this.inputText })
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#FFFFFF')
            .borderRadius(22)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.inputText = value
            })

          Button('发送')
            .width(70)
            .height(44)
            .backgroundColor('#4CAF50')
            .borderRadius(22)
            .margin({ left: 8 })
            .onClick(() => {
              this.sendCommand()
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor('#FFFFFF')
        .shadow({ radius: 2, color: '#EEEEEE', offsetY: -2 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F5F5')

      // 权限弹窗
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

      // 文件面板
      if (this.showFilesPanel) {
        Column() {
          Row() {
            Text('文件')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
            
            Blank()
            
            Text('关闭')
              .fontSize(16)
              .fontColor('#4CAF50')
              .onClick(() => {
                this.showFilesPanel = false
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')

          if (this.files.length > 0) {
            List() {
              ForEach(this.files, (file: FileInfo) => {
                ListItem() {
                  FileItem({ file: file, serverIp: this.serverIp, httpPort: this.httpPort })
                }
              }, (file: FileInfo) => file.path)
            }
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('#F5F5F5')
          } else {
            Column() {
              Text('暂无文件')
                .fontSize(14)
                .fontColor('#888888')
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#F5F5F5')
          }
        }
        .width('100%')
        .height('70%')
        .backgroundColor('#FFFFFF')
        .position({ x: 0, y: '30%' })
        .borderRadius({ topLeft: 16, topRight: 16 })
        .shadow({ radius: 8, color: '#CCCCCC', offsetY: -4 })
        .zIndex(20)
      }
    }
    .width('100%')
    .height('100%')
  }

  handleMessage(msg: ESObject): void {
    const msgType: string = msg['type'] as string

    if (msgType === 'ai_response') {
      this.handleAiResponse(msg)
    } else if (msgType === 'task_status') {
      this.handleTaskStatus(msg)
    } else if (msgType === 'permission_request') {
      this.handlePermissionRequest(msg)
    } else if (msgType === 'file_added') {
      this.handleFileAdded(msg)
    } else if (msgType === 'file_updated') {
      this.handleFileUpdated(msg)
    } else if (msgType === 'file_removed') {
      this.handleFileRemoved(msg)
    } else if (msgType === 'file_list') {
      this.handleFileList(msg)
    } else if (msgType === 'error') {
      this.handleError(msg)
    }
  }

  handleAiResponse(msg: ESObject): void {
    const content: string = msg['content'] as string || ''
    const messageId: string = msg['messageID'] as string || ''
    
    this.messages = this.messages.filter((m: TaskMessage) => m.status !== 'running')
    
    if (messageId.length > 0 && messageId === this.lastAiMessageId) {
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
    this.messages.push(newMsg)
    this.lastAiMessageId = messageId
  }

  handleTaskStatus(msg: ESObject): void {
    const statusStr: string = msg['status'] as string
    const messageText: string = msg['message'] as string || ''
    
    if (statusStr === 'running') {
      this.messages = this.messages.filter((m: TaskMessage) => m.status !== 'running')
      const newMsg: TaskMessage = {
        id: 'status-running',
        type: 'system',
        content: messageText.length > 0 ? messageText : '正在处理...',
        timestamp: Date.now(),
        status: 'running'
      }
      this.messages.push(newMsg)
    } else if (statusStr === 'idle' || statusStr === 'ready' || statusStr === 'completed') {
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
    this.files = this.files.filter((f: FileInfo) => f.path !== filename)
  }

  handleFileList(msg: ESObject): void {
    const filesArray: ESObject[] = msg['files'] as ESObject[]
    const newFiles: FileInfo[] = []
    for (let i = 0; i < filesArray.length; i++) {
      const f: ESObject = filesArray[i]
      const file: FileInfo = {
        name: f['name'] as string,
        path: f['path'] as string,
        size: f['size'] as number,
        modified: f['modified'] as string,
        url: f['url'] as string
      }
      newFiles.push(file)
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
}

@Component
struct MessageItem {
  @Prop message: TaskMessage

  build() {
    Column() {
      Row() {
        if (this.message.type === 'user') {
          Text('我')
            .fontSize(14)
            .fontColor('#FFFFFF')
        } else {
          Text('AI')
            .fontSize(14)
            .fontColor('#FFFFFF')
        }
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.message.type === 'user' ? '#4CAF50' : '#2196F3')
      .justifyContent(FlexAlign.Center)

      Column() {
        Text(this.message.content)
          .fontSize(15)
          .fontColor('#333333')
          .maxLines(20)
          .textOverflow({ overflow: TextOverflow.Clip })

        if (this.message.status === 'running') {
          Row() {
            LoadingProgress()
              .width(16)
              .height(16)
              .color('#4CAF50')
            
            Text('正在处理...')
              .fontSize(12)
              .fontColor('#888888')
              .margin({ left: 4 })
          }
          .margin({ top: 4 })
        } else {
          Text(this.formatTime(this.message.timestamp))
            .fontSize(12)
            .fontColor('#AAAAAA')
            .margin({ top: 4 })
        }
      }
      .margin({ left: 8 })
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ top: 4, bottom: 4 })
  }

  formatTime(timestamp: number): string {
    const date: Date = new Date(timestamp)
    const hours: number = date.getHours()
    const minutes: number = date.getMinutes()
    return (hours < 10 ? '0' : '') + hours.toString() + ':' + (minutes < 10 ? '0' : '') + minutes.toString()
  }
}

@Component
struct FileItem {
  @Prop file: FileInfo
  @Prop serverIp: string = ''
  @Prop httpPort: number = 8081

  build() {
    Row() {
      Text(this.getFileIcon())
        .fontSize(24)

      Column() {
        Text(this.file.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.formatSize(this.file.size))
          .fontSize(12)
          .fontColor('#888888')
      }
      .margin({ left: 12 })
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('查看')
        .width(60)
        .height(32)
        .fontSize(14)
        .backgroundColor('#4CAF50')
        .onClick(() => {
          this.openFile()
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .margin({ top: 4, bottom: 4 })
  }

  getFileIcon(): string {
    const name: string = this.file.name.toLowerCase()
    if (name.endsWith('.png') || name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.gif')) {
      return '🖼'
    } else if (name.endsWith('.md') || name.endsWith('.txt')) {
      return '📄'
    } else if (name.endsWith('.json')) {
      return '📋'
    } else if (name.endsWith('.pdf')) {
      return '📑'
    } else if (name.endsWith('.zip')) {
      return '📦'
    } else {
      return '📁'
    }
  }

  openFile(): void {
    hilog.info(DOMAIN, TAG, `Open file: http://${this.serverIp}:${this.httpPort}${this.file.url}`)
  }

  formatSize(size: number): string {
    if (size < 1024) {
      return size.toString() + ' B'
    } else if (size < 1024 * 1024) {
      return (size / 1024).toFixed(1) + ' KB'
    } else {
      return (size / 1024 / 1024).toFixed(1) + ' MB'
    }
  }
}