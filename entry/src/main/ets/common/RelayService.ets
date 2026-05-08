import { webSocket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { RelayConfig, AgentInfo } from './Types';

const DOMAIN = 0xFF00;
const TAG = 'RelayService';

type MessageCallback = (msg: ESObject) => void;
type StatusCallback = (connected: boolean) => void;
type AgentListCallback = (agents: AgentInfo[]) => void;

export class RelayService {
  private ws: webSocket.WebSocket | null = null;
  private config: RelayConfig | null = null;
  private isConnected: boolean = false;
  private clientId: string = '';
  private messageCallbacks: MessageCallback[] = [];
  private statusCallbacks: StatusCallback[] = [];
  private agentListCallbacks: AgentListCallback[] = [];
  private heartbeatTimer: number = 0;

  async connect(config: RelayConfig): Promise<boolean> {
    this.config = config;
    hilog.info(DOMAIN, TAG, 'Connecting to relay: %{public}s', config.serverUrl);

    try {
      this.ws = webSocket.createWebSocket();
      
      this.ws.on('open', () => {
        hilog.info(DOMAIN, TAG, 'WebSocket opened');
        this.isConnected = true;
        this.notifyStatusChange(true);
        this.sendClientConnect();
        this.startHeartbeat();
      });

      this.ws.on('message', (err: Error, value: string | ArrayBuffer) => {
        if (err) {
          hilog.error(DOMAIN, TAG, 'Message error: %{public}s', err.message);
          return;
        }
        const data: string = typeof value === 'string' ? value : this.arrayBufferToString(value as ArrayBuffer);
        this.handleMessage(data);
      });

      this.ws.on('close', (err: Error, value: webSocket.CloseResult) => {
        hilog.info(DOMAIN, TAG, 'WebSocket closed');
        this.isConnected = false;
        this.stopHeartbeat();
        this.notifyStatusChange(false);
      });

      this.ws.on('error', (err: Error) => {
        hilog.error(DOMAIN, TAG, 'WebSocket error: %{public}s', err.message);
        this.isConnected = false;
        this.stopHeartbeat();
        this.notifyStatusChange(false);
      });

      await this.ws.connect(config.serverUrl, {
        header: {
          'Content-Type': 'application/json'
        }
      });

      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Connect failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  private sendClientConnect(): void {
    if (!this.ws || !this.config) return;
    
    const msg: ESObject = {
      type: 'client_connect',
      agentId: this.config.agentId
    };
    this.send(msg);
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this.ws && this.isConnected) {
        this.send({ type: 'ping' });
      }
    }, 30000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer > 0) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = 0;
    }
  }

  private handleMessage(data: string): void {
    try {
      const msg: ESObject = JSON.parse(data) as ESObject;
      const msgType: string = (msg['type'] as string) || '';

      if (msgType !== 'pong') {
        hilog.info(DOMAIN, TAG, 'Received: %{public}s', msgType);
      }

      if (msgType === 'client_connected') {
        this.clientId = (msg['clientId'] as string) || '';
        const success: boolean = (msg['success'] as boolean) || false;
        if (!success) {
          const errMsg: string = (msg['message'] as string) || 'Connection failed';
          this.notifyMessage({ type: 'error', message: errMsg });
        } else {
          this.notifyMessage({ type: 'task_status', status: 'ready', message: '已连接 Agent' });
        }
      } else if (msgType === 'agent_list') {
        const agents: AgentInfo[] = this.parseAgentList(msg['agents'] as ESObject[]);
        for (let i = 0; i < this.agentListCallbacks.length; i++) {
          this.agentListCallbacks[i](agents);
        }
      } else if (msgType === 'error') {
        this.notifyMessage(msg);
      } else if (msgType === 'exec_ack') {
        this.notifyMessage(msg);
      } else if (msgType === 'ai_response' || msgType === 'task_status' || msgType === 'permission_request') {
        this.notifyMessage(msg);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Parse failed: %{public}s', JSON.stringify(e));
    }
  }

  private parseAgentList(agentsData: ESObject[]): AgentInfo[] {
    const agents: AgentInfo[] = [];
    if (!agentsData) return agents;
    
    for (let i = 0; i < agentsData.length; i++) {
      const a: ESObject = agentsData[i];
      agents.push({
        agentId: (a['agentId'] as string) || '',
        name: (a['name'] as string) || 'Unknown',
        connectedAt: (a['connectedAt'] as number) || 0
      });
    }
    
    return agents;
  }

  async sendMessage(content: string): Promise<boolean> {
    if (!this.ws || !this.isConnected || this.clientId.length === 0) {
      hilog.warn(DOMAIN, TAG, 'Not connected');
      return false;
    }

    const requestId: string = Date.now().toString();
    const msg: ESObject = {
      type: 'exec',
      content: content,
      requestId: requestId
    };

    this.send(msg);
    return true;
  }

  async respondToPermission(permissionId: string, answer: string): Promise<boolean> {
    if (!this.ws || !this.isConnected) {
      return false;
    }

    const msg: ESObject = {
      type: 'permission_response',
      id: permissionId,
      answer: answer
    };

    this.send(msg);
    return true;
  }

  private send(msg: ESObject): void {
    if (!this.ws) return;
    
    const data: string = JSON.stringify(msg);
    this.ws.send(data);
  }

  private arrayBufferToString(buffer: ArrayBuffer): string {
    const bytes: Uint8Array = new Uint8Array(buffer);
    let result: string = '';
    for (let i = 0; i < bytes.length; i++) {
      result += String.fromCharCode(bytes[i]);
    }
    return result;
  }

  onMessage(callback: MessageCallback): void {
    this.messageCallbacks.push(callback);
  }

  onStatusChange(callback: StatusCallback): void {
    this.statusCallbacks.push(callback);
  }

  onAgentList(callback: AgentListCallback): void {
    this.agentListCallbacks.push(callback);
  }

  private notifyMessage(msg: ESObject): void {
    for (let i = 0; i < this.messageCallbacks.length; i++) {
      this.messageCallbacks[i](msg);
    }
  }

  private notifyStatusChange(connected: boolean): void {
    for (let i = 0; i < this.statusCallbacks.length; i++) {
      this.statusCallbacks[i](connected);
    }
  }

  close(): void {
    this.stopHeartbeat();
    if (this.ws) {
      this.ws.close();
      this.ws.off('open');
      this.ws.off('message');
      this.ws.off('close');
      this.ws.off('error');
      this.ws = null;
    }
    this.isConnected = false;
    this.clientId = '';
    this.notifyStatusChange(false);
  }

  getConnected(): boolean {
    return this.isConnected;
  }

  getClientId(): string {
    return this.clientId;
  }
}

export const relayService = new RelayService();