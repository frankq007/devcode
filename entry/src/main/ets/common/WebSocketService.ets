/**
 * WebSocket 通信服务
 * 
 * 功能：
 * - 建立 WebSocket 连接
 * - 发送/接收消息
 * - 处理认证
 * - 管理连接状态
 */

import { webSocket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type {
  WSMessage,
  AuthMessage,
  AuthResultMessage,
  TaskStatusMessage,
  PermissionRequestMessage,
  FileAddedMessage,
  FileListMessage,
  ConnectionConfig
} from './Types';

const DOMAIN = 0xFF00;
const TAG = 'WebSocketService';

// 消息回调类型
type MessageCallback = (msg: WSMessage) => void;
type StatusCallback = (connected: boolean) => void;

export class WebSocketService {
  private ws: webSocket.WebSocket | null = null;
  private url: string = '';
  private isConnected: boolean = false;
  private isAuthenticated: boolean = false;
  private messageCallbacks: MessageCallback[] = [];
  private statusCallbacks: StatusCallback[] = [];
  private heartbeatTimer: number = -1;

  /**
   * 连接服务器
   */
  connect(config: ConnectionConfig): Promise<boolean> {
    this.url = `ws://${config.ip}:${config.wsPort}`;

    hilog.info(DOMAIN, TAG, `Connecting to ${this.url}`);

    return new Promise<boolean>((resolve, reject) => {
      try {
        this.ws = webSocket.createWebSocket();

        this.ws.on('open', (err, value) => {
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

        this.ws.on('message', (err, value) => {
          if (err) {
            hilog.error(DOMAIN, TAG, `Message error: ${err.message}`);
            return;
          }

          const messageStr = value.message || value.data;
          if (messageStr) {
            this.handleMessage(messageStr.toString());
          }
        });

        this.ws.on('close', (err, value) => {
          hilog.info(DOMAIN, TAG, `Connection closed: ${value.code}, ${value.reason}`);
          this.isConnected = false;
          this.isAuthenticated = false;
          this.notifyStatusChange(false);
          this.stopHeartbeat();
        });

        this.ws.on('error', (err) => {
          hilog.error(DOMAIN, TAG, `WebSocket error: ${err.message}`);
          this.isConnected = false;
          this.notifyStatusChange(false);
        });

        this.ws.connect(this.url, (err, value) => {
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

  /**
   * 发送认证消息
   */
  private sendAuth(token: string): void {
    const authMsg: AuthMessage = {
      type: 'auth',
      token: token
    };
    this.send(authMsg);
  }

  /**
   * 处理接收的消息
   */
  private handleMessage(messageStr: string): void {
    try {
      const msg: WSMessage = JSON.parse(messageStr) as WSMessage;
      hilog.debug(DOMAIN, TAG, `Received: ${msg.type}`);

      // 处理认证结果
      if (msg.type === 'auth_result') {
        const authResult = msg as AuthResultMessage;
        this.isAuthenticated = authResult.success;
        hilog.info(DOMAIN, TAG, `Auth result: ${authResult.success}`);
        
        if (authResult.success) {
          this.startHeartbeat();
        }
      }

      // 通知所有回调
      this.messageCallbacks.forEach(cb => cb(msg));

    } catch (e) {
      hilog.error(DOMAIN, TAG, `Parse error: ${e}`);
    }
  }

  /**
   * 发送消息
   */
  send(msg: ESObject): void {
    if (!this.ws || !this.isConnected) {
      hilog.warn(DOMAIN, TAG, 'Not connected');
      return;
    }

    const msgStr = JSON.stringify(msg);
    this.ws.send(msgStr, (err, value) => {
      if (err) {
        hilog.error(DOMAIN, TAG, `Send error: ${err.message}`);
      }
    });
  }

  /**
   * 执行指令
   */
  execCommand(content: string): void {
    this.send({
      type: 'exec',
      content: content
    });
  }

  /**
   * 回复权限请求
   */
  replyPermission(id: string, answer: string): void {
    this.send({
      type: 'permission_response',
      id: id,
      answer: answer
    });
  }

  /**
   * 请求文件列表
   */
  requestFileList(): void {
    this.send({
      type: 'list_files'
    });
  }

  /**
   * 开始心跳
   */
  private startHeartbeat(): void {
    this.heartbeatTimer = setInterval(() => {
      if (this.isConnected) {
        this.send({ type: 'ping' });
      }
    }, 30000);
  }

  /**
   * 停止心跳
   */
  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  /**
   * 注册消息回调
   */
  onMessage(callback: MessageCallback): void {
    this.messageCallbacks.push(callback);
  }

  /**
   * 注册状态回调
   */
  onStatusChange(callback: StatusCallback): void {
    this.statusCallbacks.push(callback);
  }

  /**
   * 通知状态变化
   */
  private notifyStatusChange(connected: boolean): void {
    this.statusCallbacks.forEach(cb => cb(connected));
  }

  /**
   * 关闭连接
   */
  close(): void {
    if (this.ws) {
      this.stopHeartbeat();
      this.ws.close((err, value) => {
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

  /**
   * 获取连接状态
   */
  getConnected(): boolean {
    return this.isConnected;
  }

  /**
   * 获取认证状态
   */
  getAuthenticated(): boolean {
    return this.isAuthenticated;
  }
}

// 全局 WebSocket 服务实例
export const wsService = new WebSocketService();