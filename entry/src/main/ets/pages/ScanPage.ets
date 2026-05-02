/**
 * 扫码配对页面
 * 
 * 功能：
 * - 扫描二维码获取连接配置
 * - 建立 WebSocket 连接
 * - 完成认证后跳转到主控页面
 */

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cameraKit } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { wsService } from '../common/WebSocketService';
import type { ConnectionConfig } from '../common/Types';
import { PermissionDialog } from '../components/PermissionDialog';

const DOMAIN = 0xFF00;
const TAG = 'ScanPage';

@Entry
@Component
struct ScanPage {
  @State isScanning: boolean = false;
  @State statusText: string = '准备扫码';
  @State showError: boolean = false;
  @State errorMsg: string = '';
  @State manualInput: string = '';
  @State showManualInput: boolean = false;

  build() {
    Column() {
      // 标题
      Text($r('app.string.scan_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 40, bottom: 20 });

      // 说明
      Text($r('app.string.scan_instruction'))
        .fontSize(16)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
        .width('80%')
        .margin({ bottom: 30 });

      // 扫码区域
      if (!this.showManualInput) {
        Stack() {
          // 扫码框
          Column() {
            if (this.isScanning) {
              // 显示扫描动画/提示
              Column() {
                Text('正在扫描...')
                  .fontSize(18)
                  .fontColor('#FFFFFF')
                  .margin({ top: 80 });

                Progress({ value: 50, total: 100, type: ProgressType.Linear })
                  .width('60%')
                  .color('#4CAF50')
                  .margin({ top: 20 });
              }
              .width(280)
              .height(280)
              .backgroundColor('#1A1A1A')
              .borderRadius(16)
              .justifyContent(FlexAlign.Center);
            } else {
              // 扫码按钮
              Column() {
                Image($r('app.media.startIcon'))
                  .width(60)
                  .height(60)
                  .margin({ bottom: 10 });

                Text('点击开始扫码')
                  .fontSize(16)
                  .fontColor('#FFFFFF');
              }
              .width(280)
              .height(280)
              .backgroundColor('#2A2A2A')
              .borderRadius(16)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.startScan();
              });
            }
          }
          .width(280)
          .height(280);

          // 扫描框边框
          Rect()
            .width(280)
            .height(280)
            .fillOpacity(0)
            .stroke('#4CAF50')
            .strokeWidth(2)
            .radius(16);
        }
        .margin({ bottom: 30 });
      }

      // 手动输入区域
      if (this.showManualInput) {
        Column() {
          TextInput({ placeholder: '输入服务器地址 (如: 100.64.0.2:8080)' })
            .width('80%')
            .height(50)
            .margin({ bottom: 10 })
            .onChange((value) => {
              this.manualInput = value;
            });

          Button('连接')
            .width('80%')
            .height(50)
            .backgroundColor('#4CAF50')
            .onClick(() => {
              this.connectManual();
            });
        }
        .width('100%')
        .margin({ bottom: 30 });
      }

      // 切换按钮
      Button(this.showManualInput ? '使用扫码' : '手动输入')
        .width('60%')
        .height(40)
        .backgroundColor('#666666')
        .onClick(() => {
          this.showManualInput = !this.showManualInput;
        });

      // 状态文字
      Text(this.statusText)
        .fontSize(14)
        .fontColor('#888888')
        .margin({ top: 20 });

      // 错误提示
      if (this.showError) {
        Column() {
          Text(this.errorMsg)
            .fontSize(14)
            .fontColor('#FF5722')
            .margin({ top: 10 });

          Button('重试')
            .width('40%')
            .height(35)
            .backgroundColor('#FF5722')
            .margin({ top: 10 })
            .onClick(() => {
              this.showError = false;
              this.statusText = '准备扫码';
            });
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
    .justifyContent(FlexAlign.Start);
  }

  /**
   * 开始扫码
   * 注意：实际扫码需要使用 Scan Kit，这里提供简化实现
   */
  startScan(): void {
    this.isScanning = true;
    this.statusText = '请将二维码放入框内';

    // 模拟扫码成功（实际应使用 Scan Kit）
    // 在实际项目中，需要集成 @ohos.scanKit 进行扫码
    // 这里提供一个模拟流程用于开发测试
    
    // 测试用的模拟连接配置
    const testConfig: ConnectionConfig = {
      token: 'test-token-' + Date.now(),
      expire: Date.now() + 5 * 60 * 1000,
      ip: '100.64.0.2',  // 替换为实际的 Tailscale IP
      wsPort: 8080,
      httpPort: 8081
    };

    // 模拟扫码结果
    // 实际实现需要使用 Scan Kit 的 scanCore.scan()
    setTimeout(() => {
      this.handleScanResult('devcode://connect?token=' + testConfig.token + 
        '&expire=' + testConfig.expire + '&ip=' + testConfig.ip +
        '&wsPort=' + testConfig.wsPort + '&httpPort=' + testConfig.httpPort);
    }, 2000);
  }

  /**
   * 处理扫码结果
   */
  handleScanResult(result: string): void {
    hilog.info(DOMAIN, TAG, `Scan result: ${result}`);

    try {
      // 解析 URL
      const config = this.parseConnectUrl(result);
      if (!config) {
        this.showError = true;
        this.errorMsg = '无效的二维码内容';
        this.isScanning = false;
        return;
      }

      // 检查过期时间
      if (Date.now() > config.expire) {
        this.showError = true;
        this.errorMsg = '二维码已过期，请在电脑端重新生成';
        this.isScanning = false;
        return;
      }

      // 开始连接
      this.statusText = '正在连接服务器...';
      this.connect(config);

    } catch (e) {
      hilog.error(DOMAIN, TAG, `Parse error: ${e}`);
      this.showError = true;
      this.errorMsg = '解析二维码失败';
      this.isScanning = false;
    }
  }

  /**
   * 解析连接 URL
   */
  parseConnectUrl(url: string): ConnectionConfig | null {
    try {
      // 格式: devcode://connect?token=xxx&expire=xxx&ip=xxx&wsPort=xxx&httpPort=xxx
      if (!url.startsWith('devcode://connect?')) {
        return null;
      }

      const queryStr = url.substring('devcode://connect?'.length);
      const params = new Map<string, string>();

      queryStr.split('&').forEach((pair: string) => {
        const [key, value] = pair.split('=');
        params.set(key, value);
      });

      return {
        token: params.get('token') || '',
        expire: parseInt(params.get('expire') || '0'),
        ip: params.get('ip') || '',
        wsPort: parseInt(params.get('wsPort') || '8080'),
        httpPort: parseInt(params.get('httpPort') || '8081')
      };
    } catch (e) {
      hilog.error(DOMAIN, TAG, `URL parse error: ${e}`);
      return null;
    }
  }

  /**
   * 连接服务器
   */
  async connect(config: ConnectionConfig): void {
    try {
      const success = await wsService.connect(config);

      if (success) {
        this.statusText = '已连接，等待认证...';
        // 注册消息回调监听认证结果
        wsService.onMessage((msg) => {
          if (msg.type === 'auth_result') {
            const authResult = msg as ESObject;
            if (authResult.success) {
              hilog.info(DOMAIN, TAG, 'Auth success');
              // 认证成功，跳转到主控页面
              router.replaceUrl({
                url: 'pages/MainPage',
                params: {
                  serverIp: config.ip,
                  httpPort: config.httpPort
                }
              });
            } else {
              this.showError = true;
              this.errorMsg = authResult.message || '认证失败';
              this.isScanning = false;
            }
          }
        });
      } else {
        this.showError = true;
        this.errorMsg = '连接失败，请检查网络';
        this.isScanning = false;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Connect error: ${e}`);
      this.showError = true;
      this.errorMsg = '连接异常: ' + e;
      this.isScanning = false;
    }
  }

  /**
   * 手动连接
   */
  connectManual(): void {
    const parts = this.manualInput.split(':');
    if (parts.length < 2) {
      this.showError = true;
      this.errorMsg = '请输入完整地址，格式: IP:端口';
      return;
    }

    // 手动连接需要用户输入 token（或服务器生成固定 token）
    // 这里简化处理，实际应从服务器获取 token
    this.statusText = '请先在电脑端访问 /qrcode 获取 token';
  }
}