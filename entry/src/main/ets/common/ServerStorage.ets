/**
 * 服务器配置持久化存储服务
 */

import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { ServerConfig } from './Types';
import { Context } from '@kit.AbilityKit';

const DOMAIN = 0xFF00;
const TAG = 'ServerStorage';
const STORE_NAME = 'server_config';

export class ServerStorage {
  private static instance: ServerStorage;
  private dataStore: preferences.Preferences | null = null;
  private context: Context | null = null;
  private servers: ServerConfig[] = [];

  static getInstance(): ServerStorage {
    if (!ServerStorage.instance) {
      ServerStorage.instance = new ServerStorage();
    }
    return ServerStorage.instance;
  }

  async init(context: Context): Promise<void> {
    this.context = context;
    try {
      this.dataStore = await preferences.getPreferences(context, STORE_NAME);
      await this.loadServers();
      hilog.info(DOMAIN, TAG, 'ServerStorage initialized');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Init failed: %{public}s', JSON.stringify(e));
    }
  }

  private async loadServers(): Promise<void> {
    if (!this.dataStore) return;
    
    try {
      const serversJson: string = await this.dataStore.get('servers', '') as string;
      if (serversJson.length > 0) {
        this.servers = JSON.parse(serversJson) as ServerConfig[];
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Load servers failed: %{public}s', JSON.stringify(e));
      this.servers = [];
    }
  }

  private async saveServers(): Promise<void> {
    if (!this.dataStore) return;
    
    try {
      const serversJson: string = JSON.stringify(this.servers);
      await this.dataStore.put('servers', serversJson);
      await this.dataStore.flush();
      hilog.info(DOMAIN, TAG, 'Servers saved: %{public}d', this.servers.length);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Save servers failed: %{public}s', JSON.stringify(e));
    }
  }

  getServers(): ServerConfig[] {
    return this.servers;
  }

  async addServer(server: ServerConfig): Promise<boolean> {
    const existing: ServerConfig | undefined = this.servers.find(s => s.id === server.id);
    if (existing) {
      const index: number = this.servers.indexOf(existing);
      this.servers[index] = server;
    } else {
      this.servers.push(server);
    }
    await this.saveServers();
    return true;
  }

  async updateServer(server: ServerConfig): Promise<boolean> {
    const index: number = this.servers.findIndex(s => s.id === server.id);
    if (index >= 0) {
      this.servers[index] = server;
      await this.saveServers();
      return true;
    }
    return false;
  }

  async deleteServer(serverId: string): Promise<boolean> {
    const index: number = this.servers.findIndex(s => s.id === serverId);
    if (index >= 0) {
      this.servers.splice(index, 1);
      await this.saveServers();
      return true;
    }
    return false;
  }

  getServerById(serverId: string): ServerConfig | null {
    const server: ServerConfig | undefined = this.servers.find(s => s.id === serverId);
    return server || null;
  }

  getDefaultServer(): ServerConfig | null {
    const server: ServerConfig | undefined = this.servers.find(s => s.isDefault);
    return server || (this.servers.length > 0 ? this.servers[0] : null);
  }
}

export const serverStorage = ServerStorage.getInstance();