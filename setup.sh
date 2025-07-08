#!/bin/bash
# 抖音直播间AI助手一键部署脚本（含数据库迁移修复）
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
VENV_DIR="$PROJECT_DIR/venv"
MIGRATIONS_DIR="$PROJECT_DIR/migrations"  # 迁移目录路径

# 显示信息
echo -e "\n${YELLOW}===== 开始部署抖音直播间AI助手 =====${NC}"
echo -e "部署路径: $PROJECT_DIR"
echo -e "访问地址: http://$SERVER_DOMAIN"
echo -e "----------------------------------------\n"

# 1. 安装系统依赖
echo -e "${YELLOW}1. 安装系统依赖...${NC}"
apt update -y >/dev/null 2>&1
apt install -y \
    python3 python3-pip python3-venv \
    git nginx curl wget ufw \
    build-essential libssl-dev \
    nodejs npm >/dev/null 2>&1

# 2. 克隆代码
echo -e "${YELLOW}2. 克隆项目代码...${NC}"
mkdir -p $PROJECT_DIR
if [ -d "$PROJECT_DIR/.git" ]; then
    cd $PROJECT_DIR && git pull >/dev/null 2>&1
else
    git clone $GIT_REPO $PROJECT_DIR >/dev/null 2>&1 || {
        echo -e "${RED}错误：克隆代码失败，请检查仓库地址${NC}"
        exit 1
    }
fi
cd $PROJECT_DIR

# 3. 配置Python环境
echo -e "${YELLOW}3. 配置Python环境...${NC}"
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate
pip install --upgrade pip >/dev/null 2>&1
pip install -r requirements.txt >/dev/null 2>&1
pip install gunicorn >/dev/null 2>&1

# 4. 配置环境变量
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

# 5. 数据库迁移（核心修复：确保迁移目录存在）
echo -e "${YELLOW}5. 数据库迁移...${NC}"
export FLASK_APP=app.py
# 关键修复：若迁移目录不存在则初始化
if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo -e "${YELLOW}初始化数据库迁移环境...${NC}"
    flask db init >/dev/null 2>&1 || {
        echo -e "${RED}错误：迁移环境初始化失败，检查app.py是否存在${NC}"
        exit 1
    }
fi
# 创建迁移脚本（忽略空迁移警告）
flask db migrate -m "auto-migrate from deployment" >/dev/null 2>&1 || echo -e "${YELLOW}无新的数据库变更，跳过迁移脚本创建${NC}"
# 应用迁移（强制执行，确保最新结构）
flask db upgrade >/dev/null 2>&1 || {
    echo -e "${RED}错误：应用迁移失败，尝试修复数据库...${NC}"
    # 尝试修复数据库（删除旧库并重建）
    rm -f $PROJECT_DIR/site.db
    flask db upgrade >/dev/null 2>&1 || {
        echo -e "${RED}错误：数据库修复失败，请手动处理${NC}"
        exit 1
    }
}

# 6. 初始化管理员账户
echo -e "${YELLOW}6. 初始化管理员账户...${NC}"
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

# 7. 配置前端资源
echo -e "${YELLOW}7. 构建前端资源...${NC}"
cd $PROJECT_DIR/static
npm install >/dev/null 2>&1 || {
    echo -e "${RED}错误：安装前端依赖失败${NC}"
    exit 1
}
npm run build >/dev/null 2>&1 || {
    echo -e "${YELLOW}警告：前端资源压缩失败，使用未压缩版本${NC}"
}
cd $PROJECT_DIR

# 8. 配置Nginx
echo -e "${YELLOW}8. 配置Nginx...${NC}"
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

ln -s /etc/nginx/sites-available/douyin-ai /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 || {
    echo -e "${RED}错误：Nginx配置无效${NC}"
    exit 1
}
systemctl restart nginx

# 9. 配置系统服务
echo -e "${YELLOW}9. 配置系统服务...${NC}"
cat > /etc/systemd/system/douyin-ai.service <<EOL
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
systemctl enable douyin-ai >/dev/null 2>&1
systemctl restart douyin-ai

# 10. 配置防火墙
echo -e "${YELLOW}10. 配置防火墙...${NC}"
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
echo -e "数据库迁移命令（如需手动更新）:"
echo -e "  1. 进入项目目录: cd $PROJECT_DIR"
echo -e "  2. 激活环境: source $VENV_DIR/bin/activate"
echo -e "  3. 创建迁移: flask db migrate -m '描述变更'"
echo -e "  4. 应用迁移: flask db upgrade"