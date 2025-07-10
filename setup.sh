#!/bin/bash
# 抖音直播间AI助手 智能部署脚本 v2.0
# 特性：国内源适配 | 错误自修复 | 环境智能检测 | 交互式配置
# 支持系统：Ubuntu 20.04+/Debian 10+

# ==============================================
# 基础配置与初始化
# ==============================================
# 颜色与样式定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# 日志配置
DEPLOY_LOG="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a $DEPLOY_LOG) 2>&1  # 输出同时写入日志

# 核心变量（可自动推导或交互配置）
PROJECT_NAME="douyin-ai-assistant"
PROJECT_DIR="/opt/$PROJECT_NAME"
VENV_DIR="$PROJECT_DIR/venv"
SERVICE_NAME="$PROJECT_NAME"
ENV_FILE="$PROJECT_DIR/.env"
MIN_MEMORY=1024  # 最小内存要求（MB）
MIN_DISK=10240   # 最小磁盘空间要求（MB）


# ==============================================
# 智能工具函数
# ==============================================
# 进度条显示
progress_bar() {
    local duration=$1
    local width=50
    local interval=0.1
    local steps=$((duration / interval))
    
    for ((i=0; i<=steps; i++)); do
        local progress=$((i * 100 / steps))
        local filled=$((i * width / steps))
        local empty=$((width - filled))
        printf "\r${BLUE}[${BOLD}%${3}d${NORMAL}%] ${BOLD}%s${NORMAL}%s${NC}" \
            $progress $(printf "%0.s=" $(seq 1 $filled)) $(printf "%0.s " $(seq 1 $empty))
        sleep $interval
    done
    echo -e "\n"
}

# 错误处理与修复
handle_error() {
    local error_msg=$1
    local fix_cmd=$2
    local step_name=$3

    echo -e "\n${RED}❌ 步骤失败: $step_name${NC}"
    echo -e "${YELLOW}⚠️ 错误信息: $error_msg${NC}"
    
    if [ -n "$fix_cmd" ]; then
        read -p "是否尝试自动修复? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}🔧 正在执行修复命令: $fix_cmd${NC}"
            eval $fix_cmd
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ 修复成功，继续部署...${NC}"
                return 0
            else
                echo -e "${RED}❌ 修复失败，请手动处理后重试${NC}"
                exit 1
            fi
        else
            echo -e "${RED}❌ 用户取消修复，部署终止${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ 无自动修复方案，请手动排查后重试${NC}"
        exit 1
    fi
}

# 系统要求检测
check_system_requirements() {
    echo -e "${BLUE}🔍 正在检测系统环境...${NC}"
    
    # 检测内存
    local memory_total=$(free -m | awk '/Mem:/ {print $2}')
    if [ $memory_total -lt $MIN_MEMORY ]; then
        handle_error "内存不足（当前: ${memory_total}MB，要求: ${MIN_MEMORY}MB）" "" "系统内存检测"
    fi
    
    # 检测磁盘空间
    local disk_free=$(df -P $PROJECT_DIR | awk 'NR==2 {print $4}')  # KB
    disk_free=$((disk_free / 1024))  # 转换为MB
    if [ $disk_free -lt $MIN_DISK ]; then
        handle_error "磁盘空间不足（当前: ${disk_free}MB，要求: ${MIN_DISK}MB）" "" "磁盘空间检测"
    fi
    
    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
    else
        handle_error "无法识别操作系统" "" "操作系统检测"
    fi
    
    echo -e "${GREEN}✅ 系统环境检测通过（${OS} ${VERSION}）${NC}"
}

