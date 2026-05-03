/**
 * 主控页面 - 微信风格气泡对话
 */

import { router, KeyboardAvoidMode } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { wsService } from '../common/WebSocketService';
import { PermissionDialog } from '../components/PermissionDialog';
import { MarkdownRenderer } from '../components/MarkdownRenderer';
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
  @State lastAiMessageId: string = '';
  @State showMenu: boolean = false;
  @State showFilesPanel: boolean = false;
  private listScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    
    this.connectionStatus = '正在连接...';
    wsService.connect(DEBUG_CONFIG).then((success: boolean) => {
      this.connectionStatus = success ? '已连接' : '连接失败';
    }).catch(() => {
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
        // 顶部标题栏 - 固定高度
        Row() {
          Blank()
          
          Text('DevCode')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
          
          Blank()
          
          Stack() {
            Circle()
              .width(28)
              .height(28)
              .fill('#FFFFFF')
              .stroke('#4CAF50')
              .strokeWidth(1.5)
            
            Text('+')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#4CAF50')
          }
          .width(28)
          .height(28)
          .onClick(() => {
            this.showMenu = !this.showMenu
          })
        }
        .width('100%')
        .height(44)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#FFFFFF')

        // 消息列表 - layoutWeight(1) 自动压缩
        List({ scroller: this.listScroller }) {
          ForEach(this.messages, (msg: TaskMessage) => {
            ListItem() {
              ChatBubble({ message: msg })
            }
          }, (msg: TaskMessage) => msg.id)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#EDEDED')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .scrollBar(BarState.Off)

        // 输入区域 - 固定在底部
        Row() {
          TextInput({ placeholder: '输入指令...', text: this.inputText })
            .layoutWeight(1)
            .height(40)
            .backgroundColor('#FFFFFF')
            .borderRadius(20)
            .padding({ left: 14, right: 14 })
            .onChange((value: string) => {
              this.inputText = value
            })

          Button('发送')
            .width(60)
            .height(40)
            .fontSize(14)
            .backgroundColor('#07C160')
            .borderRadius(20)
            .margin({ left: 8 })
            .onClick(() => {
              this.sendCommand()
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor('#F7F7F7')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#EDEDED')

      // 下拉菜单 - 绝对定位
      if (this.showMenu) {
        Column() {
          MenuButtonItem({ text: '扫一扫', onMenuClick: () => {
            this.showMenu = false
            router.pushUrl({ url: 'pages/ScanPage' })
          }})
          
          Divider().color('#EEEEEE').height(0.5)
          
          MenuButtonItem({ text: '文件', onMenuClick: () => {
            this.showMenu = false
            this.showFilesPanel = true
          }})
          
          Divider().color('#EEEEEE').height(0.5)
          
          MenuButtonItem({ text: '设置', onMenuClick: () => {
            this.showMenu = false
          }})
        }
        .width(100)
        .backgroundColor('#FFFFFF')
        .borderRadius(6)
        .shadow({ radius: 3, color: '#00000033', offsetY: 1 })
        .position({ x: '100%', y: 44 })
        .translate({ x: -112 })
        .zIndex(100)
      }

      // 权限弹窗
      if (this.showPermissionDialog) {
        PermissionDialog({
          requestId: this.currentPermissionId,
          command: this.currentPermissionCommand,
          explanation: this.currentPermissionExplanation,
          onAllow: () => { this.replyPermission('y') },
          onDeny: () => { this.replyPermission('n') },
          onModify: (newCmd: string) => { this.replyPermission(newCmd) },
          onClose: () => { this.showPermissionDialog = false }
        })
      }

      // 文件面板
      if (this.showFilesPanel) {
        Column() {
          Row() {
            Text('文件')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
            
            Blank()
            
            Text('关闭')
              .fontSize(16)
              .fontColor('#07C160')
              .onClick(() => { this.showFilesPanel = false })
          }
          .width('100%')
          .height(44)
          .padding({ left: 16, right: 16 })
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
            .backgroundColor('#F7F7F7')
          } else {
            Column() {
              Text('暂无文件')
                .fontSize(14)
                .fontColor('#888888')
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#F7F7F7')
          }
        }
        .width('100%')
        .height('75%')
        .backgroundColor('#FFFFFF')
        .position({ x: 0, y: '25%' })
        .borderRadius({ topLeft: 12, topRight: 12 })
        .shadow({ radius: 6, color: '#00000022', offsetY: -3 })
        .zIndex(50)
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
    
    const newMsg: TaskMessage = {
      id: 'ai-' + messageId,
      type: 'ai',
      content: content,
      timestamp: Date.now(),
      status: 'completed'
    }
    this.messages.push(newMsg)
    this.lastAiMessageId = messageId
    
    setTimeout(() => {
      this.listScroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  handleTaskStatus(msg: ESObject): void {
    const statusStr: string = msg['status'] as string
    
    if (statusStr === 'running') {
      this.messages = this.messages.filter((m: TaskMessage) => m.status !== 'running')
      const newMsg: TaskMessage = {
        id: 'status-running',
        type: 'ai',
        content: '正在处理...',
        timestamp: Date.now(),
        status: 'running'
      }
      this.messages.push(newMsg)
    } else if (statusStr === 'idle' || statusStr === 'ready') {
      this.messages = this.messages.filter((m: TaskMessage) => m.status !== 'running')
    }
  }

  handlePermissionRequest(msg: ESObject): void {
    this.currentPermissionId = msg['id'] as string
    this.currentPermissionCommand = msg['command'] as string
    this.currentPermissionExplanation = msg['explanation'] as string || '需要授权'
    this.showPermissionDialog = true
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
      type: 'ai',
      content: '错误: ' + (msg['message'] as string || '未知错误'),
      timestamp: Date.now(),
      status: 'error'
    }
    this.messages.push(errMsg)
  }

  sendCommand(): void {
    if (this.inputText.trim().length === 0) return

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
    
    setTimeout(() => {
      this.listScroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  replyPermission(answer: string): void {
    if (this.currentPermissionId.length > 0) {
      wsService.replyPermission(this.currentPermissionId, answer)
      this.showPermissionDialog = false
    }
  }
}

// 菜单项组件
@Component
struct MenuButtonItem {
  @Prop text: string = ''
  onMenuClick: () => void = () => {}

  build() {
    Text(this.text)
      .fontSize(15)
      .fontColor('#333333')
      .padding({ top: 10, bottom: 10, left: 12, right: 12 })
      .width('100%')
      .textAlign(TextAlign.Center)
      .onClick(() => { this.onMenuClick() })
  }
}

// 聊天气泡组件 - 微信风格
@Component
struct ChatBubble {
  @Prop message: TaskMessage

  build() {
    Column() {
      if (this.message.type === 'user') {
        // 用户消息 - 右对齐
        Row() {
          Blank()
          
          Column() {
            Text(this.message.content)
              .fontSize(16)
              .fontColor('#FFFFFF')
              .maxLines(100)
              .textOverflow({ overflow: TextOverflow.Clip })
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            
            if (this.message.status === 'running') {
              Row() {
                LoadingProgress().width(14).height(14).color('#FFFFFF')
                Text('发送中').fontSize(12).fontColor('#FFFFFF').margin({ left: 4 })
              }.margin({ top: 4, bottom: 4 })
            }
          }
          .backgroundColor('#07C160')
          .borderRadius(6)
          .constraintSize({ minWidth: 40, maxWidth: '70%' })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
      } else {
        // AI消息 - 左对齐，使用 Markdown 渲染
        Row() {
          Column() {
            if (this.message.status === 'running') {
              Row() {
                LoadingProgress().width(14).height(14).color('#07C160')
                Text(this.message.content).fontSize(14).fontColor('#888888').margin({ left: 4 })
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .width('100%')
            } else {
              MarkdownRenderer({ content: this.message.content })
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            }
          }
          .backgroundColor('#FFFFFF')
          .borderRadius(6)
          .width('85%')
          .alignItems(HorizontalAlign.Start)
          
          Blank()
        }
        .width('100%')
      }
    }
    .width('100%')
    .margin({ top: 4, bottom: 4 })
  }
}

// 文件项组件
@Component
struct FileItem {
  @Prop file: FileInfo
  @Prop serverIp: string = ''
  @Prop httpPort: number = 8081

  build() {
    Row() {
      Text(this.getFileIcon()).fontSize(22)

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
      .margin({ left: 10 })
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('查看')
        .width(50)
        .height(28)
        .fontSize(13)
        .backgroundColor('#07C160')
        .onClick(() => { this.openFile() })
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(6)
    .margin({ top: 3, bottom: 3 })
  }

  getFileIcon(): string {
    const name: string = this.file.name.toLowerCase()
    if (name.endsWith('.png') || name.endsWith('.jpg') || name.endsWith('.jpeg')) return '🖼'
    if (name.endsWith('.md') || name.endsWith('.txt')) return '📄'
    if (name.endsWith('.json')) return '📋'
    if (name.endsWith('.pdf')) return '📑'
    if (name.endsWith('.zip')) return '📦'
    return '📁'
  }

  openFile(): void {
    hilog.info(DOMAIN, TAG, `Open file: http://${this.serverIp}:${this.httpPort}${this.file.url}`)
  }

  formatSize(size: number): string {
    if (size < 1024) return size.toString() + ' B'
    if (size < 1024 * 1024) return (size / 1024).toFixed(1) + ' KB'
    return (size / 1024 / 1024).toFixed(1) + ' MB'
  }
}