import { hilog } from '@kit.PerformanceAnalysisKit';
import { openCodeService } from './OpenCodeService';
import { relayService } from './RelayService';
import type { ServerConfig, RelayConfig } from './Types';

const DOMAIN = 0xFF00;
const TAG = 'ServiceManager';
const MAX_PENDING_MESSAGES = 100;

export type ConnectionMode = 'direct' | 'relay';

type MessageCallback = (msg: ESObject) => void;
type StatusCallback = (connected: boolean) => void;

export class ServiceManager {
  private mode: ConnectionMode = 'direct';
  private isConnected: boolean = false;
  private messageCallbacks: MessageCallback[] = [];
  private statusCallbacks: StatusCallback[] = [];
  private pendingMessages: ESObject[] = [];
  private isPageVisible: boolean = true;

  setMode(mode: ConnectionMode): void {
    this.mode = mode;
    hilog.info(DOMAIN, TAG, 'Mode set to: %{public}s', mode);
  }

  getMode(): ConnectionMode {
    return this.mode;
  }

  setPageVisible(visible: boolean): void {
    this.isPageVisible = visible;
    hilog.info(DOMAIN, TAG, 'Page visible: %{public}s', visible.toString());
    if (visible && this.pendingMessages.length > 0) {
      this.flushPendingMessages();
    }
  }

  private flushPendingMessages(): void {
    hilog.info(DOMAIN, TAG, 'Flushing %{public}d pending messages', this.pendingMessages.length);
    const messages: ESObject[] = this.pendingMessages.slice();
    this.pendingMessages = [];
    for (let i = 0; i < messages.length; i++) {
      this.notifyMessageInternal(messages[i]);
    }
  }

  getPendingMessages(): ESObject[] {
    const messages: ESObject[] = this.pendingMessages.slice();
    this.pendingMessages = [];
    return messages;
  }

  async connectDirect(server: ServerConfig): Promise<boolean> {
    this.mode = 'direct';
    const success: boolean = await openCodeService.connect(server);
    if (success) {
      this.isConnected = true;
      openCodeService.onMessage((msg: ESObject) => {
        this.notifyMessage(msg);
      });
      openCodeService.onStatusChange((connected: boolean) => {
        this.isConnected = connected;
        this.notifyStatusChange(connected);
      });
    }
    return success;
  }

  async connectRelay(config: RelayConfig): Promise<boolean> {
    this.mode = 'relay';
    const success: boolean = await relayService.connect(config);
    if (success) {
      this.isConnected = true;
      relayService.onMessage((msg: ESObject) => {
        this.notifyMessage(msg);
      });
      relayService.onStatusChange((connected: boolean) => {
        this.isConnected = connected;
        this.notifyStatusChange(connected);
      });
    }
    return success;
  }

  async sendMessage(content: string): Promise<boolean> {
    if (!this.isConnected) {
      hilog.warn(DOMAIN, TAG, 'Not connected');
      return false;
    }

    if (this.mode === 'direct') {
      return openCodeService.sendMessage(content);
    } else {
      return relayService.sendMessage(content);
    }
  }

  async createNewSession(): Promise<string> {
    if (this.mode === 'direct') {
      return openCodeService.createNewSession();
    }
    return '';
  }

  async respondToPermission(permissionId: string, answer: string): Promise<boolean> {
    if (this.mode === 'direct') {
      return openCodeService.respondToPermission(permissionId, answer);
    } else {
      return relayService.respondToPermission(permissionId, answer);
    }
  }

  getConnected(): boolean {
    return this.isConnected;
  }

  getCurrentSessionId(): string {
    if (this.mode === 'direct') {
      return openCodeService.getCurrentSessionId();
    }
    return '';
  }

  getCurrentServer(): ServerConfig | null {
    if (this.mode === 'direct') {
      return openCodeService.getCurrentServer();
    }
    return null;
  }

  onMessage(callback: MessageCallback): void {
    this.messageCallbacks.push(callback);
  }

  onStatusChange(callback: StatusCallback): void {
    this.statusCallbacks.push(callback);
  }

  private notifyMessage(msg: ESObject): void {
    if (!this.isPageVisible) {
      if (this.pendingMessages.length >= MAX_PENDING_MESSAGES) {
        this.pendingMessages.shift();
      }
      this.pendingMessages.push(msg);
      hilog.info(DOMAIN, TAG, 'Message cached (page hidden): %{public}s', (msg['type'] as string) || 'unknown');
    } else {
      this.notifyMessageInternal(msg);
    }
  }

  private notifyMessageInternal(msg: ESObject): void {
    for (let i = 0; i < this.messageCallbacks.length; i++) {
      this.messageCallbacks[i](msg);
    }
  }

  private notifyStatusChange(connected: boolean): void {
    for (let i = 0; i < this.statusCallbacks.length; i++) {
      this.statusCallbacks[i](connected);
    }
  }

  disconnect(): void {
    if (this.mode === 'direct') {
      openCodeService.close();
    } else {
      relayService.close();
    }
    this.isConnected = false;
  }
}

export const serviceManager = new ServiceManager();