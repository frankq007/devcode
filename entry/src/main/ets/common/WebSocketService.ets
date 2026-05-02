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
    hilog.info(DOMAIN, TAG, '=== connect() called ===');
    hilog.info(DOMAIN, TAG, 'URL: %{public}s', this.url);
    hilog.info(DOMAIN, TAG, 'Token: %{public}s', config.token);

    return new Promise<boolean>((resolve, reject) => {
      try {
        hilog.info(DOMAIN, TAG, 'Creating WebSocket...');
        this.ws = webSocket.createWebSocket();

        this.ws.on('open', (err: Error | null, value: ESObject) => {
          if (err) {
            hilog.error(DOMAIN, TAG, '>>> OPEN failed: %{public}s', err.message);
            resolve(false);
            return;
          }

          hilog.info(DOMAIN, TAG, '>>> OPEN success - Connection established');
          this.isConnected = true;
          this.notifyStatusChange(true);

          hilog.info(DOMAIN, TAG, '>>> Sending auth message...');
          this.sendAuth(config.token);
          resolve(true);
        });

        this.ws.on('message', (err: Error | null, value: string | ArrayBuffer) => {
          if (err) {
            hilog.error(DOMAIN, TAG, '>>> MESSAGE error: %{public}s', err.message);
            return;
          }

          let messageStr: string = '';
          if (typeof value === 'string') {
            messageStr = value as string;
          } else if (value instanceof ArrayBuffer) {
            const decoder = new util.TextDecoder('utf-8');
            messageStr = decoder.decodeToString(new Uint8Array(value as ArrayBuffer));
          }

          if (messageStr.length > 0) {
            hilog.info(DOMAIN, TAG, '>>> MESSAGE received (len=%{public}d): %{public}s', messageStr.length, messageStr.substring(0, 100));
            this.handleMessage(messageStr);
          }
        });

        this.ws.on('close', (err: Error | null, value: ESObject) => {
          hilog.info(DOMAIN, TAG, '>>> CLOSE: Connection closed');
          this.isConnected = false;
          this.isAuthenticated = false;
          this.notifyStatusChange(false);
          this.stopHeartbeat();
        });

        this.ws.on('error', (err: Error) => {
          hilog.error(DOMAIN, TAG, '>>> ERROR: %{public}s', err.message);
          this.isConnected = false;
          this.notifyStatusChange(false);
        });

        hilog.info(DOMAIN, TAG, '>>> Calling ws.connect...');
        this.ws.connect(this.url, (err: Error) => {
          if (err) {
            hilog.error(DOMAIN, TAG, '>>> connect() callback error: %{public}s', err.message);
            reject(err);
          } else {
            hilog.info(DOMAIN, TAG, '>>> connect() callback success');
          }
        });

      } catch (e) {
        hilog.error(DOMAIN, TAG, '>>> Exception: %{public}s', e);
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
      const msgType: string = msg['type'] as string || 'unknown';
      hilog.info(DOMAIN, TAG, '>>> handleMessage parsed: type=%{public}s', msgType);

      if (msgType === 'auth_result') {
        const success: boolean = msg['success'] as boolean;
        this.isAuthenticated = success;
        hilog.info(DOMAIN, TAG, '>>> Auth result: %{public}s', success ? 'SUCCESS' : 'FAILED');

        if (success) {
          hilog.info(DOMAIN, TAG, '>>> Starting heartbeat...');
          this.startHeartbeat();
        }
      }

      hilog.info(DOMAIN, TAG, '>>> Notifying %{public}d callbacks', this.messageCallbacks.length);
      for (let i = 0; i < this.messageCallbacks.length; i++) {
        const callback = this.messageCallbacks[i];
        callback(msg);
      }

    } catch (e) {
      hilog.error(DOMAIN, TAG, '>>> Parse error: %{public}s', e);
    }
  }

  send(msg: ESObject): void {
    hilog.info(DOMAIN, TAG, '>>> send() called, type=%{public}s', msg['type'] as string);
    if (!this.ws || !this.isConnected) {
      hilog.warn(DOMAIN, TAG, '>>> send() FAILED: Not connected');
      return;
    }

    const msgStr: string = JSON.stringify(msg);
    hilog.info(DOMAIN, TAG, '>>> Sending message (len=%{public}d)', msgStr.length);
    this.ws.send(msgStr, (err: Error) => {
      if (err) {
        hilog.error(DOMAIN, TAG, '>>> Send error: %{public}s', err.message);
      } else {
        hilog.info(DOMAIN, TAG, '>>> Send success');
      }
    });
  }

  execCommand(content: string): void {
    const msg: ESObject = {
      type: 'exec',
      content: content
    };
    this.send(msg);
  }

  replyPermission(id: string, answer: string): void {
    const msg: ESObject = {
      type: 'permission_response',
      id: id,
      answer: answer
    };
    this.send(msg);
  }

  requestFileList(): void {
    const msg: ESObject = {
      type: 'list_files'
    };
    this.send(msg);
  }

  private startHeartbeat(): void {
    this.heartbeatTimer = setInterval(() => {
      if (this.isConnected) {
        const pingMsg: ESObject = { type: 'ping' };
        this.send(pingMsg);
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
          hilog.error(DOMAIN, TAG, 'Close error: %{public}s', err.message);
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