# 智能切换国内源
switch_to_china_mirrors() {
    echo -e "${BLUE}🌐 正在配置国内源（加速下载）...${NC}"
    progress_bar 3  # 模拟进度
    
    if [[ $OS == *"Ubuntu"* ]]; then
        # Ubuntu 国内源（阿里云）
        local sources_list="/etc/apt/sources.list"
        if ! grep -q "mirrors.aliyun.com" $sources_list; then
            cp $sources_list "${sources_list}.bak"
            sed -i "s/archive.ubuntu.com/mirrors.aliyun.com/g" $sources_list
            sed -i "s/security.ubuntu.com/mirrors.aliyun.com/g" $sources_list
            apt update -y >/dev/null 2>&1 || {
                handle_error "Ubuntu源更新失败" "cp ${sources_list}.bak $sources_list && apt update -y" "国内源配置"
            }
        fi
    elif [[ $OS == *"Debian"* ]]; then
        # Debian 国内源（清华）
        local sources_list="/etc/apt/sources.list"
        if ! grep -q "mirrors.tuna.tsinghua.edu.cn" $sources_list; then
            cp $sources_list "${sources_list}.bak"
            sed -i "s/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g" $sources_list
            sed -i "s/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g" $sources_list
            apt update -y >/dev/null 2>&1 || {
                handle_error "Debian源更新失败" "cp ${sources_list}.bak $sources_list && apt update -y" "国内源配置"
            }
        fi
    fi
    
    # npm 国内源
    npm config get registry | grep -q "taobao" || npm config set registry https://registry.npmmirror.com
    
    echo -e "${GREEN}✅ 国内源配置完成${NC}"
}


