/**
 * WebSocket 通信服务 (ArkTS 兼容版本)
 */
 
import { webSocket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import type { ConnectionConfig } from './Types';
 
const DOMAIN = 0xFF00;
const TAG = 'WebSocketService';
 
type MessageCallback = (msg: ESObject) => void;
type StatusCallback = (connected: boolean) => void;
 
export class WebSocketService {
  private ws: webSocket.WebSocket | null = null;
  private url: string = '';
  private isConnected: boolean = false;
  private isAuthenticated: boolean = false;
  private messageCallbacks: MessageCallback[] = [];
  private statusCallbacks: StatusCallback[] = [];
  private heartbeatTimer: number = -1;
 
  connect(config: ConnectionConfig): Promise<boolean> {
    this.url = `ws://${config.ip}:${config.wsPort}`;
    hilog.info(DOMAIN, TAG, `Connecting to ${this.url}`);
    
    return new Promise<boolean>((resolve, reject) => {
      try {
        this.ws = webSocket.createWebSocket();
        
        this.ws.on('open', (err: Error | null, value: ESObject) => {
          if (err) {
            hilog.error(DOMAIN, TAG, `Connection failed: ${err.message}`);
            resolve(false);
            return;
          }
          
          hilog.info(DOMAIN, TAG, 'Connection established');
          this.isConnected = true;
          this.notifyStatusChange(true);
          
          // 发送认证消息
          this.sendAuth(config.token);
          resolve(true);
        });
        
        this.ws.on('message', (err: Error | null, value: string | ArrayBuffer) => {
          if (err) {
            hilog.error(DOMAIN, TAG, `Message error: ${err.message}`);
            return;
          }
          
          // ArkTS: value is string | ArrayBuffer, 需要类型判断
          let messageStr: string = '';
          if (typeof value === 'string') {
            messageStr = value as string;
          } else if (value instanceof ArrayBuffer) {
            const decoder = new util.TextDecoder('utf-8');
            messageStr = decoder.decodeToString(new Uint8Array(value as ArrayBuffer));
          }
          
          if (messageStr.length > 0) {
            this.handleMessage(messageStr);
          }
        });
        
        this.ws.on('close', (err: Error | null, value: ESObject) => {
          hilog.info(DOMAIN, TAG, `Connection closed`);
          this.isConnected = false;
          this.isAuthenticated = false;
          this.notifyStatusChange(false);
          this.stopHeartbeat();
        });
        
        this.ws.on('error', (err: Error) => {
          hilog.error(DOMAIN, TAG, `WebSocket error: ${err.message}`);
          this.isConnected = false;
          this.notifyStatusChange(false);
        });
        
        this.ws.connect(this.url, (err: Error) => {
          if (err) {
            hilog.error(DOMAIN, TAG, `Connect error: ${err.message}`);
            reject(err);
          }
        });
        
      } catch (e) {
        hilog.error(DOMAIN, TAG, `Exception: ${e}`);
        reject(e);
      }
    });
  }
  
  private sendAuth(token: string): void {
    const authMsg: ESObject = {
      type: 'auth',
      token: token
    };
    this.send(authMsg);
  }
  
  private handleMessage(messageStr: string): void {
    try {
      const msg: ESObject = JSON.parse(messageStr);
      hilog.debug(DOMAIN, TAG, `Received: ${msg['type']}`);
      
      // 处理认证结果
      if (msg['type'] === 'auth_result') {
        const success: boolean = msg['success'] as boolean;
        this.isAuthenticated = success;
        hilog.info(DOMAIN, TAG, `Auth result: ${success}`);
        
        if (success) {
          this.startHeartbeat();
        }
      }
      
      // 通知所有回调
      for (let i = 0; i < this.messageCallbacks.length; i++) {
        const callback = this.messageCallbacks[i];
        callback(msg);
      }
      
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Parse error: ${e}`);
    }
  }
  
  send(msg: ESObject): void {
    if (!this.ws || !this.isConnected) {
      hilog.warn(DOMAIN, TAG, 'Not connected');
      return;
    }
    
    const msgStr: string = JSON.stringify(msg);
    this.ws.send(msgStr, (err: Error) => {
      if (err) {
        hilog.error(DOMAIN, TAG, `Send error: ${err.message}`);
      }
    });
  }
  
  execCommand(content: string): void {
    this.send({
      type: 'exec',
      content: content
    });
  }
  
  replyPermission(id: string, answer: string): void {
    this.send({
      type: 'permission_response',
      id: id,
      answer: answer
    });
  }
  
  requestFileList(): void {
    this.send({
      type: 'list_files'
    });
  }
  
  private startHeartbeat(): void {
    this.heartbeatTimer = setInterval(() => {
      if (this.isConnected) {
        this.send({ type: 'ping' });
      }
    }, 30000);
  }
  
  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }
  
  onMessage(callback: MessageCallback): void {
    this.messageCallbacks.push(callback);
  }
  
  onStatusChange(callback: StatusCallback): void {
    this.statusCallbacks.push(callback);
  }
  
  private notifyStatusChange(connected: boolean): void {
    for (let i = 0; i < this.statusCallbacks.length; i++) {
      const callback = this.statusCallbacks[i];
      callback(connected);
    }
  }
  
  close(): void {
    if (this.ws) {
      this.stopHeartbeat();
      this.ws.close((err: Error) => {
        if (err) {
          hilog.error(DOMAIN, TAG, `Close error: ${err.message}`);
        }
        hilog.info(DOMAIN, TAG, 'Connection closed');
      });
      this.ws = null;
      this.isConnected = false;
      this.isAuthenticated = false;
    }
  }
  
  getConnected(): boolean {
    return this.isConnected;
  }
  
  getAuthenticated(): boolean {
    return this.isAuthenticated;
  }
}
 
export const wsService = new WebSocketService();