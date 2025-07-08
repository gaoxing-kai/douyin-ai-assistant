#!/bin/bash
# 抖音直播间AI助手一键部署脚本
# 适用于Ubuntu 20.04+/Debian 10+

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误：必须以root用户运行此脚本${NC}" 1>&2
    exit 1
fi

# 输入配置
read -p "请输入服务器域名或IP: " SERVER_DOMAIN
read -p "请设置管理员初始密码: " ADMIN_PWD

# 变量定义
PROJECT_DIR="/opt/douyin-ai-assistant"
GIT_REPO="https://github.com/gaoxing-kai/douyin-ai-assistant.git"  # 替换为实际仓库
ENV_FILE="$PROJECT_DIR/.env"

# 显示信息
echo -e "\n${YELLOW}===== 开始部署抖音直播间AI助手 =====${NC}"
echo -e "部署路径: $PROJECT_DIR"
echo -e "访问地址: http://$SERVER_DOMAIN"
echo -e "----------------------------------------\n"

# 安装系统依赖
echo -e "${YELLOW}1. 安装系统依赖...${NC}"
apt update -y >/dev/null 2>&1
apt install -y \
    python3 python3-pip python3-venv \
    git nginx curl wget ufw \
    build-essential libssl-dev \
    nodejs npm >/dev/null 2>&1

# 克隆代码
echo -e "${YELLOW}2. 克隆项目代码...${NC}"
mkdir -p $PROJECT_DIR
git clone $GIT_REPO $PROJECT_DIR >/dev/null 2>&1 || {
    echo -e "${RED}错误：克隆代码失败，请检查仓库地址${NC}"
    exit 1
}
cd $PROJECT_DIR

# 创建虚拟环境
echo -e "${YELLOW}3. 配置Python环境...${NC}"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip >/dev/null 2>&1
pip install -r requirements.txt >/dev/null 2>&1
pip install gunicorn >/dev/null 2>&1

# 创建环境变量文件
echo -e "${YELLOW}4. 配置环境变量...${NC}"
cat > $ENV_FILE <<EOL
SECRET_KEY=$(uuidgen)
FLASK_ENV=production
DATABASE_URI=sqlite:///$PROJECT_DIR/site.db
DEEPSEEK_API_KEY=your_deepseek_key  # 替换为实际密钥
BAIDU_APP_ID=your_baidu_appid
BAIDU_API_KEY=your_baidu_apikey
BAIDU_SECRET_KEY=your_baidu_secret
ADMIN_PASSWORD=$ADMIN_PWD
EOL

# 初始化数据库
echo -e "${YELLOW}5. 初始化数据库...${NC}"
export FLASK_APP=app.py
flask run --host=127.0.0.1 --port=5001 >/dev/null 2>&1 &  # 临时启动初始化
sleep 5
pkill -f "flask run" >/dev/null 2>&1

# 配置Nginx
echo -e "${YELLOW}6. 配置Nginx...${NC}"
cat > /etc/nginx/sites-available/douyin-ai <<EOL
server {
    listen 80;
    server_name $SERVER_DOMAIN;

    access_log /var/log/nginx/douyin-access.log;
    error_log /var/log/nginx/douyin-error.log;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /socket.io {
        proxy_pass http://127.0.0.1:5000/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /static {
        alias $PROJECT_DIR/static;
        expires 1d;
    }
}
EOL

# 启用站点
ln -s /etc/nginx/sites-available/douyin-ai /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 || {
    echo -e "${RED}错误：Nginx配置无效${NC}"
    exit 1
}
systemctl restart nginx

# 创建系统服务
echo -e "${YELLOW}7. 配置系统服务...${NC}"
cat > /etc/systemd/system/douyin-ai.service <<EOL
[Unit]
Description=Douyin Live AI Assistant
After=network.target nginx.service

[Service]
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin"
ExecStart=$PROJECT_DIR/venv/bin/gunicorn -w 4 -k geventwebsocket.gunicorn.workers.GeventWebSocketWorker -b 127.0.0.1:5000 app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable douyin-ai >/dev/null 2>&1
systemctl start douyin-ai

# 配置防火墙
echo -e "${YELLOW}8. 配置防火墙...${NC}"
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 22/tcp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

# 完成部署
echo -e "\n${GREEN}===== 部署完成！=====${NC}"
echo -e "访问地址: http://$SERVER_DOMAIN"
echo -e "管理员账号: admin"
echo -e "管理员密码: $ADMIN_PWD（建议登录后立即修改）"
echo -e "服务状态: $(systemctl is-active douyin-ai)"
echo -e "----------------------------------------"
echo -e "管理命令:"
echo -e "  启动服务: systemctl start douyin-ai"
echo -e "  停止服务: systemctl stop douyin-ai"
echo -e "  查看日志: journalctl -u douyin-ai -f"