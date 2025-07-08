#!/bin/bash

# 抖音直播间智能AI助手一键部署脚本
# 优化版：全自动错误处理 + 国内源加速 + Ubuntu 22.04适配
# 最后更新：2025年7月8日

set -euo pipefail  # 严格错误处理

echo "抖音直播间智能AI助手一键部署脚本 (Ubuntu 22.04 优化版)"
echo "--------------------------------"

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
   echo "错误：此脚本必须以root用户运行" 1>&2
   exit 1
fi

# 配置变量
SERVER_IP="101.126.155.137"  # 替换为实际服务器IP
PROJECT_DIR="/opt/douyin-ai-assistant"
REPO_URL="https://github.com/gaoxing-kai/douyin-ai-assistant.git"

# 安装系统依赖（使用国内源）
echo "步骤1/10: 配置国内源并更新系统..."
export DEBIAN_FRONTEND=noninteractive
sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list
apt-get update -yq
apt-get upgrade -yq

echo "步骤2/10: 安装系统依赖..."
apt-get install -yq \
    python3 \
    python3-pip \
    python3-venv \
    git \
    nginx \
    ufw \
    curl \
    gnupg \
    ca-certificates

# 安装Node.js（使用国内源）
echo "步骤3/10: 安装Node.js (使用淘宝源)..."
curl -sL https://deb.nodesource.com/setup_18.x | bash -  # 升级到18.x LTS
apt-get install -yq nodejs

# 配置npm淘宝源
npm config set registry https://registry.npmmirror.com

# 创建项目目录
echo "步骤4/10: 创建项目目录..."
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# 克隆项目（带重试机制）
echo "步骤5/10: 克隆项目代码..."
for i in {1..3}; do
    git clone $REPO_URL . && break || {
        echo "克隆失败，重试 $i/3..."
        sleep 2
        rm -rf $PROJECT_DIR/*  # 清理失败尝试
    }
done

if [ ! -f "requirements.txt" ]; then
    echo "错误：项目代码克隆失败！"
    exit 1
fi

# 创建虚拟环境
echo "步骤6/10: 创建Python虚拟环境..."
python3 -m venv venv
source venv/bin/activate

# 配置pip国内源
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip config set global.trusted-host pypi.tuna.tsinghua.edu.cn

# 安装Python依赖
echo "步骤7/10: 安装Python依赖..."
pip install --upgrade pip
pip install -r requirements.txt || {
    echo "警告：部分依赖安装失败，尝试继续..."
}

# 安装前端依赖
echo "步骤8/10: 安装前端依赖..."
cd static
npm install --force --registry=https://registry.npmmirror.com

# 构建前端
echo "构建前端资源..."
npm run build || {
    echo "警告：前端构建失败，尝试继续..."
}
cd ..

# 初始化数据库
echo "步骤9/10: 初始化数据库..."
if ! command -v flask &> /dev/null; then
    echo "错误：flask命令未找到！"
    exit 1
fi
flask db upgrade

# 配置Nginx
echo "步骤10/10: 配置服务..."
cat > /etc/nginx/sites-available/douyin-ai-assistant <<EOL
server {
    listen 80;
    server_name $SERVER_IP;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /socket.io {
        proxy_pass http://127.0.0.1:5000/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    
    location /static {
        alias $PROJECT_DIR/static;
        expires 30d;
    }
}
EOL

# 启用Nginx配置
ln -sf /etc/nginx/sites-available/douyin-ai-assistant /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# 配置防火墙
ufw allow 80/tcp
ufw allow 22/tcp
ufw --force enable

# 创建systemd服务
cat > /etc/systemd/system/douyin-ai-assistant.service <<EOL
[Unit]
Description=Douyin AI Assistant
After=network.target nginx.service

[Service]
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin"
ExecStart=$PROJECT_DIR/venv/bin/gunicorn \
    -w 4 \
    -k geventwebsocket.gunicorn.workers.GeventWebSocketWorker \
    -b 127.0.0.1:5000 \
    --timeout 120 \
    --access-logfile - \
    --error-logfile - \
    app:app

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# 启动服务
systemctl daemon-reload
systemctl enable douyin-ai-assistant
systemctl restart douyin-ai-assistant

# 等待服务启动
sleep 5
if ! systemctl is-active --quiet douyin-ai-assistant; then
    echo "错误：服务启动失败，请检查日志：journalctl -u douyin-ai-assistant"
    exit 1
fi

# 安装完成
echo "安装完成！"
echo "--------------------------------"
echo "访问地址: http://$SERVER_IP"
echo "管理员账号: admin"
echo "管理员密码: admin"
echo ""
echo "请登录后立即修改管理员密码"
echo "--------------------------------"
echo "常用命令:"
echo "  服务状态: systemctl status douyin-ai-assistant"
echo "  重启服务: systemctl restart douyin-ai-assistant"
echo "  查看日志: journalctl -u douyin-ai-assistant -f"
echo "--------------------------------"