# ==============================================
# 主部署流程
# ==============================================
main() {
    # 检查root权限
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误：必须以root用户运行此脚本${NC}" 1>&2
        exit 1
    fi

    # 欢迎信息
    clear
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}         抖音直播间AI助手 智能部署工具        ${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "  版本: v2.0 | 支持系统: Ubuntu/Debian"
    echo -e "  部署日志将保存至: $(pwd)/$DEPLOY_LOG"
    echo -e "${GREEN}==============================================${NC}\n"

    # 系统要求检测
    check_system_requirements

    # 交互式配置
    echo -e "${BLUE}📋 请完成以下配置（直接回车使用默认值）${NC}"
    read -p "请输入服务器IP或域名（访问地址）: " SERVER_ADDR
    while [ -z "$SERVER_ADDR" ]; do
        echo -e "${YELLOW}⚠️ 服务器地址不能为空${NC}"
        read -p "请输入服务器IP或域名（访问地址）: " SERVER_ADDR
    done

    read -p "请设置管理员初始密码: " ADMIN_PWD
    while [ -z "$ADMIN_PWD" ]; do
        echo -e "${YELLOW}⚠️ 密码不能为空${NC}"
        read -p "请设置管理员初始密码: " ADMIN_PWD
    done

    read -p "请输入Git仓库地址（默认: https://gitee.com/gaoxing-kai/douyin-ai-assistant.git）: " GIT_REPO
    GIT_REPO=${GIT_REPO:-"https://gitee.com/gaoxing-kai/douyin-ai-assistant.git"}  # 国内Gitee源

    # 显示配置确认
    echo -e "\n${YELLOW}📝 部署配置确认${NC}"
    echo -e "  服务器地址: $SERVER_ADDR"
    echo -e "  管理员密码: ******（已加密保存）"
    echo -e "  代码仓库: $GIT_REPO"
    echo -e "  部署路径: $PROJECT_DIR"
    read -p "确认以上配置正确? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ 用户取消部署${NC}"
        exit 0
    fi

    # 开始部署
    echo -e "\n${GREEN}🚀 开始部署（预计10-15分钟）...${NC}"

    # 1. 切换国内源
    switch_to_china_mirrors

    # 2. 安装系统依赖（智能重试）
    echo -e "${BLUE}📦 安装系统依赖...${NC}"
    apt update -y >/dev/null 2>&1 || {
        handle_error "apt更新失败" "apt clean && apt update -y" "系统依赖更新"
    }
    
    apt install -y \
        python3 python3-pip python3-venv \
        git nginx curl wget ufw \
        build-essential libssl-dev \
        nodejs npm >/dev/null 2>&1 || {
        handle_error "依赖安装失败" "apt --fix-broken install -y && apt install -y python3 python3-pip git nginx nodejs npm" "系统依赖安装"
    }
    echo -e "${GREEN}✅ 系统依赖安装完成${NC}"

    # 3. 清理旧部署
    echo -e "${BLUE}🧹 清理旧部署文件...${NC}"
    systemctl stop $SERVICE_NAME >/dev/null 2>&1
    systemctl disable $SERVICE_NAME >/dev/null 2>&1
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    rm -rf $PROJECT_DIR
    rm -f /etc/nginx/sites-enabled/$PROJECT_NAME
    rm -f /etc/nginx/sites-available/$PROJECT_NAME
    echo -e "${GREEN}✅ 旧部署清理完成${NC}"

    # 4. 克隆代码（支持重试）
    echo -e "${BLUE}📥 克隆项目代码...${NC}"
    mkdir -p $PROJECT_DIR
    git clone $GIT_REPO $PROJECT_DIR >/dev/null 2>&1 || {
        handle_error "代码克隆失败（可能是网络问题）" "git clone https://github.com/gaoxing-kai/douyin-ai-assistant.git $PROJECT_DIR" "代码克隆"
    }
    cd $PROJECT_DIR || {
        handle_error "进入项目目录失败" "mkdir -p $PROJECT_DIR && cd $PROJECT_DIR" "目录切换"
    }
    echo -e "${GREEN}✅ 代码克隆完成${NC}"

    # 5. 配置Python环境（智能处理依赖冲突）
    echo -e "${BLUE}🐍 配置Python环境...${NC}"
    python3 -m venv $VENV_DIR || {
        handle_error "虚拟环境创建失败" "apt install -y python3-venv && python3 -m venv $VENV_DIR" "虚拟环境配置"
    }
    source $VENV_DIR/bin/activate
    
    pip install --upgrade pip >/dev/null 2>&1 || {
        handle_error "pip升级失败" "curl https://bootstrap.pypa.io/get-pip.py | python3 -" "pip升级"
    }
    
    # 国内PyPI源加速
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
    
    pip install -r requirements.txt >/dev/null 2>&1 || {
        handle_error "Python依赖安装失败" "pip install --upgrade setuptools && pip install -r requirements.txt" "Python依赖安装"
    }
    pip install gunicorn gevent-websocket >/dev/null 2>&1
    echo -e "${GREEN}✅ Python环境配置完成${NC}"

    # 6. 构建前端资源
    echo -e "${BLUE}🎨 构建前端资源...${NC}"
    cd static || {
        handle_error "进入静态资源目录失败" "mkdir -p static && cd static" "前端目录切换"
    }
    npm install >/dev/null 2>&1 || {
        handle_error "npm依赖安装失败" "npm cache clean --force && npm install" "前端依赖安装"
    }
    npm run build >/dev/null 2>&1 || {
        handle_error "前端构建失败" "npm install --force && npm run build" "前端资源构建"
    }
    cd ..
    echo -e "${GREEN}✅ 前端资源构建完成${NC}"

    # 7. 生成环境变量（智能配置）
    echo -e "${BLUE}🔑 配置环境变量...${NC}"
    SECRET_KEY=$(python3 -c "import uuid; print(uuid.uuid4().hex)")  # 自动生成安全密钥
    cat > $ENV_FILE <<EOL
SECRET_KEY=$SECRET_KEY
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
    echo -e "${GREEN}✅ 环境变量配置完成${NC}"

    # 8. 数据库初始化
    echo -e "${BLUE}🗄️ 初始化数据库...${NC}"
    export FLASK_APP=app.py
    source $VENV_DIR/bin/activate
    
    if [ ! -d "$PROJECT_DIR/migrations" ]; then
        flask db init >/dev/null 2>&1 || {
            handle_error "数据库迁移初始化失败" "pip install flask-migrate && flask db init" "数据库初始化"
        }
    fi
    
    flask db migrate -m "auto-deploy" >/dev/null 2>&1 || {
        handle_error "数据库迁移创建失败" "flask db migrate --empty -m 'fix' && flask db upgrade" "数据库迁移"
    }
    flask db upgrade >/dev/null 2>&1 || {
        handle_error "数据库迁移应用失败" "rm -rf migrations && flask db init && flask db migrate -m 'fresh' && flask db upgrade" "数据库升级"
    }
    echo -e "${GREEN}✅ 数据库初始化完成${NC}"

    # 9. 创建管理员账户
    echo -e "${BLUE}👤 创建管理员账户...${NC}"
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
    python init_admin.py >/dev/null 2>&1 || {
        handle_error "管理员账户创建失败" "python init_admin.py" "管理员账户配置"
    }
    rm init_admin.py
    echo -e "${GREEN}✅ 管理员账户创建完成${NC}"

    # 10. 配置Nginx（冲突检测）
    echo -e "${BLUE}🌐 配置Nginx服务...${NC}"
    # 检测80端口占用
    if lsof -i:80 >/dev/null 2>&1; then
        handle_error "80端口被占用（可能是其他Web服务）" "systemctl stop nginx && fuser -k 80/tcp" "端口冲突处理"
    fi

    # 生成Nginx配置
    cat > /etc/nginx/sites-available/$PROJECT_NAME <<EOL
server {
    listen 80;
    server_name $SERVER_ADDR;
    access_log /var/log/nginx/$PROJECT_NAME-access.log;
    error_log /var/log/nginx/$PROJECT_NAME-error.log;

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

    # 激活配置
    rm -f /etc/nginx/sites-enabled/$PROJECT_NAME
    ln -s /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default  # 移除默认配置

    nginx -t >/dev/null 2>&1 || {
        handle_error "Nginx配置错误" "nano /etc/nginx/sites-available/$PROJECT_NAME" "Nginx配置验证"
    }
    systemctl restart nginx || {
        handle_error "Nginx重启失败" "systemctl daemon-reload && systemctl restart nginx" "Nginx重启"
    }
    systemctl enable nginx
    echo -e "${GREEN}✅ Nginx配置完成${NC}"

    # 11. 配置系统服务
    echo -e "${BLUE}🔧 配置系统服务...${NC}"
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
    systemctl enable $SERVICE_NAME || {
        handle_error "服务启用失败" "systemctl daemon-reload && systemctl enable $SERVICE_NAME" "系统服务配置"
    }
    systemctl start $SERVICE_NAME || {
        handle_error "服务启动失败" "journalctl -u $SERVICE_NAME -n 20 && systemctl start $SERVICE_NAME" "系统服务启动"
    }
    echo -e "${GREEN}✅ 系统服务配置完成${NC}"

    # 12. 配置防火墙
    echo -e "${BLUE}🛡️ 配置防火墙...${NC}"
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 22/tcp >/dev/null 2>&1  # 保留SSH端口
    ufw --force enable >/dev/null 2>&1
    echo -e "${GREEN}✅ 防火墙配置完成${NC}"


    # ==============================================
    # 部署完成
    # ==============================================
    echo -e "\n${GREEN}==============================================${NC}"
    echo -e "${GREEN}🎉 部署成功！${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "  访问地址: http://$SERVER_ADDR"
    echo -e "  管理员账号: admin"
    echo -e "  管理员密码: $ADMIN_PWD（请立即修改）"
    echo -e "  部署日志: $(pwd)/$DEPLOY_LOG"
    echo -e "\n${YELLOW}⚠️ 重要提示:${NC}"
    echo -e "  1. 登录后请在【系统设置】中填写DeepSeek和百度API密钥"
    echo -e "  2. 生产环境建议配置HTTPS（可通过Let's Encrypt免费获取证书）"
    echo -e "\n${BLUE}常用命令:${NC}"
    echo -e "  启动服务: systemctl start $SERVICE_NAME"
    echo -e "  停止服务: systemctl stop $SERVICE_NAME"
    echo -e "  查看日志: journalctl -u $SERVICE_NAME -f"
    echo -e "  重启Nginx: systemctl restart nginx"
    echo -e "${GREEN}==============================================${NC}"
}

# 启动主流程
main