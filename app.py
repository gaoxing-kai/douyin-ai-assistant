import os
import traceback
import logging
from logging.handlers import RotatingFileHandler
from flask import Flask, render_template, request, jsonify, session, redirect, url_for
from flask_socketio import SocketIO
from flask_sqlalchemy import SQLAlchemy
from dotenv import load_dotenv
import requests
import json
import base64
import threading
import time
import uuid
from datetime import datetime

# 加载环境变量
load_dotenv()

# 创建Flask应用
app = Flask(__name__)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'fallback_secret_key')

# 配置日志
def setup_logging():
    log_dir = 'logs'
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
    
    # 错误日志
    error_handler = RotatingFileHandler(
        'logs/error.log', maxBytes=1000000, backupCount=5
    )
    error_handler.setLevel(logging.ERROR)
    error_handler.setFormatter(logging.Formatter(
        '%(asctime)s %(levelname)s: %(message)s [in %(pathname)s:%(lineno)d]'
    ))
    
    # 访问日志
    access_handler = RotatingFileHandler(
        'logs/access.log', maxBytes=1000000, backupCount=5
    )
    access_handler.setLevel(logging.INFO)
    access_handler.setFormatter(logging.Formatter(
        '%(asctime)s %(levelname)s: %(message)s'
    ))
    
    # 应用日志
    app_handler = RotatingFileHandler(
        'logs/app.log', maxBytes=1000000, backupCount=5
    )
    app_handler.setLevel(logging.DEBUG)
    app_handler.setFormatter(logging.Formatter(
        '%(asctime)s %(levelname)s: %(message)s [in %(pathname)s:%(lineno)d]'
    ))
    
    # 添加处理器
    app.logger.addHandler(error_handler)
    app.logger.addHandler(access_handler)
    app.logger.addHandler(app_handler)
    app.logger.setLevel(logging.DEBUG)

setup_logging()

