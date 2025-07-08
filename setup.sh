#!/bin/bash
# 抖音直播间智能AI助手 完整自动部署脚本
# 适用系统：Ubuntu 20.04+/Debian 10+
# 版本：1.0.0（解决Nginx配置冲突、服务启动失败等问题）

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

# 输入配置信息
read -p "请输入服务器IP或域名（如：101.126.155.137）: " SERVER_ADDR
read -p "请设置管理员初始密码: " ADMIN_PWD
read -p "请输入Git仓库地址（默认：https://github.com/gaoxing-kai/douyin-ai-assistant.git）: " GIT_REPO
GIT_REPO=${GIT_REPO:-"https://github.com/gaoxing-kai/douyin-ai-assistant.git"}

# 核心变量定义
PROJECT_DIR="/opt/douyin-ai-assistant"
VENV_DIR="$PROJECT_DIR/venv"
NGINX_CONF="douyin-ai"
SERVICE_NAME="douyin-ai-assistant"
ENV_FILE="$PROJECT_DIR/.env"

# 显示部署信息
echo -e "\n${YELLOW}===== 开始部署抖音直播间AI助手 =====${NC}"
echo -e "部署路径: $PROJECT_DIR"
echo -e "访问地址: http://$SERVER_ADDR"
echo -e "Git仓库: $GIT_REPO"
echo -e "----------------------------------------\n"

# 1. 安装系统依赖（解决依赖缺失问题）
echo -e "${YELLOW}1. 安装系统依赖...${NC}"
apt update -y >/dev/null 2>&1
apt install -y \
    python3 python3-pip python3-venv \
    git nginx curl wget ufw \
    build-essential libssl-dev \
    nodejs npm >/dev/null 2>&1 || {
    echo -e "${RED}系统依赖安装失败，请检查网络${NC}"
    exit 1
}

# 2. 清理旧部署（解决残留文件冲突）
echo -e "${YELLOW}2. 清理旧部署文件...${NC}"
systemctl stop $SERVICE_NAME >/dev/null 2>&1
systemctl disable $SERVICE_NAME >/dev/null 2>&1
rm -f /etc/systemd/system/$SERVICE_NAME.service
rm -rf $PROJECT_DIR
rm -f /etc/nginx/sites-enabled/$NGINX_CONF
rm -f /etc/nginx/sites-available/$NGINX_CONF

# 3. 克隆项目代码
echo -e "${YELLOW}3. 克隆项目代码...${NC}"
mkdir -p $PROJECT_DIR
git clone $GIT_REPO $PROJECT_DIR >/dev/null 2>&1 || {
    echo -e "${RED}代码克隆失败，请检查仓库地址${NC}"
    exit 1
}
cd $PROJECT_DIR

# 4. 配置Python环境（解决依赖版本问题）
echo -e "${YELLOW}4. 配置Python环境...${NC}"
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate
pip install --upgrade pip >/dev/null 2>&1
pip install -r requirements.txt >/dev/null 2>&1 || {
    echo -e "${RED}Python依赖安装失败${NC}"
    exit 1
}
pip install gunicorn gevent-websocket >/dev/null 2>&1

# 5. 配置前端依赖与构建
echo -e "${YELLOW}5. 构建前端资源...${NC}"
cd static
npm install >/dev/null 2>&1
npm run build >/dev/null 2>&1
cd ..

# 6. 生成环境变量文件（解决配置缺失问题）
echo -e "${YELLOW}6. 配置环境变量...${NC}"
cat > $ENV_FILE <<EOL
SECRET_KEY=$(uuidgen)
FLASK_ENV=production
DATABASE_URI=sqlite:///$PROJECT_DIR/site.db
DEEPSEEK_API_KEY=your_deepseek_key  # 请替换为实际密钥
BAIDU_APP_ID=your_baidu_appid      # 请替换为实际密钥
BAIDU_API_KEY=your_baidu_apikey    # 请替换为实际密钥
BAIDU_SECRET_KEY=your_baidu_secret  # 请替换为实际密钥
LOG_FILE=$PROJECT_DIR/app.log
ADMIN_PASSWORD=$ADMIN_PWD
EOL
chmod 644 $ENV_FILE

