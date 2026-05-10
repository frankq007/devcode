/**
 * OpenCode Serve API 客户端服务 (ArkTS 严格类型版本)
 */

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { ServerConfig, SessionInfo } from './Types';

const DOMAIN = 0xFF00;
const TAG = 'OpenCodeService';

interface HealthResponse {
  healthy: boolean;
}

interface EmptyResponse {}

interface SessionResponse {
  id: string;
  title?: string;
  time?: ESObject;
}

interface MessagePart {
  type: string;
  text?: string;
}

interface ModelConfig {
  providerID: string;
  modelID: string;
}

interface PromptRequest {
  parts: MessagePart[];
  model: ModelConfig;
}

interface PermissionRequest {
  answer: string;
}

interface SessionCreateRequest {
  title: string;
}

type MessageCallback = (msg: ESObject) => void;
type StatusCallback = (connected: boolean) => void;

export class OpenCodeService {
  private currentServer: ServerConfig | null = null;
  private currentSessionId: string = '';
  private isConnected: boolean = false;
  private messageCallbacks: MessageCallback[] = [];
  private statusCallbacks: StatusCallback[] = [];
  private eventRequest: http.HttpRequest | null = null;
  private lastStatus: string = '';
  private lastSentMessageId: string = '';
  private lastSentResponseId: string = '';

  async connect(server: ServerConfig): Promise<boolean> {
    this.currentServer = server;
    hilog.info(DOMAIN, TAG, 'Connecting to %{public}s:%{public}d', server.ip, server.port);

    const healthy: boolean = await this.checkHealth();
    if (healthy) {
      this.isConnected = true;
      this.notifyStatusChange(true);
      const sessionId: string = await this.getOrCreateSession();
      if (sessionId.length > 0) {
        this.currentSessionId = sessionId;
        this.startEventListener();
        return true;
      }
    }
    this.isConnected = false;
    this.notifyStatusChange(false);
    return false;
  }

  private getAuthHeader(): string {
    if (!this.currentServer) return '';
    const credentials: string = `${this.currentServer.username}:${this.currentServer.password}`;
    return `Basic ${this.base64Encode(credentials)}`;
  }

  private base64Encode(str: string): string {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result: string = '';
    
    for (let i = 0; i < str.length; i += 3) {
      const b1: number = str.charCodeAt(i);
      const b2: number = i + 1 < str.length ? str.charCodeAt(i + 1) : 0;
      const b3: number = i + 2 < str.length ? str.charCodeAt(i + 2) : 0;
      
      const triplet: number = (b1 << 16) | (b2 << 8) | b3;
      
      result += chars.charAt((triplet >> 18) & 0x3F);
      result += chars.charAt((triplet >> 12) & 0x3F);
      result += i + 1 >= str.length ? '=' : chars.charAt((triplet >> 6) & 0x3F);
      result += i + 2 >= str.length ? '=' : chars.charAt(triplet & 0x3F);
    }
    
    return result;
  }

