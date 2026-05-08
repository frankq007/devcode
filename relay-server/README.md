# 云转发部署说明

## 架构概述

```
手机 App --wss--> 云中转服务器 <--wss--> 本地 Agent --> OpenCode Serve
```

## 部署步骤

### 1. 云服务器部署 (阿里云)

#### 1.1 安装依赖
```bash
# 安装 Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# 安装 Nginx
sudo apt install -y nginx
```

#### 1.2 部署中转服务器
```bash
# 克隆代码
git clone https://github.com/frankq007/devcode.git
cd devcode/relay-server

# 安装依赖
npm install

# 生成 SSL 证书 (自签名)
bash generate-cert.sh

# 或使用 Let's Encrypt (推荐，需有域名)
# sudo apt install -y certbot
# sudo certbot certonly --standalone -d relay.example.com
```

#### 1.3 配置 Nginx
```bash
# 复制配置示例
sudo cp nginx.conf.example /etc/nginx/sites-available/relay

# 修改配置中的证书路径和域名/IP
sudo nano /etc/nginx/sites-available/relay

# 启用配置
sudo ln -s /etc/nginx/sites-available/relay /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

#### 1.4 启动中转服务器
```bash
# 直接启动
npm start

# 或使用 PM2 保持运行
sudo npm install -g pm2
pm2 start server.js --name relay-server
pm2 save
pm2 startup
```

### 2. 本地 Agent 部署

#### 2.1 启动 OpenCode Serve
```bash
opencode serve --port 4096
```

#### 2.2 启动 Agent
```bash
cd server

# 设置环境变量
export RELAY_SERVER_URL=wss://relay.example.com  # 或 wss://YOUR_IP
export AGENT_ID=my-agent
export AGENT_NAME="My DevCode Agent"

# 启动 Agent
node agent.js

# 或使用 PM2
pm2 start agent.js --name devcode-agent
```

### 3. 手机 App 配置

#### 3.1 直连模式 (局域网/Tailscale)
- 连接名称: 自定义
- IP 地址: 本地 IP 或 Tailscale IP
- 端口: 4096
- 用户名/密码: OpenCode Serve 认证信息

#### 3.2 云中转模式
- 云服务器: `wss://relay.example.com` 或 `wss://YOUR_SERVER_IP`
- Agent ID: 配置的 Agent ID (如 `my-agent`)

## SSL 证书说明

### 自签名证书 (无域名)
- 证书文件: `relay-server/cert/server.crt`
- 密钥文件: `relay-server/cert/server.key`
- 手机 App 需要信任证书或跳过验证

### Let's Encrypt (有域名)
```bash
# 获取证书
sudo certbot certonly --standalone -d relay.example.com

# 证书位置
# /etc/letsencrypt/live/relay.example.com/fullchain.pem
# /etc/letsencrypt/live/relay.example.com/privkey.pem

# 自动续期
sudo certbot renew --dry-run
```

## 验证测试

### 1. 测试云中转服务器
```bash
# 检查服务状态
curl http://localhost:8080/status

# 或通过 HTTPS
curl https://relay.example.com/status
```

### 2. 测试 Agent 连接
```bash
# 查看 Agent 日志
pm2 logs devcode-agent

# 应看到 "Agent registered" 消息
```

### 3. 测试手机连接
- 打开 DevCode App
- 选择 "云中转" 模式
- 输入云服务器地址和 Agent ID
- 点击连接

## 端口说明

| 服务 | 端口 | 说明 |
|------|------|------|
| 云中转 (内部) | 8080 | Node.js WebSocket 服务 |
| HTTPS/WSS | 443 | Nginx SSL 代理 |
| HTTP | 80 | 重定向到 HTTPS |
| OpenCode Serve | 4096 | 本地运行 |

## 常见问题

### Q: 手机无法连接云服务器
1. 检查防火墙是否开放 443 端口
2. 检查 Nginx 配置是否正确
3. 检查 SSL 证书是否有效

### Q: Agent 无法连接云服务器
1. 检查 RELAY_SERVER_URL 是否正确
2. 检查网络是否可访问云服务器
3. 检查云中转服务器是否正常运行

### Q: 自签名证书警告
- 手机 App 可以忽略证书验证 (开发测试)
- 生产环境建议使用 Let's Encrypt 正式证书