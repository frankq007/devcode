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
}