  private async checkHealth(): Promise<boolean> {
    if (!this.currentServer) return false;
    
    const httpRequest: http.HttpRequest = http.createHttp();
    const url: string = `http://${this.currentServer.ip}:${this.currentServer.port}/global/health`;
    
    try {
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': this.getAuthHeader()
        }
      });
      
      httpRequest.destroy();
      
      if (response.responseCode === 200) {
        const resultStr: string = response.result as string;
        const result: HealthResponse = JSON.parse(resultStr) as HealthResponse;
        return result.healthy;
      }
      return false;
    } catch (e) {
      httpRequest.destroy();
      hilog.error(DOMAIN, TAG, 'Health check failed');
      return false;
    }
  }

  private async getOrCreateSession(): Promise<string> {
    if (!this.currentServer) return '';
    
    try {
      const sessions: SessionResponse[] = await this.callAPIArray('GET', '/session');
      
      if (sessions.length > 0) {
        return sessions[0].id;
      }
      
      const createReq: SessionCreateRequest = { title: 'DevCode Remote' };
      const newSession: SessionResponse = await this.callAPIObject('POST', '/session', createReq) as SessionResponse;
      return newSession.id;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Session creation failed');
      return '';
    }
  }

  private async callAPIArray(method: string, path: string): Promise<SessionResponse[]> {
    const result: Object = await this.callAPI(method, path);
    return result as SessionResponse[];
  }

  private async callAPIObject(method: string, path: string, body?: Object): Promise<Object> {
    return await this.callAPI(method, path, body);
  }

  private async callAPI(method: string, path: string, body?: Object): Promise<Object> {
    if (!this.currentServer) {
      throw new Error('No server configured');
    }
    
    const httpRequest: http.HttpRequest = http.createHttp();
    const url: string = `http://${this.currentServer.ip}:${this.currentServer.port}${path}`;
    
    const headers: Record<string, string> = {
      'Authorization': this.getAuthHeader(),
      'Content-Type': 'application/json'
    };
    
    const options: http.HttpRequestOptions = {
      method: method === 'GET' ? http.RequestMethod.GET : 
              method === 'POST' ? http.RequestMethod.POST : 
              method === 'DELETE' ? http.RequestMethod.DELETE : http.RequestMethod.GET,
      header: headers
    };
    
    if (body) {
      options.extraData = JSON.stringify(body);
    }
    
    try {
      const response: http.HttpResponse = await httpRequest.request(url, options);
      httpRequest.destroy();
      
      if (response.responseCode >= 200 && response.responseCode < 300) {
        const resultStr: string = response.result as string;
        if (resultStr.length > 0) {
          return JSON.parse(resultStr);
        }
        const empty: EmptyResponse = {};
        return empty;
      }
      throw new Error(`API error: ${response.responseCode}`);
    } catch (e) {
      httpRequest.destroy();
      throw new Error('API call failed');
    }
  }

  async sendMessage(content: string): Promise<boolean> {
    if (!this.currentSessionId || !this.currentServer) {
      hilog.error(DOMAIN, TAG, 'sendMessage: No session or server');
      return false;
    }
    
    hilog.info(DOMAIN, TAG, 'Sending message to session %{public}s: %{public}s', this.currentSessionId, content);
    
    try {
      const part: MessagePart = { type: 'text', text: content };
      const model: ModelConfig = { providerID: 'alibaba-cn', modelID: 'glm-5' };
      const promptReq: PromptRequest = { parts: [part], model: model };
      await this.callAPIObject('POST', `/session/${this.currentSessionId}/prompt_async`, promptReq);
      hilog.info(DOMAIN, TAG, 'Message sent successfully');
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Send message failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  async createNewSession(): Promise<string> {
    if (!this.currentServer) return '';
    
    try {
      const createReq: SessionCreateRequest = { title: 'DevCode Remote' };
      const newSession: SessionResponse = await this.callAPIObject('POST', '/session', createReq) as SessionResponse;
      this.currentSessionId = newSession.id;
      return this.currentSessionId;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Create session failed');
      return '';
    }
  }

  async getSessionList(): Promise<SessionInfo[]> {
    if (!this.currentServer) return [];
    
    try {
      const sessions: SessionResponse[] = await this.callAPIArray('GET', '/session');
      const result: SessionInfo[] = [];
      
      for (let i = 0; i < sessions.length; i++) {
        const s: SessionResponse = sessions[i];
        result.push({
          id: s.id,
          title: s.title || 'Untitled',
          time: s.time as ESObject
        });
      }
      
      return result;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Get sessions failed');
      return [];
    }
  }

  async respondToPermission(permissionId: string, answer: string): Promise<boolean> {
    if (!this.currentSessionId || !this.currentServer) return false;
    
    try {
      const permReq: PermissionRequest = { answer: answer };
      await this.callAPIObject('POST', `/session/${this.currentSessionId}/permission/${permissionId}`, permReq);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Permission response failed');
      return false;
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
      this.statusCallbacks[i](connected);
    }
  }

  private startEventListener(): void {
    if (!this.currentServer || this.eventRequest) {
      hilog.warn(DOMAIN, TAG, 'startEventListener: No server or already listening');
      return;
    }

    hilog.info(DOMAIN, TAG, 'Starting SSE connection to %{public}s:%{public}d',
      this.currentServer.ip, this.currentServer.port);

    this.eventRequest = http.createHttp();
    const url: string = `http://${this.currentServer.ip}:${this.currentServer.port}/event`;
    hilog.info(DOMAIN, TAG, 'SSE URL: %{public}s', url);

    this.eventRequest.on('dataReceive', (data: ArrayBuffer) => {
      const str: string = this.arrayBufferToString(data);
      this.handleSseData(str);
    });

    this.eventRequest.on('dataEnd', () => {
      hilog.info(DOMAIN, TAG, 'SSE connection closed');
      this.eventRequest = null;
      // 尝试重连
      setTimeout(() => {
        if (this.currentServer && this.isConnected) {
          hilog.info(DOMAIN, TAG, 'Attempting SSE reconnect');
          this.startEventListener();
        }
      }, 5000);
    });

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'Authorization': this.getAuthHeader(),
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache'
      },
      connectTimeout: 60000,
      readTimeout: 600000
    };

    this.eventRequest.requestInStream(url, options)
      .then((code: number) => {
        hilog.info(DOMAIN, TAG, 'SSE connected, code: %{public}d', code);
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'SSE failed: %{public}s', err.message);
        this.eventRequest = null;
      });
  }

  private arrayBufferToString(buffer: ArrayBuffer): string {
    const bytes: Uint8Array = new Uint8Array(buffer);
    let result: string = '';
    for (let i = 0; i < bytes.length; i++) {
      result += String.fromCharCode(bytes[i]);
    }
    return result;
  }

  private handleSseData(data: string): void {
    hilog.debug(DOMAIN, TAG, 'SSE data received: %{public}s', data.substring(0, 300));
    const lines: string[] = data.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.startsWith('data:')) {
        const jsonStr: string = line.substring(5).trim();
        if (jsonStr.length === 0) {
          continue;
        }
        try {
          const event: ESObject = JSON.parse(jsonStr) as ESObject;
          this.handleOpenCodeEvent(event);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'Parse event failed: %{public}s', jsonStr.substring(0, 100));
        }
      }
    }
  }

  private handleOpenCodeEvent(event: ESObject): void {
    const eventType: string = (event['type'] || event['name']) as string;

    if (eventType !== 'message.part.delta' && eventType !== 'server.heartbeat') {
      hilog.info(DOMAIN, TAG, 'Event: %{public}s, data: %{public}s', eventType, JSON.stringify(event).substring(0, 200));
    }

    if (eventType === 'message.part.delta') {
      if (this.lastStatus !== 'running') {
        this.lastStatus = 'running';
        this.sendStatusMessage('running', '正在处理...');
      }
    } else if (eventType === 'message.updated') {
      const props: ESObject = event['properties'] as ESObject || {};
      const info: ESObject = props['info'] as ESObject || {};
      hilog.info(DOMAIN, TAG, 'message.updated: sessionID=%{public}s, id=%{public}s, role=%{public}s',
        props['sessionID'] as string || 'null',
        info['id'] as string || 'null',
        info['role'] as string || 'null');
      if (props['sessionID'] && info['id'] && info['role'] === 'assistant') {
        this.lastSentMessageId = info['id'] as string;
        hilog.info(DOMAIN, TAG, 'Set lastSentMessageId: %{public}s', this.lastSentMessageId);
      }
    } else if (eventType === 'session.idle') {
      hilog.info(DOMAIN, TAG, 'session.idle: lastSentMessageId=%{public}s, currentSessionId=%{public}s',
        this.lastSentMessageId, this.currentSessionId);
      if (this.lastStatus !== 'idle') {
        this.lastStatus = 'idle';
        this.sendStatusMessage('idle', '完成');
      }
      
      if (this.lastSentMessageId.length > 0 && this.currentSessionId.length > 0) {
        if (this.lastSentResponseId !== this.lastSentMessageId) {
          this.lastSentResponseId = this.lastSentMessageId;
          hilog.info(DOMAIN, TAG, 'Fetching completed message: session=%{public}s, msg=%{public}s',
            this.currentSessionId, this.lastSentMessageId);
          this.fetchCompletedMessage(this.currentSessionId, this.lastSentMessageId);
        } else {
          hilog.info(DOMAIN, TAG, 'Message already sent: %{public}s', this.lastSentMessageId);
        }
      } else {
        hilog.warn(DOMAIN, TAG, 'Missing IDs: lastSentMessageId=%{public}s, currentSessionId=%{public}s',
          this.lastSentMessageId, this.currentSessionId);
      }
    } else if (eventType === 'session.message') {
      // 备选：直接从 session.message 事件获取消息
      const data: ESObject = event['data'] as ESObject || {};
      if (data['sessionID'] && data['messageID']) {
        hilog.info(DOMAIN, TAG, 'session.message: session=%{public}s, msg=%{public}s',
          data['sessionID'] as string, data['messageID'] as string);
        this.fetchCompletedMessage(data['sessionID'] as string, data['messageID'] as string);
      }
    } else if (eventType === 'permission.request') {
      this.handlePermissionEvent(event);
    } else {
      // 记录未处理的事件，帮助调试
      if (eventType !== 'server.heartbeat' && eventType !== 'session.status') {
        hilog.debug(DOMAIN, TAG, 'Unhandled event: %{public}s', eventType);
      }
    }
  }

  private sendStatusMessage(status: string, message: string): void {
    for (let i = 0; i < this.messageCallbacks.length; i++) {
      const msg: ESObject = {
        'type': 'task_status',
        'status': status,
        'message': message
      };
      this.messageCallbacks[i](msg);
    }
  }

  private async fetchCompletedMessage(sessionId: string, messageId: string): Promise<void> {
    if (!this.currentServer) {
      hilog.error(DOMAIN, TAG, 'fetchCompletedMessage: No server');
      return;
    }

    hilog.info(DOMAIN, TAG, 'Fetching message from: /session/%{public}s/message/%{public}s', sessionId, messageId);

    try {
      const msgDetail: ESObject = await this.callAPIObject('GET', `/session/${sessionId}/message/${messageId}`) as ESObject;
      hilog.info(DOMAIN, TAG, 'Message detail: %{public}s', JSON.stringify(msgDetail).substring(0, 500));
      
      const parts: ESObject[] = msgDetail['parts'] as ESObject[] || [];
      hilog.info(DOMAIN, TAG, 'Parts count: %{public}d', parts.length);

      const textParts: string[] = [];
      const toolParts: string[] = [];

      for (let i = 0; i < parts.length; i++) {
        const p: ESObject = parts[i];
        if (p['type'] === 'text') {
          textParts.push(p['text'] as string || '');
        } else if (p['type'] === 'tool' && p['tool'] === 'bash' && p['state']?.['status'] === 'completed') {
          const cmd: string = p['state']?.['input']?.['command'] || '';
          const output: string = p['state']?.['output'] || '';
          toolParts.push(`[执行: ${cmd}]\n${output}`);
        }
      }

      const fullContent: string = (textParts.join('\n') + '\n' + toolParts.join('\n')).trim();
      hilog.info(DOMAIN, TAG, 'Full content length: %{public}d', fullContent.length);

      if (fullContent.length > 0) {
        hilog.info(DOMAIN, TAG, 'Sending ai_response with content: %{public}s', fullContent.substring(0, 100));
        for (let j = 0; j < this.messageCallbacks.length; j++) {
          const msg: ESObject = {
            'type': 'ai_response',
            'content': fullContent,
            'messageID': messageId
          };
          this.messageCallbacks[j](msg);
        }
      } else {
        hilog.warn(DOMAIN, TAG, 'No content to send');
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Fetch message failed: %{public}s', JSON.stringify(e));
    }
  }

  private handlePermissionEvent(event: ESObject): void {
    const data: ESObject = event['data'] as ESObject || {};
    const requestId: string = (data['id'] as string) || Date.now().toString();
    const msg: ESObject = {
      'type': 'permission_request',
      'id': requestId,
      'command': (data['permission'] || data['tool'] || 'Unknown') as string,
      'explanation': (data['message'] || '需要授权') as string
    };
    for (let i = 0; i < this.messageCallbacks.length; i++) {
      this.messageCallbacks[i](msg);
    }
  }

  close(): void {
    if (this.eventRequest) {
      this.eventRequest.off('dataReceive');
      this.eventRequest.off('dataEnd');
      this.eventRequest.destroy();
      this.eventRequest = null;
    }
    this.isConnected = false;
    this.currentServer = null;
    this.currentSessionId = '';
    this.lastSentMessageId = '';
    this.lastSentResponseId = '';
    this.notifyStatusChange(false);
  }

  getConnected(): boolean {
    return this.isConnected;
  }

  getCurrentServer(): ServerConfig | null {
    return this.currentServer;
  }

  getCurrentSessionId(): string {
    return this.currentSessionId;
  }

  setCurrentSessionId(sessionId: string): void {
    this.currentSessionId = sessionId;
  }

  disconnect(): void {
    this.close();
  }
}

export const openCodeService = new OpenCodeService();