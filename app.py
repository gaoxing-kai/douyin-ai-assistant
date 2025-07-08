from flask import Flask, render_template, request, jsonify, session, redirect, url_for
from flask_socketio import SocketIO, emit
from flask_sqlalchemy import SQLAlchemy
import requests
import json
import base64
import threading
import time
import uuid

app = Flask(__name__)
app.config['SECRET_KEY'] = 'your_secret_key_here'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///site.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# 初始化扩展
db = SQLAlchemy(app)
socketio = SocketIO(app)

# 数据库模型
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password = db.Column(db.String(100), nullable=False)
    is_admin = db.Column(db.Boolean, default=False)

class APIKey(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.String(50), unique=True, nullable=False)
    is_used = db.Column(db.Boolean, default=False)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    
class Setting(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    live_url = db.Column(db.String(200))
    prompt = db.Column(db.Text, default="你是一个专业的直播助手，请用简洁的语言回复观众的问题")
    voice_style = db.Column(db.String(50), default="知性女声")

# 模拟抖音直播间评论采集
def simulate_douyin_comments():
    comments = [
        "这个产品怎么用？",
        "主播好漂亮！",
        "价格能再优惠点吗？",
        "发货地是哪里？",
        "有没有售后服务？",
        "买过的朋友觉得怎么样？",
        "主播能演示一下吗？",
        "今天有什么特别优惠？",
        "适合送人吗？",
        "质量怎么样？"
    ]
    
    while True:
        if 'live_active' in session and session['live_active']:
            comment = {
                "user": f"观众{int(time.time() % 1000)}",
                "content": comments[int(time.time()) % len(comments)],
                "timestamp": time.strftime("%H:%M:%S")
            }
            socketio.emit('new_comment', comment, room=session['room'])
            time.sleep(5)  # 每5秒模拟一条评论
        else:
            time.sleep(1)

# 启动模拟评论线程
threading.Thread(target=simulate_douyin_comments, daemon=True).start()

# 调用DeepSeek API进行分析
def analyze_with_deepseek(comment, prompt):
    # 这里使用模拟响应，实际应用中替换为真实API调用
    responses = [
        "感谢您的提问！这款产品使用非常简单，只需三步操作即可。",
        "谢谢夸奖！今天我们的重点是给大家带来优质的产品介绍。",
        "今天的价格已经是最大优惠了，直播间专享价哦！",
        "我们是从浙江杭州发货，全国大部分地区2-3天可达。",
        "我们提供7天无理由退换货和1年质保服务。",
        "这款产品复购率很高，很多老顾客都反馈使用效果很好。",
        "稍后我会为大家详细演示产品使用方法。",
        "今天下单的前100名观众会额外赠送精美礼品！",
        "这款产品包装精美，非常适合作为礼物赠送。",
        "我们产品采用优质材料制造，质量有保证，请放心购买。"
    ]
    return responses[hash(comment) % len(responses)]

# 调用百度语音合成
def text_to_speech(text, voice_style):
    # 这里使用模拟响应，实际应用中替换为真实API调用
    # 生成一个模拟的语音数据URL
    return f"data:audio/mp3;base64,{base64.b64encode(b'simulated_audio_data').decode('utf-8')}"

# 路由定义
@app.route('/')
def index():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    return redirect(url_for('dashboard'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        user = User.query.filter_by(username=username, password=password).first()
        if user:
            session['user_id'] = user.id
            session['username'] = user.username
            session['is_admin'] = user.is_admin
            return redirect(url_for('dashboard'))
        return render_template('login.html', error="用户名或密码错误")
    return render_template('login.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        key = request.form['key']
        
        # 检查卡密有效性
        apikey = APIKey.query.filter_by(key=key, is_used=False).first()
        if not apikey:
            return render_template('register.html', error="无效的卡密")
        
        # 创建用户
        if User.query.filter_by(username=username).first():
            return render_template('register.html', error="用户名已存在")
        
        new_user = User(username=username, password=password)
        db.session.add(new_user)
        db.session.flush()  # 获取新用户ID
        
        # 标记卡密已使用
        apikey.is_used = True
        apikey.user_id = new_user.id
        
        # 创建默认设置
        default_setting = Setting(user_id=new_user.id)
        db.session.add(default_setting)
        
        db.session.commit()
        
        session['user_id'] = new_user.id
        session['username'] = new_user.username
        session['is_admin'] = new_user.is_admin
        return redirect(url_for('dashboard'))
    
    return render_template('register.html')

@app.route('/dashboard')
def dashboard():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    
    setting = Setting.query.filter_by(user_id=session['user_id']).first()
    return render_template('dashboard.html', setting=setting)

@app.route('/settings', methods=['GET', 'POST'])
def settings():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    
    setting = Setting.query.filter_by(user_id=session['user_id']).first()
    
    if request.method == 'POST':
        setting.live_url = request.form['live_url']
        setting.prompt = request.form['prompt']
        setting.voice_style = request.form['voice_style']
        db.session.commit()
        return jsonify({"status": "success", "message": "设置已更新"})
    
    return render_template('settings.html', setting=setting)

@app.route('/users')
def users():
    if 'user_id' not in session or not session['is_admin']:
        return redirect(url_for('dashboard'))
    
    users = User.query.all()
    return render_template('users.html', users=users)

@app.route('/keys', methods=['GET', 'POST'])
def keys():
    if 'user_id' not in session or not session['is_admin']:
        return redirect(url_for('dashboard'))
    
    if request.method == 'POST':
        count = int(request.form.get('count', 1))
        new_keys = []
        for _ in range(count):
            key = str(uuid.uuid4()).replace('-', '')[:16]
            new_key = APIKey(key=key)
            db.session.add(new_key)
            new_keys.append(key)
        db.session.commit()
        return render_template('keys.html', new_keys=new_keys)
    
    keys = APIKey.query.all()
    return render_template('keys.html', keys=keys)

@app.route('/start_live')
def start_live():
    if 'user_id' not in session:
        return jsonify({"status": "error", "message": "请先登录"})
    
    session['live_active'] = True
    session['room'] = f"room_{session['user_id']}"
    return jsonify({"status": "success", "message": "直播间已启动"})

@app.route('/stop_live')
def stop_live():
    if 'user_id' in session:
        session.pop('live_active', None)
        session.pop('room', None)
    return jsonify({"status": "success", "message": "直播间已停止"})

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

# WebSocket事件处理
@socketio.on('connect')
def handle_connect():
    if 'user_id' in session and 'room' in session:
        session['sid'] = request.sid
        socketio.emit('system_message', {'message': '已连接到直播间'}, room=request.sid)

@socketio.on('disconnect')
def handle_disconnect():
    if 'user_id' in session:
        session.pop('sid', None)

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
        
        # 创建初始管理员用户
        if not User.query.first():
            admin = User(username='admin', password='admin', is_admin=True)
            db.session.add(admin)
            db.session.commit()
            
            # 创建管理员设置
            admin_setting = Setting(user_id=admin.id)
            db.session.add(admin_setting)
            
            # 创建一些初始卡密
            for _ in range(5):
                key = APIKey(key=str(uuid.uuid4()).replace('-', '')[:16])
                db.session.add(key)
            
            db.session.commit()
    
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)