import os
import time
import uuid
import requests
import base64
import threading
from datetime import datetime
from flask import (
    Flask, render_template, request, jsonify, 
    session, redirect, url_for, g, current_app
)
from flask_socketio import SocketIO, emit, join_room, leave_room
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from werkzeug.security import generate_password_hash, check_password_hash
from config import active_config

# 初始化应用
app = Flask(__name__)
app.config.from_object(active_config)

# 初始化扩展
db = SQLAlchemy(app)
migrate = Migrate(app, db)  # 数据库迁移工具
socketio = SocketIO(
    app, 
    cors_allowed_origins="*",
    async_mode="gevent",
    ping_timeout=30,
    ping_interval=10
)

# ------------------------------
# 数据库模型
# ------------------------------
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password_hash = db.Column(db.String(128), nullable=False)
    is_admin = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    setting = db.relationship('Setting', backref='user', uselist=False, cascade="all, delete-orphan")
    api_keys = db.relationship('APIKey', backref='user', lazy=True, cascade="all, delete-orphan")

class APIKey(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.String(50), unique=True, nullable=False)
    is_used = db.Column(db.Boolean, default=False)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id', ondelete='SET NULL'), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    used_at = db.Column(db.DateTime)

class Setting(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id', ondelete='CASCADE'), nullable=False)
    live_url = db.Column(db.String(200))
    prompt = db.Column(db.Text, default="你是专业直播助手，简洁回复观众问题")
    voice_style = db.Column(db.String(50), default="知性女声")
    monitor_interval = db.Column(db.Integer, default=5)
    ai_mode = db.Column(db.String(20), default="normal")
    speech_speed = db.Column(db.Integer, default=5)
    volume = db.Column(db.Integer, default=5)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

# ------------------------------
# 全局状态与工具函数
# ------------------------------
live_rooms = {}  # {user_id: {active: bool, room: str, thread: Thread, interval: int}}
room_lock = threading.Lock()

def log(message, level="info"):
    """统一日志输出"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_dir = os.path.dirname(current_app.config['LOG_FILE'])
    if log_dir and not os.path.exists(log_dir):
        os.makedirs(log_dir)
    with open(current_app.config['LOG_FILE'], 'a') as f:
        f.write(f"[{timestamp}] [{level.upper()}] {message}\n")
    if current_app.config['DEBUG']:
        print(f"[{timestamp}] [{level.upper()}] {message}")

# ------------------------------
# 抖音评论采集
# ------------------------------
def fetch_douyin_comments(user_id, room):
    log(f"启动用户{user_id}的评论采集线程")
    comments = [
        "这个产品怎么用？", "价格能优惠吗？", "发货地在哪？",
        "有售后服务吗？", "适合送人吗？", "质量怎么样？",
        "主播能演示下吗？", "今天有什么优惠？", "买过的说说体验"
    ]
    try:
        while True:
            with room_lock:
                active = live_rooms.get(user_id, {}).get('active', False)
                interval = live_rooms.get(user_id, {}).get('interval', 5)
            
            if active:
                comment = {
                    "user": f"观众{int(time.time() % 1000)}",
                    "content": comments[int(time.time()) % len(comments)],
                    "timestamp": time.strftime("%H:%M:%S"),
                    "answered": False
                }
                socketio.emit('new_comment', comment, room=room)
                log(f"用户{user_id}的直播间推送评论: {comment['content']}", "debug")
                time.sleep(interval)
            else:
                time.sleep(1)
    except Exception as e:
        log(f"评论采集线程错误: {str(e)}", "error")

def start_comment_thread(user_id):
    with room_lock:
        if (user_id not in live_rooms 
            or not live_rooms[user_id].get('thread') 
            or not live_rooms[user_id]['thread'].is_alive()):
            
            room = f"room_{user_id}"
            setting = Setting.query.filter_by(user_id=user_id).first()
            interval = setting.monitor_interval if setting else 5
            
            thread = threading.Thread(
                target=fetch_douyin_comments,
                args=(user_id, room),
                name=f"comment_thread_{user_id}",
                daemon=True
            )
            thread.start()
            
            live_rooms[user_id] = {
                'active': True,
                'room': room,
                'thread': thread,
                'interval': interval
            }
            log(f"为用户{user_id}创建新的评论线程")

# ------------------------------
# 第三方服务集成
# ------------------------------
def deepseek_analyze(comment, prompt, ai_mode):
    retry_count = 0
    max_retry = 2
    while retry_count <= max_retry:
        try:
            url = current_app.config['DEEPSEEK_API_URL']
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {current_app.config['DEEPSEEK_API_KEY']}"
            }
            mode_prompt = {
                "normal": "请用简洁明了的语言回复观众问题",
                "professional": "请用专业术语详细解答，突出产品优势",
                "friendly": "请用亲切口语化的方式回复，拉近与观众距离"
            }.get(ai_mode, "请用简洁语言回复")
            
            data = {
                "model": current_app.config['DEEPSEEK_MODEL'],
                "messages": [
                    {"role": "system", "content": f"{prompt}\n补充要求：{mode_prompt}"},
                    {"role": "user", "content": comment}
                ],
                "timeout": current_app.config['AI_REPLY_TIMEOUT']
            }
            
            response = requests.post(
                url, 
                json=data, 
                timeout=current_app.config['AI_REPLY_TIMEOUT'] + 2
            )
            response.raise_for_status()
            return response.json()["choices"][0]["message"]["content"]
        
        except Exception as e:
            retry_count += 1
            log(f"DeepSeek API调用失败（第{retry_count}次重试）: {str(e)}", "error")
            if retry_count > max_retry:
                return f"抱歉，暂时无法回复关于'{comment}'的问题，请稍后再试~"

def baidu_tts(text, voice_style, speed=5, volume=5):
    try:
        from aip import AipSpeech
        client = AipSpeech(
            current_app.config['BAIDU_APP_ID'],
            current_app.config['BAIDU_API_KEY'],
            current_app.config['BAIDU_SECRET_KEY']
        )
        
        voice_mapping = {
            "知性女声": 0, "甜美女生": 1, "成熟男声": 3,
            "磁性男声": 4, "可爱童声": 5
        }
        voice = voice_mapping.get(voice_style, 0)
        
        result = client.synthesis(
            text, 'zh', 1,
            {
                'vol': volume, 
                'spd': speed, 
                'pit': 5, 
                'per': voice
            }
        )
        
        if not isinstance(result, dict):
            return f"data:audio/mp3;base64,{base64.b64encode(result).decode('utf-8')}"
        else:
            log(f"百度TTS错误: {result}", "error")
    except Exception as e:
        log(f"语音合成失败: {str(e)}", "error")
    
    return {
        "type": "text",
        "content": text
    }

# ------------------------------
# 装饰器
# ------------------------------
def login_required(f):
    def wrapper(*args, **kwargs):
        if 'user_id' not in session:
            log("未登录用户尝试访问受保护资源", "warning")
            return redirect(url_for('login', next=request.path))
        return f(*args, **kwargs)
    wrapper.__name__ = f.__name__
    return wrapper

def admin_required(f):
    def wrapper(*args, **kwargs):
        if 'user_id' not in session:
            return redirect(url_for('login'))
        user = User.query.get(session['user_id'])
        if not user or not user.is_admin:
            log(f"用户{session['user_id']}尝试访问管理员资源", "warning")
            return redirect(url_for('dashboard'))
        return f(*args, **kwargs)
    wrapper.__name__ = f.__name__
    return wrapper

# ------------------------------
# 自定义模板过滤器
# ------------------------------
@app.template_filter('datetimeformat')
def datetimeformat(value, format='%Y-%m-%d %H:%M:%S'):
    """格式化日期时间的模板过滤器"""
    if isinstance(value, datetime):
        return value.strftime(format)
    return "未知时间"

# ------------------------------
# 路由
# ------------------------------
@app.route('/')
def index():
    return redirect(url_for('dashboard') if 'user_id' in session else url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        user = User.query.filter_by(username=username).first()
        
        if user and check_password_hash(user.password_hash, password):
            session['user_id'] = user.id
            session['username'] = user.username
            session['is_admin'] = user.is_admin
            log(f"用户{username}登录成功")
            next_url = request.args.get('next', url_for('dashboard'))
            return redirect(next_url)
        else:
            log(f"用户{username}登录失败（密码错误）", "warning")
            return render_template('login.html', error="用户名或密码错误")
    
    return render_template('login.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        confirm_pwd = request.form.get('confirm_password')
        key = request.form.get('key')
        
        if password != confirm_pwd:
            return render_template('register.html', error="两次密码不一致")
        if User.query.filter_by(username=username).first():
            return render_template('register.html', error="用户名已存在")
        
        api_key = APIKey.query.filter_by(key=key, is_used=False).first()
        if not api_key:
            log(f"用户{username}注册失败（无效卡密: {key}）", "warning")
            return render_template('register.html', error="无效或已使用的卡密")
        
        new_user = User(
            username=username,
            password_hash=generate_password_hash(password)
        )
        db.session.add(new_user)
        db.session.flush()
        
        api_key.is_used = True
        api_key.user_id = new_user.id
        api_key.used_at = datetime.utcnow()
        
        db.session.add(Setting(user_id=new_user.id))
        db.session.commit()
        
        log(f"新用户注册成功: {username}")
        return redirect(url_for('login', msg="注册成功，请登录"))
    
    return render_template('register.html')

@app.route('/dashboard')
@login_required
def dashboard():
    user_id = session['user_id']
    setting = Setting.query.filter_by(user_id=user_id).first()
    return render_template('dashboard.html', setting=setting)

@app.route('/settings', methods=['GET', 'POST'])
@login_required
def settings():
    user_id = session['user_id']
    setting = Setting.query.filter_by(user_id=user_id).first()
    
    if request.method == 'POST':
        try:
            setting.live_url = request.form.get('live_url')
            setting.prompt = request.form.get('ai_prompt')
            setting.voice_style = request.form.get('voice_style')
            setting.monitor_interval = int(request.form.get('monitor_interval', 5))
            setting.ai_mode = request.form.get('ai_mode')
            setting.speech_speed = int(request.form.get('speech_speed', 5))
            setting.volume = int(request.form.get('volume', 5))
            db.session.commit()
            
            with room_lock:
                if user_id in live_rooms:
                    live_rooms[user_id]['interval'] = setting.monitor_interval
            
            log(f"用户{user_id}更新了系统设置")
            return jsonify({"status": "success", "msg": "设置已更新"})
        except Exception as e:
            db.session.rollback()
            log(f"用户{user_id}更新设置失败: {str(e)}", "error")
            return jsonify({"status": "error", "msg": "更新失败，请重试"}), 500
    
    return render_template('settings.html', setting=setting)

@app.route('/users', methods=['GET', 'POST', 'DELETE'])
@admin_required
def users():
    if request.method == 'POST':
        try:
            username = request.form.get('username')
            password = request.form.get('password')
            is_admin = request.form.get('is_admin') == 'on'
            
            if User.query.filter_by(username=username).first():
                return jsonify({"status": "error", "msg": "用户名已存在"})
            
            new_user = User(
                username=username,
                password_hash=generate_password_hash(password),
                is_admin=is_admin
            )
            db.session.add(new_user)
            db.session.flush()
            db.session.add(Setting(user_id=new_user.id))
            db.session.commit()
            
            log(f"管理员{session['user_id']}添加了新用户: {username}")
            return jsonify({"status": "success", "msg": "用户添加成功"})
        except Exception as e:
            db.session.rollback()
            log(f"添加用户失败: {str(e)}", "error")
            return jsonify({"status": "error", "msg": "操作失败"}), 500
    
    if request.method == 'DELETE':
        try:
            user_id = request.json.get('user_id')
            if user_id == session['user_id']:
                return jsonify({"status": "error", "msg": "不能删除当前登录用户"})
            
            User.query.filter_by(id=user_id).delete()
            db.session.commit()
            log(f"管理员{session['user_id']}删除了用户: {user_id}")
            return jsonify({"status": "success"})
        except Exception as e:
            db.session.rollback()
            log(f"删除用户失败: {str(e)}", "error")
            return jsonify({"status": "error", "msg": "操作失败"}), 500
    
    users = User.query.order_by(User.created_at.desc()).all()
    return render_template('users.html', users=users)

@app.route('/keys', methods=['GET', 'POST', 'DELETE'])
@admin_required
def keys():
    if request.method == 'POST':
        try:
            count = int(request.form.get('count', 1))
            new_keys = []
            for _ in range(count):
                key = str(uuid.uuid4()).replace('-', '')[:16]
                db.session.add(APIKey(key=key))
                new_keys.append(key)
            db.session.commit()
            log(f"管理员{session['user_id']}生成了{count}个卡密")
            return render_template('keys.html', new_keys=new_keys, keys=APIKey.query.all())
        except Exception as e:
            db.session.rollback()
            log(f"生成卡密失败: {str(e)}", "error")
            return render_template('keys.html', keys=APIKey.query.all(), error="生成失败")
    
    if request.method == 'DELETE':
        try:
            key_id = request.json.get('key_id')
            api_key = APIKey.query.get(key_id)
            if api_key and not api_key.is_used:
                db.session.delete(api_key)
                db.session.commit()
                log(f"管理员{session['user_id']}删除了卡密: {api_key.key}")
                return jsonify({"status": "success"})
            return jsonify({"status": "error", "msg": "只能删除未使用的卡密"})
        except Exception as e:
            db.session.rollback()
            log(f"删除卡密失败: {str(e)}", "error")
            return jsonify({"status": "error", "msg": "操作失败"}), 500
    
    keys = APIKey.query.order_by(APIKey.created_at.desc()).all()
    return render_template('keys.html', keys=keys)

@app.route('/live/start')
@login_required
def start_live():
    user_id = session['user_id']
    try:
        start_comment_thread(user_id)
        with room_lock:
            room = live_rooms[user_id]['room']
        log(f"用户{user_id}启动了直播间: {room}")
        return jsonify({
            "status": "success", 
            "msg": "直播间已启动",
            "room": room
        })
    except Exception as e:
        log(f"用户{user_id}启动直播间失败: {str(e)}", "error")
        return jsonify({"status": "error", "msg": "启动失败，请重试"}), 500

@app.route('/live/stop')
@login_required
def stop_live():
    user_id = session['user_id']
    with room_lock:
        if user_id in live_rooms:
            live_rooms[user_id]['active'] = False
    log(f"用户{user_id}停止了直播间")
    return jsonify({"status": "success", "msg": "直播间已停止"})

@app.route('/logout')
def logout():
    username = session.get('username', '未知用户')
    session.clear()
    log(f"用户{username}退出登录")
    return redirect(url_for('login'))

# ------------------------------
# WebSocket事件
# ------------------------------
@socketio.on('connect')
def handle_connect():
    if 'user_id' not in session:
        emit('system_msg', {"msg": "请先登录", "type": "error"})
        return False
    
    user_id = session['user_id']
    room = live_rooms.get(user_id, {}).get('room', f"room_{user_id}")
    join_room(room)
    emit('system_msg', {
        "msg": "已连接到直播间", 
        "time": time.strftime("%H:%M:%S"),
        "type": "info"
    })
    log(f"用户{user_id}的客户端连接到WebSocket", "debug")

@socketio.on('disconnect')
def handle_disconnect():
    if 'user_id' in session:
        user_id = session['user_id']
        room = live_rooms.get(user_id, {}).get('room')
        if room:
            leave_room(room)
        log(f"用户{user_id}的客户端断开连接", "debug")

@socketio.on('analyze_comment')
def handle_analyze(comment):
    try:
        user_id = session['user_id']
        room = live_rooms.get(user_id, {}).get('room', f"room_{user_id}")
        setting = Setting.query.filter_by(user_id=user_id).first()
        
        if not setting:
            emit('ai_reply', {"error": "未找到系统设置"}, room=room)
            return
        
        def async_analyze():
            ai_reply = deepseek_analyze(comment['content'], setting.prompt, setting.ai_mode)
            audio = baidu_tts(
                ai_reply, 
                setting.voice_style,
                speed=setting.speech_speed,
                volume=setting.volume
            )
            socketio.emit('ai_reply', {
                "user": "AI助手",
                "content": ai_reply,
                "timestamp": time.strftime("%H:%M:%S"),
                "audio_url": audio if isinstance(audio, str) else None,
                "text_fallback": audio.get('content') if isinstance(audio, dict) else None
            }, room=room)
        
        threading.Thread(target=async_analyze, daemon=True).start()
    
    except Exception as e:
        log(f"处理评论分析失败: {str(e)}", "error")
        emit('system_msg', {"msg": "处理评论失败", "type": "error"})

# ------------------------------
# 错误处理
# ------------------------------
@app.errorhandler(404)
def page_not_found(e):
    return render_template('errors/404.html'), 404

@app.errorhandler(500)
def internal_server_error(e):
    log(f"服务器内部错误: {str(e)}", "error")
    return render_template('errors/500.html'), 500

# ------------------------------
# 应用初始化
# ------------------------------
@app.before_first_request
def before_first_request():
    log_dir = os.path.dirname(current_app.config['LOG_FILE'])
    if log_dir and not os.path.exists(log_dir):
        os.makedirs(log_dir)
    log("应用启动初始化完成")

if __name__ == '__main__':
    debug_mode = app.config['DEBUG']
    log(f"应用启动（环境: {'开发' if debug_mode else '生产'}）")
    
    socketio.run(
        app,
        host='0.0.0.0',
        port=5000,
        debug=debug_mode,
        use_reloader=debug_mode
    )