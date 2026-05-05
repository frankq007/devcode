#!/bin/bash

# OpenCode Serve 启动脚本
# 用于启动 OpenCode Serve 并设置认证信息

echo "========================================"
echo "  OpenCode Serve Launcher"
echo "========================================"

# 默认配置
PORT=4096
USERNAME="devcode"
PASSWORD="devcode123"

# 检查参数
if [ "$1" != "" ]; then
    USERNAME="$1"
fi

if [ "$2" != "" ]; then
    PASSWORD="$2"
fi

echo "端口: $PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo ""

# 获取本地 IP
LOCAL_IP=$(hostname -I | awk '{print $1}')
if [ "$LOCAL_IP" == "" ]; then
    LOCAL_IP="127.0.0.1"
fi

echo "服务器地址: http://$LOCAL_IP:$PORT"
echo ""

# 生成二维码信息
QR_DATA="opencode://connect?ip=$LOCAL_IP&port=$PORT&username=$USERNAME&password=$PASSWORD"
echo "扫码连接信息:"
echo "$QR_DATA"
echo ""

# 启动 OpenCode Serve
echo "启动 OpenCode Serve..."
opencode serve --port $PORT --username "$USERNAME" --password "$PASSWORD"

echo ""
echo "========================================"
echo "  连接信息"
echo "========================================"
echo "IP: $LOCAL_IP"
echo "端口: $PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo ""
echo "在手机端添加服务器时填写以上信息"
echo "========================================"