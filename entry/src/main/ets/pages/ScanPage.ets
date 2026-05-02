/**
 * 扫码配对页面 (ArkTS 兼容版本)
 */
 
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { wsService } from '../common/WebSocketService';
import type { ConnectionConfig } from '../common/Types';
 
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
      Text($r('app.string.scan_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 40, bottom: 20 });
 
      Text($r('app.string.scan_instruction'))
        .fontSize(16)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
        .width('80%')
        .margin({ bottom: 30 });
 
      if (!this.showManualInput) {
        Stack() {
          Column() {
            if (this.isScanning) {
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
 
      if (this.showManualInput) {
        Column() {
          TextInput({ placeholder: '输入服务器地址 (如: 100.64.0.2:8080)' })
            .width('80%')
            .height(50)
            .margin({ bottom: 10 })
            .onChange((value: string) => {
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
 
      Button(this.showManualInput ? '使用扫码' : '手动输入')
        .width('60%')
        .height(40)
        .backgroundColor('#666666')
        .onClick(() => {
          this.showManualInput = !this.showManualInput;
        });
 
      Text(this.statusText)
        .fontSize(14)
        .fontColor('#888888')
        .margin({ top: 20 });
 
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
 
  startScan(): void {
    this.isScanning = true;
    this.statusText = '请将二维码放入框内';
    
    const testConfig: ConnectionConfig = {
      token: 'test-token-' + Date.now().toString(),
      expire: Date.now() + 5 * 60 * 1000,
      ip: '100.64.0.2',
      wsPort: 8080,
      httpPort: 8081
    };
 
    setTimeout(() => {
      const url: string = 'devcode://connect?token=' + testConfig.token +
        '&expire=' + testConfig.expire.toString() + '&ip=' + testConfig.ip +
        '&wsPort=' + testConfig.wsPort.toString() + '&httpPort=' + testConfig.httpPort.toString();
      this.handleScanResult(url);
    }, 2000);
  }
 
  handleScanResult(result: string): void {
    hilog.info(DOMAIN, TAG, `Scan result: ${result}`);
    
    try {
      const config = this.parseConnectUrl(result);
      if (config === null) {
        this.showError = true;
        this.errorMsg = '无效的二维码内容';
        this.isScanning = false;
        return;
      }
 
      if (Date.now() > config.expire) {
        this.showError = true;
        this.errorMsg = '二维码已过期，请在电脑端重新生成';
        this.isScanning = false;
        return;
      }
 
      this.statusText = '正在连接服务器...';
      this.doConnect(config);
      
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Parse error: ${e}`);
      this.showError = true;
      this.errorMsg = '解析二维码失败';
      this.isScanning = false;
    }
  }
 
  parseConnectUrl(url: string): ConnectionConfig | null {
    try {
      if (!url.startsWith('devcode://connect?')) {
        return null;
      }
 
      const prefixLen: number = 'devcode://connect?'.length;
      const queryStr: string = url.substring(prefixLen);
      const pairs: string[] = queryStr.split('&');
      const params: Map<string, string> = new Map();
      
      for (let i = 0; i < pairs.length; i++) {
        const pair: string = pairs[i];
        const parts: string[] = pair.split('=');
        if (parts.length === 2) {
          params.set(parts[0], parts[1]);
        }
      }
      
      const token: string = params.get('token') || '';
      const expireStr: string = params.get('expire') || '0';
      const ip: string = params.get('ip') || '';
      const wsPortStr: string = params.get('wsPort') || '8080';
      const httpPortStr: string = params.get('httpPort') || '8081';
      
      if (token.length === 0 || ip.length === 0) {
        return null;
      }
      
      const expire: number = parseInt(expireStr);
      if (isNaN(expire)) {
        return null;
      }
      
      return {
        token: token,
        expire: expire,
        ip: ip,
        wsPort: parseInt(wsPortStr),
        httpPort: parseInt(httpPortStr)
      };
    } catch (e) {
      hilog.error(DOMAIN, TAG, `URL parse error: ${e}`);
      return null;
    }
  }
 
  doConnect(config: ConnectionConfig): void {
    wsService.connect(config).then((success: boolean) => {
      if (success) {
        this.statusText = '已连接，等待认证...';
        wsService.onMessage((msg: ESObject) => {
          const msgType: string = msg['type'] as string;
          if (msgType === 'auth_result') {
            const authSuccess: boolean = msg['success'] as boolean;
            if (authSuccess) {
              hilog.info(DOMAIN, TAG, 'Auth success');
              router.replaceUrl({
                url: 'pages/MainPage',
                params: {
                  serverIp: config.ip,
                  httpPort: config.httpPort
                }
              });
            } else {
              this.showError = true;
              const authMessage: string = msg['message'] as string || '认证失败';
              this.errorMsg = authMessage;
              this.isScanning = false;
            }
          }
        });
      } else {
        this.showError = true;
        this.errorMsg = '连接失败，请检查网络';
        this.isScanning = false;
      }
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, `Connect error: ${e.message}`);
      this.showError = true;
      this.errorMsg = '连接异常';
      this.isScanning = false;
    });
  }
 
  connectManual(): void {
    const parts: string[] = this.manualInput.split(':');
    if (parts.length < 2) {
      this.showError = true;
      this.errorMsg = '请输入完整地址，格式: IP:端口';
      return;
    }
    
    this.statusText = '请先在电脑端访问 /qrcode 获取 token';
  }
}