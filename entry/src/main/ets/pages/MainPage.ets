/**
 * 主控页面 - HarmonyOS 设计风格
 */

import { router, KeyboardAvoidMode, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { serviceManager } from '../common/ServiceManager';
import { PermissionDialog } from '../components/PermissionDialog';
import { MarkdownRenderer } from '../components/MarkdownRenderer';
import type { TaskMessage, ToolCallInfo, ProgressInfo } from '../common/Types';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { scanBarcode } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0xFF00;
const TAG = 'MainPage';

@Entry
@Component
struct MainPage {
  @State messages: TaskMessage[] = [];
  @State inputText: string = '';
  @State showPermissionDialog: boolean = false;
  @State currentPermissionId: string = '';
  @State currentPermissionCommand: string = '';
  @State currentPermissionExplanation: string = '';
  @State connectionStatus: string = '未连接';
  @State lastAiMessageId: string = '';
  @State showMenu: boolean = false;
  @State keyboardHeight: number = 0;
  @State isVoiceMode: boolean = true;
  @State isRecording: boolean = false;
  @State voiceButtonText: string = '按住说话';
  @State recognizedText: string = '';
  @State isCanceling: boolean = false;
  @State currentStreamMessageId: string = '';
  @State currentStreamContent: string = '';
  @State currentThinking: string = '';
  @State currentToolCalls: ToolCallInfo[] = [];
  @State currentProgress: ProgressInfo | null = null;
  @State showThinking: boolean = false;
  @State showToolCalls: boolean = true;
  private listScroller: Scroller = new Scroller();
  private windowClass: window.Window | null = null;
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private sessionId: string = '';
  private startY: number = 0;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    
    try {
      window.getLastWindow(this.getUIContext().getHostContext()).then((win: window.Window) => {
        this.windowClass = win;
        win.on('keyboardHeightChange', (height: number) => {
          this.keyboardHeight = this.getUIContext().px2vp(height);
        });
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to get window: %{public}s', JSON.stringify(e));
    }
    
    this.initSpeechRecognizer();
    
    if (serviceManager.getConnected()) {
      this.connectionStatus = '已连接';
    }

    serviceManager.onMessage((msg: ESObject) => {
      this.handleMessage(msg);
    });

    serviceManager.onStatusChange((connected: boolean) => {
      this.connectionStatus = connected ? '已连接' : '未连接';
    });
    
    serviceManager.setPageVisible(true);
  }

  onPageShow(): void {
    hilog.info(DOMAIN, TAG, 'onPageShow');
    serviceManager.setPageVisible(true);
    
    const pendingMessages: ESObject[] = serviceManager.getPendingMessages();
    if (pendingMessages.length > 0) {
      hilog.info(DOMAIN, TAG, 'Processing %{public}d pending messages', pendingMessages.length);
      for (let i = 0; i < pendingMessages.length; i++) {
        this.handleMessage(pendingMessages[i]);
      }
    }
  }

  onPageHide(): void {
    hilog.info(DOMAIN, TAG, 'onPageHide');
    serviceManager.setPageVisible(false);
  }

  aboutToDisappear(): void {
    serviceManager.setPageVisible(false);
    if (this.windowClass) {
      this.windowClass.off('keyboardHeightChange');
    }
    if (this.asrEngine) {
      this.asrEngine.shutdown();
    }
  }

  initSpeechRecognizer(): void {
    const extraParams: Record<string, Object> = {
      'locate': 'CN',
      'recognizerMode': 'short'
    };
    const initParams: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1,
      extraParams: extraParams
    };

    speechRecognizer.createEngine(initParams).then((engine: speechRecognizer.SpeechRecognitionEngine) => {
      this.asrEngine = engine;
      hilog.info(DOMAIN, TAG, 'Speech recognizer engine created');
      this.setupRecognitionListener();
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to create engine: %{public}s', err.message);
    });
  }

  setupRecognitionListener(): void {
    if (!this.asrEngine) return;

    const listener: speechRecognizer.RecognitionListener = {
      onStart: (sessionId: string, eventMessage: string) => {
        hilog.info(DOMAIN, TAG, 'onStart: %{public}s', eventMessage);
        this.voiceButtonText = '正在识别...';
      },
      onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
        hilog.info(DOMAIN, TAG, 'onEvent: code=%{public}d, msg=%{public}s', eventCode, eventMessage);
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        hilog.info(DOMAIN, TAG, 'onResult: %{public}s', result.result);
        if (result.isFinal) {
          this.recognizedText = result.result;
        }
      },
      onComplete: (sessionId: string, eventMessage: string) => {
        hilog.info(DOMAIN, TAG, 'onComplete: %{public}s', eventMessage);
        this.isRecording = false;
        this.voiceButtonText = '按住说话';
        if (this.recognizedText.length > 0 && !this.isCanceling) {
          this.inputText = this.recognizedText;
          this.sendCommand();
          this.recognizedText = '';
        }
        this.isCanceling = false;
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        hilog.error(DOMAIN, TAG, 'onError: code=%{public}d, msg=%{public}s', errorCode, errorMessage);
        this.isRecording = false;
        this.voiceButtonText = '按住说话';
        this.isCanceling = false;
      }
    };

    this.asrEngine.setListener(listener);
  }

  startVoiceRecognition(): void {
    if (!this.asrEngine || this.asrEngine.isBusy()) {
      hilog.warn(DOMAIN, TAG, 'Engine not ready or busy');
      return;
    }

    this.sessionId = 'session-' + Date.now().toString();
    this.recognizedText = '';
    this.isCanceling = false;

    const startParams: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      },
      extraParams: {
        'recognitionMode': 0,
        'vadEnd': 2000
      }
    };

    this.asrEngine.startListening(startParams);
    this.isRecording = true;
    this.voiceButtonText = '松开结束';
  }

  stopVoiceRecognition(): void {
    if (this.asrEngine && this.sessionId.length > 0) {
      this.asrEngine.finish(this.sessionId);
    }
  }

  cancelVoiceRecognition(): void {
    if (this.asrEngine && this.sessionId.length > 0) {
      this.isCanceling = true;
      this.asrEngine.cancel(this.sessionId);
      this.voiceButtonText = '已取消';
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶部标题栏 - 固定高度
        Row() {
          Blank()
          
          Text('DevCode')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor('#182431')
          
          Blank()
          
          Stack() {
            Circle()
              .width(28)
              .height(28)
              .fill($r('sys.color.comp_background_primary'))
              .stroke('#007DFF')
              .strokeWidth(2)
            
            Text('+')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#007DFF')
          }
          .width(28)
          .height(28)
          .onClick(() => {
            this.showMenu = !this.showMenu
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
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
        .backgroundColor('#F1F3F5')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .scrollBar(BarState.Off)

        // 输入区域 - 固定在底部
        Column() {
          Row() {
            // 切换按钮 - 使用系统图标
            Button() {
              if (this.isVoiceMode) {
                // 键盘图标
                SymbolGlyph($r('sys.symbol.keyboard'))
                  .fontSize(20)
                  .fontColor([ '#182431' ])
              } else {
                // 麦克风图标
                SymbolGlyph($r('sys.symbol.mic'))
                  .fontSize(20)
                  .fontColor([ '#182431' ])
              }
            }
            .width(44)
            .height(44)
            .backgroundColor('#FFFFFF')
            .borderRadius(22)
            .margin({ right: 8 })
            .onClick(() => {
              this.isVoiceMode = !this.isVoiceMode
              if (!this.isVoiceMode && this.windowClass) {
                this.getUIContext().getFocusController().clearFocus()
              }
            })

            if (this.isVoiceMode) {
              // 语音模式 - 按住说话按钮，支持向上滑动取消
              Button(this.voiceButtonText)
                .layoutWeight(1)
                .height(44)
                .fontSize(16)
                .fontColor(this.isRecording ? Color.White : '#182431')
                .backgroundColor(this.isRecording ? '#007DFF' : '#FFFFFF')
                .borderRadius(22)
                .gesture(
                  GestureGroup(GestureMode.Parallel,
                    PanGesture({ direction: PanDirection.Vertical })
                      .onActionStart((event: GestureEvent) => {
                        this.startY = event.offsetY;
                      })
                      .onActionUpdate((event: GestureEvent) => {
                        if (this.isRecording && event.offsetY - this.startY < -100) {
                          this.cancelVoiceRecognition();
                        }
                      }),
                    LongPressGesture({ repeat: false, duration: 100 })
                      .onAction(() => {
                        this.startVoiceRecognition();
                      })
                      .onActionEnd(() => {
                        if (!this.isCanceling) {
                          this.stopVoiceRecognition();
                        }
                      })
                  )
                )
            } else {
              // 文本模式 - 输入框 + 发送按钮
              TextInput({ placeholder: '输入指令...', text: this.inputText })
                .layoutWeight(1)
                .height(44)
                .backgroundColor('#FFFFFF')
                .borderRadius(22)
                .placeholderColor('#99182431')
                .padding({ left: 16, right: 16 })
                .onChange((value: string) => {
                  this.inputText = value
                })

              Button('发送')
                .width(64)
                .height(44)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor('#007DFF')
                .borderRadius(22)
                .margin({ left: 12 })
                .onClick(() => {
                  this.sendCommand()
                })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })

          // 程序员常用输入键行 - 文本模式且键盘弹出时显示
          if (!this.isVoiceMode && this.keyboardHeight > 0) {
            Row() {
              ForEach(['/', '-', '+', '_', '!'], (key: string) => {
                Button(key)
                  .width(44)
                  .height(40)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .backgroundColor('#FFFFFF')
                  .fontColor('#182431')
                  .borderRadius(8)
                  .margin({ left: 6, right: 6 })
                  .onClick(() => {
                    this.inputText += key
                  })
              }, (key: string) => key)
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .backgroundColor('#F5F5F5')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F1F3F5')

      // 下拉菜单 - 绝对定位，点击外部关闭
      if (this.showMenu) {
        // 透明遮罩层，点击关闭菜单
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.showMenu = false })
          .zIndex(99)
        
        Column() {
          MenuButtonItem({ icon: '[-]', text: '扫一扫', onMenuClick: () => {
            this.showMenu = false
            this.startScan()
          }})
          
          Divider().strokeWidth(0.5).color('#05182431')
          
          MenuButtonItem({ icon: '[+]', text: '新建会话', onMenuClick: () => {
            this.showMenu = false
            if (serviceManager.getConnected()) {
              serviceManager.createNewSession().then((sessionId: string) => {
                if (sessionId.length > 0) {
                  const msg: TaskMessage = {
                    id: 'sys-' + Date.now().toString(),
                    type: 'system',
                    content: '✅ 新会话已创建',
                    timestamp: Date.now(),
                    status: 'completed'
                  }
                  this.messages.push(msg)
                  this.listScroller.scrollEdge(Edge.Bottom)
                }
              })
            } else {
              router.pushUrl({ url: 'pages/ServerListPage' })
            }
          }})
          
          Divider().strokeWidth(0.5).color('#05182431')
          
          MenuButtonItem({ icon: '[=]', text: '会话列表', onMenuClick: () => {
            this.showMenu = false
            router.pushUrl({ url: 'pages/ServerListPage' })
          }})
        }
        .width(120)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .shadow({ radius: 8, color: '#1A000000', offsetY: 2 })
        .position({ x: '100%', y: 56 })
        .translate({ x: -128 })
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
    } else if (msgType === 'error') {
      this.handleError(msg)
    } else if (msgType === 'stream_start') {
      this.handleStreamStart(msg)
    } else if (msgType === 'stream_delta') {
      this.handleStreamDelta(msg)
    }
  }

  handleStreamStart(msg: ESObject): void {
    this.currentStreamMessageId = (msg['messageID'] as string) || 'stream-' + Date.now().toString()
    this.currentStreamContent = ''
    this.currentThinking = ''
    this.currentToolCalls = []
    this.currentProgress = null
    this.showThinking = false
    
    const streamMsg: TaskMessage = {
      id: this.currentStreamMessageId,
      type: 'ai',
      content: '',
      timestamp: Date.now(),
      status: 'running',
      thinking: '',
      toolCalls: [],
      isStreaming: true
    }
    this.messages.push(streamMsg)
    
    setTimeout(() => {
      this.listScroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  handleStreamDelta(msg: ESObject): void {
    const deltaType: string = (msg['deltaType'] as string) || ''
    
    if (deltaType === 'text') {
      const content: string = (msg['content'] as string) || ''
      this.currentStreamContent += content
      this.updateStreamMessage()
    } else if (deltaType === 'thinking') {
      const thinking: string = (msg['content'] as string) || ''
      this.currentThinking += thinking
      this.updateStreamMessage()
    } else if (deltaType === 'tool_start') {
      const toolId: string = (msg['toolId'] as string) || 'tool-' + Date.now().toString()
      const toolName: string = (msg['toolName'] as string) || 'unknown'
      const progress: ProgressInfo | null = this.parseProgress(msg['progress'])
      
      const newTool: ToolCallInfo = {
        id: toolId,
        name: toolName,
        input: '',
        output: '',
        status: 'pending',
        timestamp: Date.now()
      }
      this.currentToolCalls.push(newTool)
      if (progress) {
        this.currentProgress = progress
      }
      this.updateStreamMessage()
    } else if (deltaType === 'tool_input') {
      const toolId: string = (msg['toolId'] as string) || ''
      const toolInput: string = (msg['toolInput'] as string) || ''
      const progress: ProgressInfo | null = this.parseProgress(msg['progress'])
      
      const toolIndex: number = this.currentToolCalls.findIndex((t: ToolCallInfo) => t.id === toolId)
      if (toolIndex >= 0) {
        this.currentToolCalls[toolIndex].input = toolInput
        this.currentToolCalls[toolIndex].status = 'running'
      }
      if (progress) {
        this.currentProgress = progress
      }
      this.updateStreamMessage()
    } else if (deltaType === 'tool_result') {
      const toolId: string = (msg['toolId'] as string) || ''
      const toolOutput: string = (msg['toolOutput'] as string) || ''
      const toolStatus: string = (msg['toolStatus'] as string) || 'completed'
      const progress: ProgressInfo | null = this.parseProgress(msg['progress'])
      
      const toolIndex: number = this.currentToolCalls.findIndex((t: ToolCallInfo) => t.id === toolId)
      if (toolIndex >= 0) {
        this.currentToolCalls[toolIndex].output = toolOutput
        this.currentToolCalls[toolIndex].status = toolStatus as 'pending' | 'running' | 'completed' | 'error'
      }
      if (progress) {
        this.currentProgress = progress
      }
      this.updateStreamMessage()
    }
  }

  parseProgress(progressData: ESObject): ProgressInfo | null {
    if (!progressData) return null
    return {
      current: (progressData['current'] as number) || 0,
      total: (progressData['total'] as number) || 0,
      description: (progressData['description'] as string) || ''
    }
  }

  updateStreamMessage(): void {
    const index: number = this.messages.findIndex((m: TaskMessage) => m.id === this.currentStreamMessageId)
    if (index >= 0) {
      const updatedMsg: TaskMessage = {
        id: this.currentStreamMessageId,
        type: 'ai',
        content: this.currentStreamContent,
        timestamp: this.messages[index].timestamp,
        status: 'running',
        thinking: this.currentThinking,
        toolCalls: this.currentToolCalls.slice(),
        isStreaming: true
      }
      if (this.currentProgress) {
        updatedMsg.progress = this.currentProgress
      }
      this.messages[index] = updatedMsg
      this.messages = [...this.messages]
    }
    
    setTimeout(() => {
      this.listScroller.scrollEdge(Edge.Bottom)
    }, 50)
  }

  handleAiResponse(msg: ESObject): void {
    const content: string = msg['content'] as string || ''
    const messageId: string = msg['messageID'] as string || ''
    
    if (this.currentStreamMessageId.length > 0) {
      const index: number = this.messages.findIndex((m: TaskMessage) => m.id === this.currentStreamMessageId)
      if (index >= 0) {
        const existingMsg: TaskMessage = this.messages[index]
        this.messages[index] = {
          id: this.currentStreamMessageId,
          type: 'ai',
          content: content,
          timestamp: existingMsg.timestamp,
          status: 'completed',
          thinking: existingMsg.thinking,
          toolCalls: existingMsg.toolCalls,
          progress: existingMsg.progress,
          isStreaming: false
        }
        this.messages = [...this.messages]
      }
      this.currentStreamMessageId = ''
    } else {
      this.messages = this.messages.filter((m: TaskMessage) => m.status !== 'running')
      
      const newMsg: TaskMessage = {
        id: 'ai-' + messageId,
        type: 'ai',
        content: content,
        timestamp: Date.now(),
        status: 'completed'
      }
      this.messages.push(newMsg)
    }
    this.lastAiMessageId = messageId
    
    setTimeout(() => {
      this.listScroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  handleTaskStatus(msg: ESObject): void {
    const statusStr: string = msg['status'] as string
    
    if (statusStr === 'idle' || statusStr === 'ready') {
      if (this.currentStreamMessageId.length > 0) {
        const index: number = this.messages.findIndex((m: TaskMessage) => m.id === this.currentStreamMessageId)
        if (index >= 0 && this.messages[index].status === 'running') {
          this.messages[index].status = 'completed'
          this.messages[index].isStreaming = false
          this.messages = [...this.messages]
        }
        this.currentStreamMessageId = ''
      }
      this.messages = this.messages.filter((m: TaskMessage) => m.status !== 'running')
    }
  }

  handlePermissionRequest(msg: ESObject): void {
    this.currentPermissionId = msg['id'] as string
    this.currentPermissionCommand = msg['command'] as string
    this.currentPermissionExplanation = msg['explanation'] as string || '需要授权'
    this.showPermissionDialog = true
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
    if (this.inputText.trim().length === 0) return

    if (!serviceManager.getConnected()) {
      hilog.warn(DOMAIN, TAG, 'OpenCode not connected')
      const msg: TaskMessage = {
        id: 'err-' + Date.now().toString(),
        type: 'system',
        content: '请先连接服务器',
        timestamp: Date.now(),
        status: 'error'
      }
      this.messages.push(msg)
      return
    }

    hilog.info(DOMAIN, TAG, 'Sending command: %{public}s', this.inputText)

    const userMsg: TaskMessage = {
      id: 'user-' + Date.now().toString(),
      type: 'user',
      content: this.inputText,
      timestamp: Date.now(),
      status: 'pending'
    }
    this.messages.push(userMsg)
    serviceManager.sendMessage(this.inputText)
    this.inputText = ''
    
    setTimeout(() => {
      this.listScroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  replyPermission(answer: string): void {
    if (this.currentPermissionId.length > 0) {
      serviceManager.respondToPermission(this.currentPermissionId, answer)
      this.showPermissionDialog = false
    }
  }

  async startScan(): Promise<void> {
    this.showMenu = false
    
    try {
      const options: scanBarcode.ScanOptions = {
        enableMultiMode: false,
        enableAlbum: true
      }
      
      scanBarcode.startScan(options, (error: BusinessError, result: scanBarcode.ScanResult) => {
        if (error) {
          hilog.error(DOMAIN, TAG, 'Scan failed: %{public}s', error.message)
        } else if (result && result.originalValue) {
          hilog.info(DOMAIN, TAG, 'Scan result: %{public}s', result.originalValue)
          this.parseQRCode(result.originalValue)
        }
      })
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Scan failed: %{public}s', JSON.stringify(e))
    }
  }

  private parseQRCode(qrContent: string): void {
    try {
      const data: ESObject = JSON.parse(qrContent) as ESObject
      
      const ip: string = (data['ip'] as string) || ''
      const port: string = (data['port'] as string) || '4096'
      const username: string = (data['username'] as string) || ''
      const password: string = (data['password'] as string) || ''
      
      if (ip.length > 0) {
        router.pushUrl({
          url: 'pages/AddServerPage',
          params: {
            serverIp: ip,
            serverPort: port,
            username: username,
            password: password
          }
        })
      } else {
        hilog.warn(DOMAIN, TAG, 'QR code missing IP address')
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Parse QR code failed: %{public}s', JSON.stringify(e))
    }
  }
}

// 菜单项组件
@Component
struct MenuButtonItem {
  @Prop icon: string = ''
  @Prop text: string = ''
  onMenuClick: () => void = () => {}

  build() {
    Row() {
      Text(this.icon)
        .fontSize(14)
        .fontColor('#182431')
        .width(32)
      
      Text(this.text)
        .fontSize(14)
        .fontColor('#182431')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .onClick(() => { this.onMenuClick() })
  }
}

// 聊天气泡组件 - 简洁圆角矩形风格
@Component
struct ChatBubble {
  @Prop message: TaskMessage
  @State showThinkingContent: boolean = false
  @State showToolOutputs: Set<string> = new Set()

  build() {
    Column() {
      if (this.message.type === 'user') {
        // 用户消息 - 右对齐
        Row() {
          Blank()
          
          Column() {
            Text(this.message.content)
              .fontSize(16)
              .fontColor(Color.White)
              .maxLines(100)
              .textOverflow({ overflow: TextOverflow.Clip })
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            
            if (this.message.status === 'running') {
              Row() {
                LoadingProgress().width(16).height(16).color(Color.White)
                Text('发送中').fontSize(12).fontColor(Color.White).margin({ left: 6 })
              }.margin({ top: 4, bottom: 4 })
            }
          }
          .backgroundColor('#007DFF')
          .borderRadius(12)
          .constraintSize({ minWidth: 40, maxWidth: '70%' })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
      } else {
        // AI消息 - 左对齐
        Row() {
          Column() {
            // 进度指示
            if (this.message.progress && this.message.isStreaming) {
              this.ProgressIndicator(
                this.message.progress.current,
                this.message.progress.total,
                this.message.progress.description
              )
            }
            
            // 思考过程（折叠）
            if (this.message.thinking && this.message.thinking.length > 0) {
              this.ThinkingSection(
                this.message.thinking,
                this.showThinkingContent,
                () => { this.showThinkingContent = !this.showThinkingContent }
              )
            }
            
            // 工具调用
            if (this.message.toolCalls && this.message.toolCalls.length > 0) {
              ForEach(this.message.toolCalls, (tool: ToolCallInfo) => {
                this.ToolCallSection(
                  tool.id,
                  tool.name,
                  tool.input,
                  tool.output || '',
                  tool.status,
                  this.showToolOutputs.has(tool.id),
                  () => {
                    if (this.showToolOutputs.has(tool.id)) {
                      this.showToolOutputs.delete(tool.id)
                    } else {
                      this.showToolOutputs.add(tool.id)
                    }
                    this.showToolOutputs = new Set(this.showToolOutputs)
                  }
                )
              }, (tool: ToolCallInfo) => tool.id)
            }
            
            // 文本内容
            if (this.message.content.length > 0 || this.message.status === 'running') {
              if (this.message.status === 'running' && this.message.content.length === 0) {
                Row() {
                  LoadingProgress().width(16).height(16).color('#007DFF')
                  Text('正在思考...').fontSize(14).fontColor('#99182431').margin({ left: 6 })
                }
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .width('100%')
              } else {
                MarkdownRenderer({ content: this.message.content })
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              }
            }
          }
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .width('85%')
          .alignItems(HorizontalAlign.Start)
          
          Blank()
        }
        .width('100%')
      }
    }
    .width('100%')
    .margin({ top: 6, bottom: 6 })
  }

  @Builder
  ProgressIndicator(current: number, total: number, description: string): void {
    Row() {
      LoadingProgress().width(12).height(12).color('#007DFF')
      
      if (total > 0) {
        Text(`第 ${current}/${total} 步`)
          .fontSize(12)
          .fontColor('#007DFF')
          .margin({ left: 8 })
      }
      
      if (description.length > 0) {
        Text(description)
          .fontSize(12)
          .fontColor('#99182431')
          .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor('#F0F7FF')
    .borderRadius({ topLeft: 12, topRight: 12 })
  }

  @Builder
  ThinkingSection(thinking: string, isExpanded: boolean, onToggle: () => void): void {
    Column() {
      Row() {
        Text('💭')
          .fontSize(14)
          .margin({ right: 6 })
        
        Text('思考过程')
          .fontSize(14)
          .fontColor('#182431')
          .fontWeight(FontWeight.Medium)
        
        Blank()
        
        Text(isExpanded ? '收起' : '展开')
          .fontSize(12)
          .fontColor('#007DFF')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .onClick(() => { onToggle() })
      
      if (isExpanded) {
        Text(thinking)
          .fontSize(13)
          .fontColor('#666666')
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
          .maxLines(50)
      }
    }
    .width('100%')
    .backgroundColor('#FFF8E1')
    .borderRadius(8)
    .margin({ bottom: 4 })
  }

  @Builder
  ToolCallSection(toolId: string, toolName: string, toolInput: string, toolOutput: string, 
                  toolStatus: 'pending' | 'running' | 'completed' | 'error', 
                  isExpanded: boolean, onToggle: () => void): void {
    Column() {
      Row() {
        if (toolStatus === 'running') {
          LoadingProgress().width(12).height(12).color('#007DFF')
        } else if (toolStatus === 'completed') {
          Text('✓')
            .fontSize(14)
            .fontColor('#4CAF50')
        } else if (toolStatus === 'error') {
          Text('✗')
            .fontSize(14)
            .fontColor('#E84026')
        } else {
          Text('○')
            .fontSize(14)
            .fontColor('#99182431')
        }
        
        Text('🔧')
          .fontSize(14)
          .margin({ left: 6, right: 4 })
        
        Text(toolName)
          .fontSize(13)
          .fontColor('#182431')
          .fontWeight(FontWeight.Medium)
        
        if (toolInput.length > 0 && toolInput.length < 50) {
          Text(toolInput)
            .fontSize(12)
            .fontColor('#666666')
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        
        Blank()
        
        if (toolOutput && toolOutput.length > 0) {
          Text(isExpanded ? '收起' : '查看输出')
            .fontSize(12)
            .fontColor('#007DFF')
            .onClick(() => { onToggle() })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      
      if (isExpanded && toolOutput && toolOutput.length > 0) {
        Column() {
          Text('输出:')
            .fontSize(12)
            .fontColor('#888888')
            .margin({ bottom: 4 })
          
          Text(toolOutput)
            .fontSize(12)
            .fontColor('#182431')
            .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
        .backgroundColor('#F5F5F5')
      }
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .margin({ bottom: 4 })
  }
}