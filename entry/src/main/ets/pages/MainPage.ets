/**
 * 主控页面
 * 
 * 功能：
 * - 显示消息列表
 * - 语音/文字输入指令
 * - 文件列表
 * - 权限弹窗处理
 */

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { wsService } from '../common/WebSocketService';
import type {
  WSMessage,
  TaskStatusMessage,
  PermissionRequestMessage,
  FileAddedMessage,
  FileListMessage,
  FileInfo,
  TaskMessage
} from '../common/Types';
import { PermissionDialog } from '../components/PermissionDialog';

const DOMAIN = 0xFF00;
const TAG = 'MainPage';

@Entry
@Component
struct MainPage {
  // 状态
  @State messages: TaskMessage[] = [];
  @State files: FileInfo[] = [];
  @State inputText: string = '';
  @State showPermissionDialog: boolean = false;
  @State currentPermission: PermissionRequestMessage | null = null;
  @State connectionStatus: string = '已连接';
  @State serverIp: string = '';
  @State httpPort: number = 8081;
  @State isRecording: boolean = false;

  // 从路由参数获取
  private routeParams: ESObject = router.getParams() as ESObject;

  aboutToAppear(): void {
    // 获取路由参数
    if (this.routeParams) {
      this.serverIp = this.routeParams.serverIp || '100.64.0.2';
      this.httpPort = this.routeParams.httpPort || 8081;
    }

    // 注册消息回调
    wsService.onMessage((msg: WSMessage) => {
      this.handleMessage(msg);
    });

    // 注册状态回调
    wsService.onStatusChange((connected: boolean) => {
      this.connectionStatus = connected ? '已连接' : '已断开';
      if (!connected) {
        // 连接断开，返回扫码页面
        router.replaceUrl({ url: 'pages/ScanPage' });
      }
    });

    // 请求文件列表
    wsService.requestFileList();

    hilog.info(DOMAIN, TAG, 'MainPage initialized');
  }

