/**
 * ArkTS 兼容类型定义
 * 移除索引签名，和 indexed类型
 */

 
export interface WSMessage {
  type: string;
  content?: string | ESObject;
}

 
// 文件信息
export interface FileInfo {
  name: string;
  path: string;
  size: number;
  modified: string;
  url: string
}
 
// 连接配置
export interface ConnectionConfig {
  token: string;
  expire: number;
  ip: string;
  wsPort: number;
  httpPort: number;
}
    
// 任务消息
export interface TaskMessage {
  id: string;
  type: 'user' | 'ai' | 'system' | 'permission';
  content: string;
  timestamp: number;
  status?: 'pending' | 'running' | 'completed' | 'error';
}