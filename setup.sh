#!/bin/bash

# 抖音直播间智能AI助手一键部署脚本
# 适用于火山引擎Linux系统

echo "抖音直播间智能AI助手一键部署脚本"
echo "--------------------------------"

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
   echo "此脚本必须以root用户运行" 1>&2
   exit 1
fi

# 安装系统依赖
echo "安装系统依赖..."
apt update
apt upgrade -y
apt install -y python3 python3-pip python3-venv git nginx

# 安装Node.js（用于构建前端）
curl -sL https://deb.nodesource.com/setup_16.x | bash -
apt install -y nodejs

# 创建项目目录
mkdir -p /opt/douyin-ai-assistant
cd /opt/douyin-ai-assistant

# 克隆项目
echo "克隆项目代码..."
git clone https://github.com/gaoxing-kai/douyin-ai-assistant.git .

# 创建虚拟环境
echo "创建Python虚拟环境..."
python3 -m venv venv
source venv/bin/activate

# 安装Python依赖
echo "安装Python依赖..."
pip install --upgrade pip
pip install -r requirements.txt

# 安装前端依赖
echo "安装前端依赖..."
cd static
npm install

# 构建前端（如果需要）
echo "构建前端资源..."
npm run build
cd ..

# 初始化数据库
echo "初始化数据库..."
flask db upgrade

# 配置Nginx
echo "配置Nginx..."
cat > /etc/nginx/sites-available/douyin-ai-assistant <<EOL
server {
    listen 80;
    server_name your-domain.com;
    
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
        alias /opt/douyin-ai-assistant/static;
    }
}
EOL

ln -s /etc/nginx/sites-available/douyin-ai-assistant /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

# 配置防火墙
echo "配置防火墙..."
ufw allow 80
ufw allow 22
ufw enable

# 创建systemd服务
echo "创建systemd服务..."
cat > /etc/systemd/system/douyin-ai-assistant.service <<EOL
[Unit]
Description=Douyin AI Assistant
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/opt/douyin-ai-assistant
Environment="PATH=/opt/douyin-ai-assistant/venv/bin"
ExecStart=/opt/douyin-ai-assistant/venv/bin/gunicorn -w 4 -k geventwebsocket.gunicorn.workers.GeventWebSocketWorker -b 127.0.0.1:5000 app:app

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable douyin-ai-assistant
systemctl start douyin-ai-assistant

# 安装完成
echo "安装完成！"
echo "--------------------------------"
echo "访问地址: http://your-domain.com"
echo "管理员账号: admin"
echo "管理员密码: admin"
echo ""
echo "请登录后立即修改管理员密码"
echo "--------------------------------"