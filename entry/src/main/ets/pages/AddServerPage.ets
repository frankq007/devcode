/**
 * 添加服务器页面
 */

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { serviceManager, ConnectionMode } from '../common/ServiceManager';
import { relayService } from '../common/RelayService';
import { serverStorage } from '../common/ServerStorage';
import type { ServerConfig, RelayConfig, AgentInfo } from '../common/Types';

const DOMAIN = 0xFF00;
const TAG = 'AddServerPage';

@Entry
@Component
struct AddServerPage {
  @State connectionMode: ConnectionMode = 'direct';
  @State serverName: string = '';
  @State serverIp: string = '';
  @State serverPort: string = '4096';
  @State username: string = '';
  @State password: string = '';
  @State relayUrl: string = '';
  @State agentId: string = '';
  @State agents: AgentInfo[] = [];
  @State isConnecting: boolean = false;
  @State errorMessage: string = '';
  @State isFetchingAgents: boolean = false;

  aboutToAppear(): void {
    const params: ESObject = router.getParams() as ESObject;
    if (params) {
      if (params['mode']) {
        this.connectionMode = (params['mode'] as string) === 'relay' ? 'relay' : 'direct';
      }
      if (params['serverIp']) {
        this.serverIp = params['serverIp'] as string;
      }
      if (params['serverPort']) {
        this.serverPort = params['serverPort'] as string;
      }
      if (params['username']) {
        this.username = params['username'] as string;
      }
      if (params['password']) {
        this.password = params['password'] as string;
      }
      if (params['relayUrl']) {
        this.relayUrl = params['relayUrl'] as string;
      }
      if (params['agentId']) {
        this.agentId = params['agentId'] as string;
      }
    }
  }

