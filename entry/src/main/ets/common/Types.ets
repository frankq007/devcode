/**
 * 类型定义
 */

// WebSocket 消息类型
export interface WSMessage {
  type: string;
  [key: string]: ESObject;
}

// 认证消息
export interface AuthMessage extends WSMessage {
  type: 'auth';
  token: string;
}

// 认证结果
export interface AuthResultMessage extends WSMessage {
  type: 'auth_result';
  success: boolean;
  message: string;
}

// 执行指令消息
export interface ExecMessage extends WSMessage {
  type: 'exec';
  content: string;
}

// 任务状态消息
export interface TaskStatusMessage extends WSMessage {
  type: 'task_status';
  status: 'running' | 'completed' | 'error' | 'terminated';
  content?: string;
  code?: number;
}

// 权限请求消息
export interface PermissionRequestMessage extends WSMessage {
  type: 'permission_request';
  id: string;
  command: string;
  explanation: string;
  raw: string;
}

// 权限响应消息
export interface PermissionResponseMessage extends WSMessage {
  type: 'permission_response';
  id: string;
  answer: string;
}

// 文件添加消息
export interface FileAddedMessage extends WSMessage {
  type: 'file_added';
  filename: string;
  url: string;
  size: number;
  modified: string;
  mimeType: string;
}

// 文件列表
export interface FileListMessage extends WSMessage {
  type: 'file_list';
  files: FileInfo[];
}

// 文件信息
export interface FileInfo {
  name: string;
  path: string;
  size: number;
  modified: string;
  url: string;
}

// 连接配置（从二维码解析）
export interface ConnectionConfig {
  token: string;
  expire: number;
  ip: string;
  wsPort: number;
  httpPort: number;
}

// 任务消息（用于 UI 显示）
export interface TaskMessage {
  id: string;
  type: 'user' | 'ai' | 'system' | 'permission';
  content: string;
  timestamp: number;
  status?: 'pending' | 'running' | 'completed' | 'error';
}

// App 状态
export interface AppState {
  connected: boolean;
  authenticated: boolean;
  serverIp: string;
  wsPort: number;
  httpPort: number;
  messages: TaskMessage[];
  files: FileInfo[];
  currentPermissionRequest: PermissionRequestMessage | null;
}