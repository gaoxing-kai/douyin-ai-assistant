#!/bin/bash

# 抖音直播间智能AI助手一键部署脚本
# 适用于Ubuntu 20.04+ 系统

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
apt install -y python3 python3-pip python3-venv git nginx build-essential libssl-dev libffi-dev python3-dev

# 安装Node.js
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
pip install wheel
pip install -r requirements.txt

# 安装关键依赖
echo "安装关键依赖..."
pip install zope.event zope.interface

# 创建.env配置文件
echo "创建.env配置文件..."
cat > .env <<EOL
SECRET_KEY=$(openssl rand -hex 32)
DEEPSEEK_API_KEY=your_deepseek_api_key_here
BAIDU_APP_ID=your_baidu_app_id
BAIDU_API_KEY=your_baidu_api_key
BAIDU_SECRET_KEY=your_baidu_secret_key
DB_TYPE=sqlite
EOL

# 安装前端依赖
echo "安装前端依赖..."
cd static
npm install
cd ..

# 初始化数据库
echo "初始化数据库..."
source venv/bin/activate
python -c "from app import db, app; with app.app_context(): db.create_all()"

# 创建管理员用户
echo "创建管理员用户..."
python -c "from app import db, User, app; \
with app.app_context(): \
    if not User.query.filter_by(username='admin').first(): \
        admin = User(username='admin', password='admin', is_admin=True); \
        db.session.add(admin); \
        db.session.commit(); \
        print('管理员用户已创建')"

# 配置Nginx
echo "配置Nginx..."
cat > /etc/nginx/sites-available/douyin-ai-assistant <<EOL
server {
    listen 80;
    server_name _;
    
    # 静态文件服务
    location /static {
        alias /opt/douyin-ai-assistant/static;
        expires 30d;
    }
    
    # WebSocket支持
    location /socket.io {
        proxy_pass http://127.0.0.1:5000/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    # 主应用代理
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 增加超时时间
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
    }
    
    # 错误处理
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
        internal;
    }
    
    access_log /var/log/nginx/douyin-access.log;
    error_log /var/log/nginx/douyin-error.log;
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
EnvironmentFile=/opt/douyin-ai-assistant/.env
ExecStartPre=/bin/bash -c 'source /opt/douyin-ai-assistant/venv/bin/activate && pip install -r requirements.txt'
ExecStart=/opt/douyin-ai-assistant/venv/bin/gunicorn -w 4 -k "eventlet" -b 127.0.0.1:5000 app:app

# 重启策略
Restart=always
RestartSec=5
StartLimitInterval=0

# 日志配置
StandardOutput=file:/var/log/douyin-app.log
StandardError=file:/var/log/douyin-error.log

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable douyin-ai-assistant
systemctl start douyin-ai-assistant

# 创建日志文件
touch /var/log/douyin-app.log
touch /var/log/douyin-error.log
chown root:root /var/log/douyin-*.log
chmod 644 /var/log/douyin-*.log

# 安装完成
echo "安装完成！"
echo "--------------------------------"
echo "访问地址: http://$(curl -s ifconfig.me)"
echo "管理员账号: admin"
echo "管理员密码: admin"
echo ""
echo "请登录后立即修改管理员密码"
echo "--------------------------------"
echo "应用日志: /var/log/douyin-app.log"
echo "错误日志: /var/log/douyin-error.log"
echo "--------------------------------"