# 7. 数据库初始化与迁移（解决表结构问题）
echo -e "${YELLOW}7. 初始化数据库...${NC}"
export FLASK_APP=app.py
source $VENV_DIR/bin/activate
# 初始化迁移环境（首次部署）
if [ ! -d "$PROJECT_DIR/migrations" ]; then
    flask db init >/dev/null 2>&1
fi
# 创建并应用迁移
flask db migrate -m "auto-deploy" >/dev/null 2>&1
flask db upgrade >/dev/null 2>&1

# 8. 初始化管理员账户
echo -e "${YELLOW}8. 创建管理员账户...${NC}"
cat > init_admin.py <<EOL
from app import app, db, User, Setting
from werkzeug.security import generate_password_hash
with app.app_context():
    if not User.query.filter_by(username='admin').first():
        admin = User(
            username='admin',
            password_hash=generate_password_hash('$ADMIN_PWD'),
            is_admin=True
        )
        db.session.add(admin)
        db.session.flush()
        db.session.add(Setting(user_id=admin.id))
        db.session.commit()
EOL
python init_admin.py >/dev/null 2>&1
rm init_admin.py

# 9. 配置Nginx（解决配置冲突与语法错误）
echo -e "${YELLOW}9. 配置Nginx服务...${NC}"
# 生成正确的Nginx配置
cat > /etc/nginx/sites-available/$NGINX_CONF <<EOL
server {
    listen 80;
    server_name $SERVER_ADDR;

    access_log /var/log/nginx/douyin-access.log;
    error_log /var/log/nginx/douyin-error.log;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
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
        expires 1d;
    }
}
EOL

# 创建符号链接（先删除旧链接避免冲突）
rm -f /etc/nginx/sites-enabled/$NGINX_CONF
ln -s /etc/nginx/sites-available/$NGINX_CONF /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default  # 移除默认配置避免冲突

# 验证Nginx配置
nginx -t >/dev/null 2>&1 || {
    echo -e "${RED}Nginx配置错误，请检查脚本中的Nginx模板${NC}"
    exit 1
}
systemctl restart nginx
systemctl enable nginx

# 10. 配置系统服务（解决服务启动失败问题）
echo -e "${YELLOW}10. 配置系统服务...${NC}"
cat > /etc/systemd/system/$SERVICE_NAME.service <<EOL
[Unit]
Description=Douyin Live AI Assistant
After=network.target nginx.service

[Service]
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$VENV_DIR/bin"
EnvironmentFile=$ENV_FILE
ExecStart=$VENV_DIR/bin/gunicorn -w 4 -k geventwebsocket.gunicorn.workers.GeventWebSocketWorker -b 127.0.0.1:5000 app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# 11. 配置防火墙（解决网络访问问题）
echo -e "${YELLOW}11. 配置防火墙...${NC}"
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 22/tcp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

# 12. 部署完成验证
echo -e "\n${GREEN}===== 部署成功！=====${NC}"
echo -e "访问地址: http://$SERVER_ADDR"
echo -e "管理员账号: admin"
echo -e "管理员密码: $ADMIN_PWD（请登录后立即修改）"
echo -e "----------------------------------------"
echo -e "服务状态: $(systemctl is-active $SERVICE_NAME)"
echo -e "Nginx状态: $(systemctl is-active nginx)"
echo -e "----------------------------------------"
echo -e "管理命令:"
echo -e "  启动服务: systemctl start $SERVICE_NAME"
echo -e "  停止服务: systemctl stop $SERVICE_NAME"
echo -e "  查看日志: journalctl -u $SERVICE_NAME -f"
echo -e "  重启Nginx: systemctl restart nginx"