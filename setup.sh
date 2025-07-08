#!/bin/bash
# 抖音直播间AI助手全自动部署脚本（含前端构建与数据库迁移）
# 版本：v3.0 支持数据库迁移、前端资源构建、服务自启动

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置参数（可根据实际环境调整）
PROJECT_DIR="/opt/douyin-ai-assistant"
VENV_DIR="$PROJECT_DIR/venv"
STATIC_DIR="$PROJECT_DIR/static"
DB_MIGRATION_DIR="$PROJECT_DIR/migrations"
LOG_DIR="/var/log/douyin-ai"
GIT_REPO="https://github.com/gaoxing-kai/douyin-ai-assistant.git"  # 替换为实际仓库地址
NODE_VERSION="16.14.2"  # 前端构建所需Node版本
SERVER_IP=$(hostname -I | awk '{print $1}')  # 自动获取服务器IP

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误：此脚本必须以root用户运行${NC}" 1>&2
    exit 1
fi

# 阶段1：系统环境准备
echo -e "\n${YELLOW}===== 阶段1/5：系统环境初始化 ====="
# 更新系统包
apt update -y
apt upgrade -y

# 安装基础依赖
apt install -y \
    python3 python3-pip python3-venv \
    git nginx curl wget software-properties-common \
    build-essential libssl-dev libffi-dev \
    nodejs npm  # 前端构建依赖

# 安装nvm管理Node.js版本
if [ ! -d "$HOME/.nvm" ]; then
    echo -e "${YELLOW}安装nvm...${NC}"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
    # 加载nvm环境
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    # 安装指定版本Node.js并设为默认
    nvm install $NODE_VERSION
    nvm alias default $NODE_VERSION
else
    echo -e "${GREEN}nvm已安装，跳过初始化${NC}"
fi

# 阶段2：代码拉取与目录准备
echo -e "\n${YELLOW}===== 阶段2/5：代码部署 ====="
# 创建项目目录
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# 拉取代码（支持首次克隆或更新）
if [ -d ".git" ]; then
    echo -e "${YELLOW}更新代码...${NC}"
    git pull
else
    echo -e "${YELLOW}克隆代码...${NC}"
    git clone $GIT_REPO .
fi

# 阶段3：前端资源构建（含package.json处理）
echo -e "\n${YELLOW}===== 阶段3/5：前端资源构建 ====="
cd $STATIC_DIR

# 检查并生成package.json
if [ ! -f "package.json" ]; then
    echo -e "${YELLOW}生成package.json...${NC}"
    cat > package.json <<EOL
{
  "name": "douyin-ai-frontend",
  "version": "1.0.0",
  "description": "抖音直播间AI助手前端资源",
  "main": "js/script.js",
  "scripts": {
    "build": "npm run minify-css && npm run minify-js",
    "minify-css": "cleancss -o css/style.min.css css/style.css",
    "minify-js": "uglifyjs js/script.js -o js/script.min.js -c -m",
    "preinstall": "echo '前端依赖预安装完成'"
  },
  "dependencies": {
    "socket.io-client": "4.0.1"
  },
  "devDependencies": {
    "clean-css-cli": "^5.6.3",
    "uglify-js": "^3.17.4"
  }
}
EOL
else
    echo -e "${GREEN}package.json已存在，跳过生成${NC}"
fi

# 安装前端依赖并构建
echo -e "${YELLOW}安装前端依赖...${NC}"
npm install

echo -e "${YELLOW}执行前端构建...${NC}"
npm run build  # 执行CSS/JS压缩

cd $PROJECT_DIR  # 回到项目根目录

# 阶段4：Python环境配置与数据库迁移
echo -e "\n${YELLOW}===== 阶段4/5：Python环境与数据库 ====="
# 创建并激活虚拟环境
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv $VENV_DIR
fi
source $VENV_DIR/bin/activate

# 安装Python依赖
echo -e "${YELLOW}安装Python依赖...${NC}"
pip install --upgrade pip
pip install -r requirements.txt

# 数据库迁移处理
echo -e "${YELLOW}执行数据库迁移...${NC}"
# 初始化迁移环境（仅首次执行）
if [ ! -d "$DB_MIGRATION_DIR" ]; then
    flask db init
fi
# 创建并应用迁移
flask db migrate -m "初始化数据库结构"
flask db upgrade

# 阶段5：服务配置与启动
echo -e "\n${YELLOW}===== 阶段5/5：服务部署 ====="
# 配置Nginx
echo -e "${YELLOW}配置Nginx...${NC}"
cat > /etc/nginx/sites-available/douyin-ai <<EOL
server {
    listen 80;
    server_name $SERVER_IP;

    access_log $LOG_DIR/nginx-access.log;
    error_log $LOG_DIR/nginx-error.log;

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
        alias $STATIC_DIR;
        expires 1d;
        # 优先加载压缩后的静态资源
        try_files \$uri \$uri.min \$uri/ =404;
    }
}
EOL

# 启用Nginx配置
ln -s /etc/nginx/sites-available/douyin-ai /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 检查Nginx配置并重启
nginx -t && systemctl restart nginx || {
    echo -e "${RED}Nginx配置错误，请检查！${NC}"
    exit 1
}

# 配置系统服务（含数据库迁移自动处理）
echo -e "${YELLOW}配置系统服务...${NC}"
cat > /etc/systemd/system/douyin-ai.service <<EOL
[Unit]
Description=抖音直播间AI助手服务
After=network.target nginx.service
Requires=nginx.service

[Service]
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$VENV_DIR/bin"
EnvironmentFile=$PROJECT_DIR/.env  # 加载环境变量
ExecStart=$VENV_DIR/bin/gunicorn \
          --workers 4 \
          --worker-class geventwebsocket.gunicorn.workers.GeventWebSocketWorker \
          --bind 127.0.0.1:5000 \
          "app:app"
# 数据库迁移触发：服务启动/重启时自动检查迁移
ExecReload=$VENV_DIR/bin/flask db upgrade
Restart=always
RestartSec=3
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOL

# 服务初始化与启动
systemctl daemon-reload
systemctl enable douyin-ai.service
systemctl restart douyin-ai.service

# 验证部署结果
echo -e "\n${GREEN}===== 部署完成 ====="
echo -e "服务状态：$(systemctl is-active douyin-ai.service)"
echo -e "访问地址：http://$SERVER_IP"
echo -e "日志查看：journalctl -u douyin-ai.service -f"
echo -e "前端资源：已构建完成（style.min.css/script.min.js）"
echo -e "数据库状态：已完成迁移，支持自动升级"