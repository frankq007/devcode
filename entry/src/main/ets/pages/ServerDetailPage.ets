/**
 * 服务器详情页面
 */

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { openCodeService } from '../common/OpenCodeService';
import { serverStorage } from '../common/ServerStorage';
import type { ServerConfig } from '../common/Types';

const DOMAIN = 0xFF00;
const TAG = 'ServerDetailPage';

@Entry
@Component
struct ServerDetailPage {
  @State serverName: string = '';
  @State serverIp: string = '';
  @State serverPort: string = '4096';
  @State username: string = '';
  @State password: string = '';
  @State isSaving: boolean = false;
  @State isDeleting: boolean = false;
  @State errorMessage: string = '';
  private serverId: string = '';

  aboutToAppear(): void {
    const params: ESObject = router.getParams() as ESObject;
    if (params && params['server']) {
      const server: ServerConfig = params['server'] as ServerConfig;
      this.serverId = server.id;
      this.serverName = server.name;
      this.serverIp = server.ip;
      this.serverPort = server.port.toString();
      this.username = server.username;
      this.password = server.password;
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Button() {
          Text('←')
            .fontSize(20)
            .fontColor('#182431')
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.back();
        })

        Text('服务器详情')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#182431')
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      // 表单
      Column() {
        // 连接名称
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

        // IP 地址
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

        // 端口
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

        // 用户名
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

        // 密码
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

        // 错误信息
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor('#E84026')
            .margin({ top: 16 })
        }

        // 保存按钮
        Button(this.isSaving ? '保存中...' : '保存')
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor(this.isSaving ? '#AAAAAA' : '#007DFF')
          .borderRadius(22)
          .margin({ top: 32 })
          .enabled(!this.isSaving)
          .onClick(() => {
            this.save();
          })

        // 删除按钮
        Button(this.isDeleting ? '删除中...' : '删除连接')
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor(this.isDeleting ? '#AAAAAA' : '#E84026')
          .borderRadius(22)
          .margin({ top: 16 })
          .enabled(!this.isDeleting)
          .onClick(() => {
            this.delete();
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

  private async save(): Promise<void> {
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

    this.isSaving = true;
    this.errorMessage = '';

    const port: number = parseInt(this.serverPort) || 4096;

    const server: ServerConfig = {
      id: this.serverId,
      name: this.serverName,
      ip: this.serverIp,
      port: port,
      username: this.username,
      password: this.password,
      isDefault: false
    };

    try {
      const success = await openCodeService.connect(server);
      
      if (success) {
        await serverStorage.updateServer(server);
        router.back();
      } else {
        this.errorMessage = '连接失败，请检查配置';
      }
    } catch (e) {
      this.errorMessage = '连接错误: ' + JSON.stringify(e);
    }

    this.isSaving = false;
  }

  private async delete(): Promise<void> {
    this.isDeleting = true;
    openCodeService.disconnect();
    await serverStorage.deleteServer(this.serverId);
    this.isDeleting = false;
    router.back({ url: 'pages/ServerListPage' });
  }
}