#!/bin/bash
# 修复后带错误处理的部署脚本

# 配置变量
PROJECT_DIR="/opt/douyin-ai-assistant"
VENV_DIR="$PROJECT_DIR/venv"
LOG_DIR="/var/log/douyin-ai"
APP_LOG="$LOG_DIR/app.log"
GUNICORN_PATH="$VENV_DIR/bin/gunicorn"  # 明确虚拟环境中的gunicorn路径

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. 初始化日志目录
mkdir -p $LOG_DIR
chmod 755 $LOG_DIR
touch $APP_LOG
chown -R www-data:www-data $LOG_DIR

# 2. 安装系统依赖（确保基础工具可用）
echo -e "${YELLOW}安装系统依赖...${NC}"
apt update -y >> $APP_LOG 2>&1
apt install -y python3 python3-pip python3-venv nginx git net-tools >> $APP_LOG 2>&1

# 3. 拉取代码
echo -e "${YELLOW}部署代码...${NC}"
if [ -d "$PROJECT_DIR" ]; then
    cd $PROJECT_DIR && git pull >> $APP_LOG 2>&1
else
    git clone https://github.com/gaoxing-kai/douyin-ai-assistant.git $PROJECT_DIR >> $APP_LOG 2>&1
fi

# 4. 配置Python虚拟环境（确保gunicorn安装在虚拟环境中）
echo -e "${YELLOW}配置Python环境...${NC}"
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate >> $APP_LOG 2>&1
pip install --upgrade pip >> $APP_LOG 2>&1
# 强制安装gunicorn到虚拟环境
pip install gunicorn >> $APP_LOG 2>&1
# 安装项目依赖（含修正后的baidu-aip）
pip install -r $PROJECT_DIR/requirements.txt >> $APP_LOG 2>&1 || {
    echo -e "${RED}依赖安装失败！查看日志：$APP_LOG${NC}"
    exit 1
}

# 5. 修复前端package.json并安装依赖
echo -e "${YELLOW}修复前端配置并安装依赖...${NC}"
cd $PROJECT_DIR/static
# 移除package.json中的注释（若存在）
sed -i '/\/\/.*/d' package.json  # 删除所有含//的行
npm install >> $APP_LOG 2>&1 || {
    echo -e "${RED}前端依赖安装失败！查看日志：$APP_LOG${NC}"
    exit 1
}
npm run build >> $APP_LOG 2>&1
cd $PROJECT_DIR

# 6. 数据库迁移
echo -e "${YELLOW}数据库迁移...${NC}"
export FLASK_APP="app.py"
flask db upgrade >> $APP_LOG 2>&1 || {
    echo -e "${RED}数据库迁移失败！查看日志：$APP_LOG${NC}"
    exit 1
}

# 7. 配置Nginx并重启
echo -e "${YELLOW}配置Nginx...${NC}"
cat > /etc/nginx/sites-available/douyin-ai <<EOL
server {
    listen 80;
    server_name _;
    access_log $LOG_DIR/nginx-access.log;
    error_log $LOG_DIR/nginx-error.log;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
    }
    location /socket.io {
        proxy_pass http://127.0.0.1:5000/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    location /static {
        alias $PROJECT_DIR/static;
    }
}
EOL
ln -s /etc/nginx/sites-available/douyin-ai /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx >> $APP_LOG 2>&1

# 8. 启动应用（使用虚拟环境中gunicorn的绝对路径）
echo -e "${YELLOW}启动应用服务...${NC}"
pkill -f "$GUNICORN_PATH" >> $APP_LOG 2>&1  # 停止残留进程
nohup $GUNICORN_PATH -w 4 -k geventwebsocket.gunicorn.workers.GeventWebSocketWorker \
    -b 127.0.0.1:5000 "app:app" >> $APP_LOG 2>&1 &

# 9. 检测应用启动状态
echo -e "${YELLOW}检测应用状态...${NC}"
for i in {1..30}; do
    if netstat -tulpn | grep -q ":5000"; then
        echo -e "${GREEN}应用启动成功！5000端口已监听${NC}"
        exit 0
    fi
    sleep 1
done

# 启动失败处理
echo -e "${RED}应用启动失败！查看日志：$APP_LOG${NC}"
exit 1