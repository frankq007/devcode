/**
 * 服务器列表页面
 */

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { openCodeService } from '../common/OpenCodeService';
import { serverStorage } from '../common/ServerStorage';
import type { ServerConfig, SessionInfo } from '../common/Types';

const DOMAIN = 0xFF00;
const TAG = 'ServerListPage';

@Entry
@Component
struct ServerListPage {
  @State servers: ServerConfig[] = [];
  @State serverSessionsMap: Map<string, SessionInfo[]> = new Map();
  @State currentSessionId: string = '';
  @State currentServerId: string = '';
  @State loadingServerId: string = '';

  aboutToAppear(): void {
    this.currentSessionId = openCodeService.getCurrentSessionId();
    this.serverSessionsMap.clear();
    this.loadServers();
  }

  private loadServers(): void {
    this.servers = serverStorage.getServers();
    const currentServer: ServerConfig | null = openCodeService.getCurrentServer();
    if (currentServer) {
      this.currentServerId = currentServer.id;
      this.loadSessionsForServer(currentServer);
    } else if (this.servers.length > 0) {
      const defaultServer: ServerConfig | null = serverStorage.getDefaultServer();
      if (defaultServer) {
        this.currentServerId = defaultServer.id;
      } else {
        this.currentServerId = this.servers[0].id;
      }
    }
  }

  private async loadSessionsForServer(server: ServerConfig): Promise<void> {
    this.loadingServerId = server.id;
    
    try {
      await openCodeService.connect(server);
      const sessions: SessionInfo[] = await openCodeService.getSessionList();
      this.serverSessionsMap.set(server.id, sessions);
      this.currentServerId = server.id;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Load sessions failed: %{public}s', JSON.stringify(e));
      this.serverSessionsMap.set(server.id, []);
    }
    
    this.loadingServerId = '';
  }

  private async onServerClick(server: ServerConfig): Promise<void> {
    if (this.loadingServerId.length > 0) {
      return;
    }
    await this.loadSessionsForServer(server);
  }

  private onSessionClick(sessionId: string): void {
    openCodeService.setCurrentSessionId(sessionId);
    router.replaceUrl({ url: 'pages/MainPage' });
  }

  private onServerDetail(server: ServerConfig): void {
    router.pushUrl({ url: 'pages/ServerDetailPage', params: { server: server } });
  }

  private onAddServer(): void {
    router.pushUrl({ url: 'pages/AddServerPage' });
  }

  private getSessions(serverId: string): SessionInfo[] {
    const sessions: SessionInfo[] | undefined = this.serverSessionsMap.get(serverId);
    return sessions || [];
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

        Text('服务器会话列表')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#182431')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank()
          .width(44)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#FFFFFF')

      // 服务器列表
      if (this.servers.length > 0) {
        List() {
          ForEach(this.servers, (server: ServerConfig) => {
            ListItem() {
              ServerSessionGroupComponent({
                server: server,
                sessions: this.getSessions(server.id),
                currentSessionId: this.currentSessionId,
                isLoading: this.loadingServerId === server.id,
                isSelected: server.id === this.currentServerId,
                onServerClick: () => {
                  this.onServerClick(server);
                },
                onServerDetail: () => {
                  this.onServerDetail(server);
                },
                onSessionClick: (sessionId: string) => {
                  this.onSessionClick(sessionId);
                }
              })
            }
          }, (server: ServerConfig) => server.id)

          // 新增服务器按钮
          ListItem() {
            Button() {
              Row() {
                Text('+')
                  .fontSize(20)
                  .fontColor('#007DFF')

                Text('新增服务器')
                  .fontSize(14)
                  .fontColor('#007DFF')
                  .margin({ left: 8 })
              }
            }
            .width('100%')
            .height(56)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .margin({ top: 8 })
            .onClick(() => {
              this.onAddServer();
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#F1F3F5')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      } else {
        // 暂无服务器提示
        Column() {
          Text('暂无服务器')
            .fontSize(14)
            .fontColor('#888888')

          Text('点击下方按钮添加服务器')
            .fontSize(12)
            .fontColor('#AAAAAA')
            .margin({ top: 8 })
        }
        .width('100%')
        .height(100)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .margin({ left: 16, right: 16 })

        Button() {
          Row() {
            Text('+')
              .fontSize(20)
              .fontColor('#007DFF')

            Text('新增服务器')
              .fontSize(14)
              .fontColor('#007DFF')
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .height(56)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .margin({ left: 16, right: 16, top: 8 })
        .onClick(() => {
          this.onAddServer();
        })

        Blank()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}

@Component
struct ServerSessionGroupComponent {
  @Prop server: ServerConfig;
  @Prop sessions: SessionInfo[];
  @Prop currentSessionId: string;
  @Prop isLoading: boolean;
  @Prop isSelected: boolean;
  onServerClick: () => void = () => {};
  onServerDetail: () => void = () => {};
  onSessionClick: (sessionId: string) => void = () => {};

  build() {
    Column() {
      // 连接名称行
      Row() {
        Column() {
          Text(this.server.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isSelected ? '#007DFF' : '#182431')

          Text(`${this.server.ip}:${this.server.port}`)
            .fontSize(12)
            .fontColor(this.isSelected ? '#007DFF' : '#888888')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('>')
          .fontSize(20)
          .fontColor('#007DFF')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.isSelected ? '#E8F4FF' : '#FFFFFF')
      .onClick(() => {
        this.onServerDetail();
      })

      // 会话列表（缩进）
      if (this.isLoading) {
        Row() {
          LoadingProgress()
            .width(16)
            .height(16)
            .color('#007DFF')

          Text('加载中...')
            .fontSize(12)
            .fontColor('#888888')
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 32, top: 8, bottom: 8 })
        .backgroundColor(this.isSelected ? '#F5FAFF' : '#FFFFFF')
      } else if (this.sessions.length > 0 && this.isSelected) {
        ForEach(this.sessions, (session: SessionInfo) => {
          Row() {
            Text(session.title)
              .fontSize(14)
              .fontColor(session.id === this.currentSessionId ? '#007DFF' : '#182431')
              .layoutWeight(1)

            Text(session.id.substring(0, 8))
              .fontSize(12)
              .fontColor(session.id === this.currentSessionId ? '#007DFF' : '#888888')
          }
          .width('100%')
          .padding({ left: 32, right: 16, top: 12, bottom: 12 })
          .backgroundColor(session.id === this.currentSessionId ? '#E8F4FF' : '#FFFFFF')
          .onClick(() => {
            this.onSessionClick(session.id);
          })
        }, (session: SessionInfo) => session.id)
      } else if (this.isSelected) {
        Row() {
          Text('暂无会话')
            .fontSize(12)
            .fontColor('#888888')
        }
        .width('100%')
        .padding({ left: 32, top: 8, bottom: 8 })
        .backgroundColor('#FFFFFF')
      }
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ top: 4, bottom: 4 })
  }
}