# 数据库配置
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('SQLALCHEMY_DATABASE_URI', 'sqlite:///site.db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# 初始化扩展
db = SQLAlchemy(app)
socketio = SocketIO(app, async_mode='eventlet', logger=True, engineio_logger=True)

# 错误处理
@app.errorhandler(404)
def not_found_error(error):
    app.logger.error(f'404 Error: {error}')
    return render_template('404.html'), 404

@app.errorhandler(500)
def internal_error(error):
    app.logger.error(f'500 Error: {error}\n{traceback.format_exc()}')
    return render_template('500.html', error=traceback.format_exc()), 500

# 数据库模型
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password = db.Column(db.String(100), nullable=False)
    is_admin = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

class APIKey(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.String(50), unique=True, nullable=False)
    is_used = db.Column(db.Boolean, default=False)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
class Setting(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    live_url = db.Column(db.String(200))
    prompt = db.Column(db.Text, default="你是一个专业的直播助手，请用简洁的语言回复观众的问题")
    voice_style = db.Column(db.String(50), default="知性女声")
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

# 初始化数据库
def init_db():
    with app.app_context():
        try:
            db.create_all()
            app.logger.info("数据库初始化成功")
            
            # 创建初始管理员用户
            if not User.query.first():
                admin = User(username='admin', password='admin', is_admin=True)
                db.session.add(admin)
                db.session.commit()
                app.logger.info("管理员用户已创建")
                
                # 创建管理员设置
                admin_setting = Setting(user_id=admin.id)
                db.session.add(admin_setting)
                
                # 创建一些初始卡密
                for _ in range(5):
                    key = APIKey(key=str(uuid.uuid4()).replace('-', '')[:16])
                    db.session.add(key)
                
                db.session.commit()
                app.logger.info("初始数据已创建")
        except Exception as e:
            app.logger.error(f"数据库初始化失败: {e}\n{traceback.format_exc()}")
            raise

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
        try:
            if 'live_active' in session and session['live_active']:
                comment = {
                    "user": f"观众{int(time.time() % 1000)}",
                    "content": comments[int(time.time()) % len(comments)],
                    "timestamp": time.strftime("%H:%M:%S")
                }
                socketio.emit('new_comment', comment, room=session['room'])
                app.logger.debug(f"模拟评论: {comment}")
                time.sleep(5)  # 每5秒模拟一条评论
            else:
                time.sleep(1)
        except Exception as e:
            app.logger.error(f"评论模拟错误: {e}")
            time.sleep(5)

# 启动模拟评论线程
threading.Thread(target=simulate_douyin_comments, daemon=True).start()

# 调用DeepSeek API进行分析
def analyze_with_deepseek(comment, prompt):
    try:
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
        response = responses[hash(comment) % len(responses)]
        app.logger.info(f"AI回复: {response}")
        return response
    except Exception as e:
        app.logger.error(f"AI分析错误: {e}")
        return "感谢您的评论！我们会尽快回复。"

# 调用百度语音合成
def text_to_speech(text, voice_style):
    try:
        # 这里使用模拟响应，实际应用中替换为真实API调用
        # 生成一个模拟的语音数据URL
        app.logger.info(f"语音合成: {text} (音色: {voice_style})")
        return f"data:audio/mp3;base64,{base64.b64encode(b'simulated_audio_data').decode('utf-8')}"
    except Exception as e:
        app.logger.error(f"语音合成错误: {e}")
        return ""

# 路由定义
@app.route('/')
def index():
    try:
        if 'user_id' not in session:
            return redirect(url_for('login'))
        return redirect(url_for('dashboard'))
    except Exception as e:
        app.logger.error(f"首页错误: {e}")
        return render_template('500.html', error=str(e)), 500

@app.route('/login', methods=['GET', 'POST'])
def login():
    try:
        if request.method == 'POST':
            username = request.form['username']
            password = request.form['password']
            user = User.query.filter_by(username=username, password=password).first()
            if user:
                session['user_id'] = user.id
                session['username'] = user.username
                session['is_admin'] = user.is_admin
                app.logger.info(f"用户登录: {username}")
                return redirect(url_for('dashboard'))
            app.logger.warning(f"登录失败: {username}")
            return render_template('login.html', error="用户名或密码错误")
        return render_template('login.html')
    except Exception as e:
        app.logger.error(f"登录错误: {e}")
        return render_template('500.html', error=str(e)), 500

@app.route('/register', methods=['GET', 'POST'])
def register():
    try:
        if request.method == 'POST':
            username = request.form['username']
            password = request.form['password']
            key = request.form['key']
            
            # 检查卡密有效性
            apikey = APIKey.query.filter_by(key=key, is_used=False).first()
            if not apikey:
                app.logger.warning(f"无效卡密: {key}")
                return render_template('register.html', error="无效的卡密")
            
            # 创建用户
            if User.query.filter_by(username=username).first():
                app.logger.warning(f"用户名已存在: {username}")
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
            app.logger.info(f"新用户注册: {username}")
            
            session['user_id'] = new_user.id
            session['username'] = new_user.username
            session['is_admin'] = new_user.is_admin
            return redirect(url_for('dashboard'))
        
        return render_template('register.html')
    except Exception as e:
        app.logger.error(f"注册错误: {e}")
        return render_template('500.html', error=str(e)), 500

@app.route('/dashboard')
def dashboard():
    try:
        if 'user_id' not in session:
            return redirect(url_for('login'))
        
        setting = Setting.query.filter_by(user_id=session['user_id']).first()
        return render_template('dashboard.html', setting=setting)
    except Exception as e:
        app.logger.error(f"控制面板错误: {e}")
        return render_template('500.html', error=str(e)), 500

@app.route('/settings', methods=['GET', 'POST'])
def settings():
    try:
        if 'user_id' not in session:
            return redirect(url_for('login'))
        
        setting = Setting.query.filter_by(user_id=session['user_id']).first()
        
        if request.method == 'POST':
            setting.live_url = request.form['live_url']
            setting.prompt = request.form['prompt']
            setting.voice_style = request.form['voice_style']
            db.session.commit()
            app.logger.info(f"设置更新: 用户ID {session['user_id']}")
            return jsonify({"status": "success", "message": "设置已更新"})
        
        return render_template('settings.html', setting=setting)
    except Exception as e:
        app.logger.error(f"设置错误: {e}")
        return render_template('500.html', error=str(e)), 500

@app.route('/start_live')
def start_live():
    try:
        if 'user_id' not in session:
            return jsonify({"status": "error", "message": "请先登录"})
        
        session['live_active'] = True
        session['room'] = f"room_{session['user_id']}"
        app.logger.info(f"直播间启动: 用户ID {session['user_id']}")
        return jsonify({"status": "success", "message": "直播间已启动"})
    except Exception as e:
        app.logger.error(f"启动直播错误: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/test')
def test_route():
    """测试路由，用于验证应用是否正常运行"""
    try:
        # 测试数据库连接
        users = User.query.limit(5).all()
        user_count = len(users)
        
        # 测试环境变量
        deepseek_key = os.getenv('DEEPSEEK_API_KEY', '未设置')
        
        return jsonify({
            "status": "success",
            "message": "应用运行正常",
            "database": f"连接正常，找到 {user_count} 个用户",
            "deepseek_key": f"{'已设置' if deepseek_key and deepseek_key != 'your_deepseek_api_key_here' else '未配置'}"
        })
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }), 500

if __name__ == '__main__':
    try:
        # 初始化数据库
        init_db()
        
        # 启动应用
        socketio.run(app, host='0.0.0.0', port=5000, debug=True)
    except Exception as e:
        app.logger.critical(f"应用启动失败: {e}\n{traceback.format_exc()}")
        print(f"致命错误: {e}")