  build() {
    Column() {
      Row() {
        Text('添加服务器')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#182431')
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')
      .justifyContent(FlexAlign.Center)

      Column() {
        Row() {
          Text('连接模式')
            .fontSize(14)
            .fontColor('#888888')
            .width(80)
            .flexShrink(0)

          Row() {
            Button('直连')
              .height(32)
              .fontSize(14)
              .fontColor(this.connectionMode === 'direct' ? Color.White : '#007DFF')
              .backgroundColor(this.connectionMode === 'direct' ? '#007DFF' : '#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                this.connectionMode = 'direct';
              })

            Button('云中转')
              .height(32)
              .fontSize(14)
              .fontColor(this.connectionMode === 'relay' ? Color.White : '#007DFF')
              .backgroundColor(this.connectionMode === 'relay' ? '#007DFF' : '#FFFFFF')
              .borderRadius(8)
              .margin({ left: 8 })
              .onClick(() => {
                this.connectionMode = 'relay';
              })
          }
        }
        .width('100%')
        .margin({ top: 16 })
        .alignItems(VerticalAlign.Center)

        if (this.connectionMode === 'direct') {
          this.DirectModeForm()
        } else {
          this.RelayModeForm()
        }

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor('#E84026')
            .margin({ top: 16 })
        }

        Button(this.isConnecting ? '连接中...' : '连接')
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor(this.isConnecting ? '#AAAAAA' : '#007DFF')
          .borderRadius(22)
          .margin({ top: 32 })
          .enabled(!this.isConnecting)
          .onClick(() => {
            this.connect();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }

  @Builder
  DirectModeForm(): void {
    Column() {
      Row() {
        Text('连接名称')
          .fontSize(14)
          .fontColor('#888888')
          .width(80)
          .flexShrink(0)

        TextInput({ placeholder: '例如: 我的开发机', text: this.serverName })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .onChange((value: string) => {
            this.serverName = value;
          })
      }
      .width('100%')
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('IP 地址')
          .fontSize(14)
          .fontColor('#888888')
          .width(80)
          .flexShrink(0)

        TextInput({ placeholder: '例如: 192.168.1.100', text: this.serverIp })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .onChange((value: string) => {
            this.serverIp = value;
          })
      }
      .width('100%')
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('端口号')
          .fontSize(14)
          .fontColor('#888888')
          .width(80)
          .flexShrink(0)

        TextInput({ placeholder: '默认: 4096', text: this.serverPort })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .onChange((value: string) => {
            this.serverPort = value;
          })
      }
      .width('100%')
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('用户名')
          .fontSize(14)
          .fontColor('#888888')
          .width(80)
          .flexShrink(0)

        TextInput({ placeholder: 'OpenCode Serve 用户名', text: this.username })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .onChange((value: string) => {
            this.username = value;
          })
      }
      .width('100%')
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('密码')
          .fontSize(14)
          .fontColor('#888888')
          .width(80)
          .flexShrink(0)

        TextInput({ placeholder: 'OpenCode Serve 密码', text: this.password })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .type(InputType.Password)
          .onChange((value: string) => {
            this.password = value;
          })
      }
      .width('100%')
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  RelayModeForm(): void {
    Column() {
      Row() {
        Text('云服务器')
          .fontSize(14)
          .fontColor('#888888')
          .width(80)
          .flexShrink(0)

        TextInput({ placeholder: '例如: wss://relay.example.com', text: this.relayUrl })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .onChange((value: string) => {
            this.relayUrl = value;
          })
      }
      .width('100%')
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('Agent ID')
          .fontSize(14)
          .fontColor('#888888')
          .width(80)
          .flexShrink(0)

        TextInput({ placeholder: '例如: my-agent', text: this.agentId })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .onChange((value: string) => {
            this.agentId = value;
          })
      }
      .width('100%')
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Button(this.isFetchingAgents ? '获取中...' : '获取 Agent 列表')
          .height(36)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(this.relayUrl.length > 0 && !this.isFetchingAgents ? '#007DFF' : '#AAAAAA')
          .borderRadius(18)
          .enabled(this.relayUrl.length > 0 && !this.isFetchingAgents)
          .onClick(() => {
            this.fetchAgents();
          })
      }
      .width('100%')
      .margin({ top: 16 })

      if (this.agents.length > 0) {
        Column() {
          Text('可选 Agent:')
            .fontSize(14)
            .fontColor('#888888')
            .margin({ top: 8 })

          ForEach(this.agents, (agent: AgentInfo) => {
            Row() {
              Radio({ value: agent.agentId, group: 'agentGroup' })
                .checked(this.agentId === agent.agentId)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.agentId = agent.agentId;
                  }
                })

              Text(agent.name)
                .fontSize(14)
                .fontColor('#182431')
                .margin({ left: 8 })
            }
            .width('100%')
            .margin({ top: 8 })
          })
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
  }

  private async connect(): Promise<void> {
    if (this.connectionMode === 'direct') {
      await this.connectDirect();
    } else {
      await this.connectRelay();
    }
  }

  private async connectDirect(): Promise<void> {
    if (this.serverName.length === 0) {
      this.errorMessage = '请输入连接名称';
      return;
    }
    if (this.serverIp.length === 0) {
      this.errorMessage = '请输入 IP 地址';
      return;
    }
    if (this.username.length === 0) {
      this.errorMessage = '请输入用户名';
      return;
    }
    if (this.password.length === 0) {
      this.errorMessage = '请输入密码';
      return;
    }

    this.isConnecting = true;
    this.errorMessage = '';

    const port: number = parseInt(this.serverPort) || 4096;

    const server: ServerConfig = {
      id: 'server-' + Date.now().toString(),
      name: this.serverName,
      ip: this.serverIp,
      port: port,
      username: this.username,
      password: this.password,
      isDefault: false
    };

    try {
      serviceManager.setMode('direct');
      const success: boolean = await serviceManager.connectDirect(server);
      
      if (success) {
        await serverStorage.addServer(server);
        router.replaceUrl({ url: 'pages/MainPage' });
      } else {
        this.errorMessage = '连接失败，请检查配置';
      }
    } catch (e) {
      this.errorMessage = '连接错误: ' + JSON.stringify(e);
    }

    this.isConnecting = false;
  }

  private async connectRelay(): Promise<void> {
    if (this.relayUrl.length === 0) {
      this.errorMessage = '请输入云服务器地址';
      return;
    }
    if (this.agentId.length === 0) {
      this.errorMessage = '请输入 Agent ID';
      return;
    }

    this.isConnecting = true;
    this.errorMessage = '';

    const config: RelayConfig = {
      serverUrl: this.relayUrl,
      agentId: this.agentId
    };

    try {
      serviceManager.setMode('relay');
      const success: boolean = await serviceManager.connectRelay(config);
      
      if (success) {
        router.replaceUrl({ url: 'pages/MainPage' });
      } else {
        this.errorMessage = '连接失败，请检查云服务器和 Agent ID';
      }
    } catch (e) {
      this.errorMessage = '连接错误: ' + JSON.stringify(e);
    }

    this.isConnecting = false;
  }

  private async fetchAgents(): Promise<void> {
    if (this.relayUrl.length === 0) return;

    this.isFetchingAgents = true;
    this.errorMessage = '';

    const config: RelayConfig = {
      serverUrl: this.relayUrl,
      agentId: ''
    };

    try {
      relayService.onAgentList((agents: AgentInfo[]) => {
        this.agents = agents;
        this.isFetchingAgents = false;
      });

      const connected: boolean = await relayService.connect(config);
      if (!connected) {
        this.errorMessage = '无法连接云服务器获取 Agent 列表';
        this.isFetchingAgents = false;
      }
    } catch (e) {
      this.errorMessage = '获取 Agent 列表失败';
      this.isFetchingAgents = false;
    }
  }
}