  build() {
    Column() {
      // 顶部状态栏
      Row() {
        Text($r('app.string.main_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold);

        Blank();

        // 连接状态
        Row() {
          Circle()
            .width(10)
            .height(10)
            .fill(this.connectionStatus === '已连接' ? '#4CAF50' : '#FF5722');

          Text(this.connectionStatus)
            .fontSize(14)
            .fontColor('#888888')
            .margin({ left: 5 });
        }
      }
      .width('100%')
      .height(50)
      .padding({ left: 20, right: 20 })
      .backgroundColor('#FFFFFF');

      // 消息列表
      List() {
        ForEach(this.messages, (msg: TaskMessage, index: number) => {
          ListItem() {
            MessageItem({ message: msg });
          }
        }, (msg: TaskMessage) => msg.id);
      }
      .width('100%')
      .height('50%')
      .backgroundColor('#F5F5F5')
      .divider({ strokeWidth: 1, color: '#EEEEEE', startMargin: 10, endMargin: 10 });

      // 文件列表区域
      Column() {
        Text($r('app.string.files_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 10 });

        if (this.files.length > 0) {
          List() {
            ForEach(this.files, (file: FileInfo, index: number) => {
              ListItem() {
                FileItem({ file: file, serverIp: this.serverIp, httpPort: this.httpPort });
              }
            }, (file: FileInfo) => file.path);
          }
          .width('100%')
          .height(120)
          .backgroundColor('#FFFFFF')
          .borderRadius(8);
        } else {
          Text('暂无文件')
            .fontSize(14)
            .fontColor('#888888')
            .height(120);
        }
      }
      .width('100%')
      .padding(20)
      .backgroundColor('#FFFFFF');

      // 输入区域
      Row() {
        // 语音按钮
        Column() {
          Image($r('app.media.startIcon'))
            .width(30)
            .height(30)
            .fillColor(this.isRecording ? '#FF5722' : '#4CAF50');

          Text($r('app.string.voice_hint'))
            .fontSize(12)
            .fontColor(this.isRecording ? '#FF5722' : '#888888');
        }
        .width(60)
        .height(60)
        .borderRadius(8)
        .backgroundColor('#EEEEEE')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          // TODO: 实现语音控制
          this.toggleRecording();
        });

        // 文字输入
        TextInput({ placeholder: '输入指令...', text: this.inputText })
          .width('60%')
          .height(50)
          .margin({ left: 10 })
          .onChange((value) => {
            this.inputText = value;
          });

        // 发送按钮
        Button($r('app.string.send_command'))
          .width('20%')
          .height(50)
          .backgroundColor('#4CAF50')
          .margin({ left: 10 })
          .onClick(() => {
            this.sendCommand();
          });
      }
      .width('100%')
      .height(80)
      .padding({ left: 10, right: 10 })
      .backgroundColor('#FFFFFF');
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5');

    // 权限弹窗（覆盖层）
    if (this.showPermissionDialog && this.currentPermission) {
      PermissionDialog({
        request: this.currentPermission,
        onAllow: () => {
          this.replyPermission('y');
        },
        onDeny: () => {
          this.replyPermission('n');
        },
        onModify: (newCmd: string) => {
          this.replyPermission(newCmd);
        },
        onClose: () => {
          this.showPermissionDialog = false;
        }
      });
    }
  }

  /**
   * 处理接收的消息
   */
  handleMessage(msg: WSMessage): void {
    hilog.debug(DOMAIN, TAG, `Handle message: ${msg.type}`);

    switch (msg.type) {
      case 'task_status':
        this.handleTaskStatus(msg as TaskStatusMessage);
        break;
      case 'permission_request':
        this.handlePermissionRequest(msg as PermissionRequestMessage);
        break;
      case 'file_added':
        this.handleFileAdded(msg as FileAddedMessage);
        break;
      case 'file_updated':
        this.handleFileUpdated(msg as FileAddedMessage);
        break;
      case 'file_removed':
        this.handleFileRemoved(msg as ESObject);
        break;
      case 'file_list':
        this.handleFileList(msg as FileListMessage);
        break;
      case 'error':
        this.handleError(msg as ESObject);
        break;
    }
  }

  /**
   * 处理任务状态
   */
  handleTaskStatus(msg: TaskStatusMessage): void {
    const newMsg: TaskMessage = {
      id: 'msg-' + Date.now(),
      type: 'ai',
      content: msg.content || '',
      timestamp: Date.now(),
      status: msg.status
    };

    this.messages.push(newMsg);
  }

  /**
   * 处理权限请求
   */
  handlePermissionRequest(msg: PermissionRequestMessage): void {
    this.currentPermission = msg;
    this.showPermissionDialog = true;

    // 添加到消息列表
    const permMsg: TaskMessage = {
      id: 'perm-' + msg.id,
      type: 'permission',
      content: `需要授权: ${msg.command}`,
      timestamp: Date.now(),
      status: 'pending'
    };
    this.messages.push(permMsg);
  }

  /**
   * 处理文件添加
   */
  handleFileAdded(msg: FileAddedMessage): void {
    const file: FileInfo = {
      name: msg.filename,
      path: msg.filename,
      size: msg.size,
      modified: msg.modified,
      url: msg.url
    };
    this.files.push(file);
  }

  /**
   * 处理文件更新
   */
  handleFileUpdated(msg: FileAddedMessage): void {
    const index = this.files.findIndex(f => f.path === msg.filename);
    if (index >= 0) {
      this.files[index] = {
        name: msg.filename,
        path: msg.filename,
        size: msg.size,
        modified: msg.modified,
        url: msg.url
      };
    }
  }

  /**
   * 处理文件删除
   */
  handleFileRemoved(msg: ESObject): void {
    this.files = this.files.filter(f => f.path !== msg.filename);
  }

  /**
   * 处理文件列表
   */
  handleFileList(msg: FileListMessage): void {
    this.files = msg.files;
  }

  /**
   * 处理错误
   */
  handleError(msg: ESObject): void {
    const errMsg: TaskMessage = {
      id: 'err-' + Date.now(),
      type: 'system',
      content: `错误: ${msg.message}`,
      timestamp: Date.now(),
      status: 'error'
    };
    this.messages.push(errMsg);
  }

  /**
   * 发送指令
   */
  sendCommand(): void {
    if (!this.inputText.trim()) {
      return;
    }

    // 添加用户消息
    const userMsg: TaskMessage = {
      id: 'user-' + Date.now(),
      type: 'user',
      content: this.inputText,
      timestamp: Date.now(),
      status: 'pending'
    };
    this.messages.push(userMsg);

    // 发送指令
    wsService.execCommand(this.inputText);

    // 清空输入
    this.inputText = '';
  }

  /**
   * 回复权限请求
   */
  replyPermission(answer: string): void {
    if (this.currentPermission) {
      wsService.replyPermission(this.currentPermission.id, answer);
      this.showPermissionDialog = false;

      // 更新权限消息状态
      const permMsgId = 'perm-' + this.currentPermission.id;
      const index = this.messages.findIndex(m => m.id === permMsgId);
      if (index >= 0) {
        this.messages[index].status = answer === 'y' ? 'completed' : 'error';
      }
    }
  }

  /**
   * 切换录音状态
   * TODO: 实现语音控制功能
   */
  toggleRecording(): void {
    this.isRecording = !this.isRecording;

    if (this.isRecording) {
      // 开始录音
      hilog.info(DOMAIN, TAG, 'Start recording');
      // 实际实现需要使用 @ohos.speech
    } else {
      // 结束录音
      hilog.info(DOMAIN, TAG, 'Stop recording');
    }
  }
}

/**
 * 消息项组件
 */
@Component
struct MessageItem {
  @Prop message: TaskMessage;

  build() {
    Row() {
      // 类型图标
      Column() {
        if (this.message.type === 'user') {
          Text('👤')
            .fontSize(20);
        } else if (this.message.type === 'ai') {
          Text('🤖')
            .fontSize(20);
        } else if (this.message.type === 'permission') {
          Text('⚠️')
            .fontSize(20);
        } else {
          Text('🔧')
            .fontSize(20);
        }
      }
      .width(40)
      .height(40)
      .backgroundColor('#EEEEEE')
      .borderRadius(20)
      .justifyContent(FlexAlign.Center);

      // 内容
      Column() {
        Text(this.message.content)
          .fontSize(14)
          .maxLines(10);

        // 状态
        Row() {
          if (this.message.status === 'running') {
            Progress({ value: 0, total: 100, type: ProgressType.Linear })
              .width(50)
              .height(4)
              .color('#4CAF50');
          }

          Text(this.formatTime(this.message.timestamp))
            .fontSize(12)
            .fontColor('#888888');
        }
        .margin({ top: 5 });
      }
      .margin({ left: 10 })
      .layoutWeight(1);
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.message.type === 'user' ? '#E3F2FD' : '#FFFFFF')
    .borderRadius(8);
  }

  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getHours()}:${date.getMinutes()}`;
  }
}

/**
 * 文件项组件
 */
@Component
struct FileItem {
  @Prop file: FileInfo;
  @Prop serverIp: string = '';
  @Prop httpPort: number = 8081;

  build() {
    Row() {
      // 文件图标
      Column() {
        if (this.file.name.endsWith('.png') || this.file.name.endsWith('.jpg')) {
          Text('🖼️')
            .fontSize(20);
        } else if (this.file.name.endsWith('.md') || this.file.name.endsWith('.txt')) {
          Text('📄')
            .fontSize(20);
        } else if (this.file.name.endsWith('.json')) {
          Text('📋')
            .fontSize(20);
        } else {
          Text('📁')
            .fontSize(20);
        }
      }
      .width(40)
      .height(40)
      .backgroundColor('#EEEEEE')
      .borderRadius(8)
      .justifyContent(FlexAlign.Center);

      // 文件信息
      Column() {
        Text(this.file.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium);

        Text(`${this.formatSize(this.file.size)}`)
          .fontSize(12)
          .fontColor('#888888');
      }
      .margin({ left: 10 })
      .layoutWeight(1);

      // 操作按钮
      Button('查看')
        .width(60)
        .height(35)
        .backgroundColor('#4CAF50')
        .onClick(() => {
          this.openFile();
        });
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(8);
  }

  /**
   * 打开文件
   */
  openFile(): void {
    // 构建文件 URL
    const fileUrl = `http://${this.serverIp}:${this.httpPort}${this.file.url}`;
    hilog.info(DOMAIN, TAG, `Open file: ${fileUrl}`);

    // TODO: 实现文件预览
    // 根据文件类型打开不同的预览组件
    // 图片: 使用 Image 组件
    // Markdown: 使用 RichEditor 或 WebView
    // PDF: 调用系统打开
  }

  /**
   * 格式化文件大小
   */
  formatSize(size: number): string {
    if (size < 1024) {
      return `${size} B`;
    } else if (size < 1024 * 1024) {
      return `${(size / 1024).toFixed(1)} KB`;
    } else {
      return `${(size / 1024 / 1024).toFixed(1)} MB`;
    }
  }
}