/**
 * ArkTS 兼容类型定义
 * 移除索引签名，和 indexed类型
 */

export interface WSMessage {
  type: string;
  content?: string | ESObject;
}

export interface FileInfo {
  name: string;
  path: string;
  size: number;
  modified: string;
  url: string
}

export interface ServerConfig {
  id: string;
  name: string;
  ip: string;
  port: number;
  username: string;
  password: string;
  isDefault: boolean;
  mode?: 'direct' | 'relay';
  relayUrl?: string;
  agentId?: string;
}

export interface SessionInfo {
  id: string;
  title: string;
  time: ESObject;
}

export interface ConnectionConfig {
  token: string;
  expire: number;
  ip: string;
  wsPort: number;
  httpPort: number;
}

export interface TaskMessage {
  id: string;
  type: 'user' | 'ai' | 'system' | 'permission';
  content: string;
  timestamp: number;
  status?: 'pending' | 'running' | 'completed' | 'error';
  thinking?: string;
  toolCalls?: ToolCallInfo[];
  progress?: ProgressInfo;
  isStreaming?: boolean;
}

export interface ToolCallInfo {
  id: string;
  name: string;
  input: string;
  output?: string;
  status: 'pending' | 'running' | 'completed' | 'error';
  timestamp: number;
}

export interface ProgressInfo {
  current: number;
  total: number;
  description: string;
}

export interface StreamDelta {
  type: 'text' | 'thinking' | 'tool_call' | 'tool_result';
  content?: string;
  toolId?: string;
  toolName?: string;
  toolInput?: string;
  toolOutput?: string;
  toolStatus?: 'pending' | 'running' | 'completed' | 'error';
  progress?: ProgressInfo;
}

export interface RelayConfig {
  serverUrl: string;
  agentId: string;
}

export interface AgentInfo {
  agentId: string;
  name: string;
  connectedAt: number;
}