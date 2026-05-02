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
  @State showManualInput: boolean = false;
  
  // 手动输入字段
  @State manualIp: string = '';
  @State manualWsPort: string = '8080';
  @State manualHttpPort: string = '8081';
  @State manualToken: string = '';
 
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
        // 扫码区域
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
        // 手动输入区域
        Column() {
          // 提示
          Text('请先在电脑浏览器访问 http://服务器IP:8081/qrcode 获取配对信息')
            .fontSize(12)
            .fontColor('#888888')
            .width('85%')
            .margin({ bottom: 15 });
 
          // IP输入
          TextInput({ placeholder: '服务器IP (如: 100.117.37.34)', text: this.manualIp })
            .width('85%')
            .height(45)
            .margin({ bottom: 8 })
            .onChange((value: string) => {
              this.manualIp = value;
            });
 
          // WebSocket端口
          TextInput({ placeholder: 'WebSocket端口', text: this.manualWsPort })
            .width('85%')
            .height(45)
            .margin({ bottom: 8 })
            .onChange((value: string) => {
              this.manualWsPort = value;
            });
 
          // HTTP端口
          TextInput({ placeholder: 'HTTP端口', text: this.manualHttpPort })
            .width('85%')
            .height(45)
            .margin({ bottom: 8 })
            .onChange((value: string) => {
              this.manualHttpPort = value;
            });
 
          // Token输入
          TextInput({ placeholder: '配对Token (从/qrcode页面获取)', text: this.manualToken })
            .width('85%')
            .height(45)
            .margin({ bottom: 15 })
            .onChange((value: string) => {
              this.manualToken = value;
            });
 
          // 连接按钮
          Button('连接')
            .width('85%')
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
          if (this.showManualInput) {
            this.statusText = '请输入配对信息';
          } else {
            this.statusText = '准备扫码';
          }
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
              this.statusText = this.showManualInput ? '请输入配对信息' : '准备扫码';
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
    
    // 模拟扫码 - 实际需要Scan Kit集成
    const testConfig: ConnectionConfig = {
      token: 'test-token-' + Date.now().toString(),
      expire: Date.now() + 5 * 60 * 1000,
      ip: '100.117.37.34',
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
    // 验证输入
    if (this.manualIp.trim().length === 0) {
      this.showError = true;
      this.errorMsg = '请输入服务器IP地址';
      return;
    }
 
    if (this.manualToken.trim().length === 0) {
      this.showError = true;
      this.errorMsg = '请输入配对Token（从电脑端/qrcode页面获取）';
      return;
    }
 
    const wsPort: number = parseInt(this.manualWsPort) || 8080;
    const httpPort: number = parseInt(this.manualHttpPort) || 8081;
 
    if (isNaN(wsPort) || wsPort <= 0 || wsPort > 65535) {
      this.showError = true;
      this.errorMsg = 'WebSocket端口无效，请输入1-65535之间的数字';
      return;
    }
 
    if (isNaN(httpPort) || httpPort <= 0 || httpPort > 65535) {
      this.showError = true;
      this.errorMsg = 'HTTP端口无效，请输入1-65535之间的数字';
      return;
    }
 
    // 构造配置
    const config: ConnectionConfig = {
      token: this.manualToken.trim(),
      expire: Date.now() + 5 * 60 * 1000, // 5分钟有效期
      ip: this.manualIp.trim(),
      wsPort: wsPort,
      httpPort: httpPort
    };
 
    this.statusText = '正在连接服务器...';
    this.doConnect(config);
  }
}