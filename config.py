import os
from dotenv import load_dotenv

# 加载环境变量
load_dotenv()

class Config:
    # 基础配置
    SECRET_KEY = os.getenv('SECRET_KEY', 'your_secret_key_here')
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # 数据库配置
    DB_TYPE = os.getenv('DB_TYPE', 'sqlite')
    
    if DB_TYPE == 'mysql':
        SQLALCHEMY_DATABASE_URI = (
            f"mysql+pymysql://{os.getenv('MYSQL_USER')}:{os.getenv('MYSQL_PASSWORD')}"
            f"@{os.getenv('MYSQL_HOST')}:{os.getenv('MYSQL_PORT', '3306')}"
            f"/{os.getenv('MYSQL_DATABASE')}"
        )
    elif DB_TYPE == 'postgres':
        SQLALCHEMY_DATABASE_URI = (
            f"postgresql://{os.getenv('POSTGRES_USER')}:{os.getenv('POSTGRES_PASSWORD')}"
            f"@{os.getenv('POSTGRES_HOST')}:{os.getenv('POSTGRES_PORT', '5432')}"
            f"/{os.getenv('POSTGRES_DB')}"
        )
    else:
        SQLALCHEMY_DATABASE_URI = 'sqlite:///site.db'
    
    # WebSocket 配置
    SOCKETIO_MESSAGE_QUEUE = os.getenv('SOCKETIO_MESSAGE_QUEUE', 'redis://localhost:6379/0')
    
    # DeepSeek AI 配置
    DEEPSEEK_API_KEY = os.getenv('DEEPSEEK_API_KEY', 'your_deepseek_api_key')
    DEEPSEEK_API_BASE = os.getenv('DEEPSEEK_API_BASE', 'https://api.deepseek.com/v1')
    DEEPSEEK_MODEL = os.getenv('DEEPSEEK_MODEL', 'deepseek-chat')
    DEFAULT_PROMPT = os.getenv('DEFAULT_PROMPT', '你是一个专业的直播助手，请用简洁的语言回复观众的问题')
    
    # 百度语音配置
    BAIDU_APP_ID = os.getenv('BAIDU_APP_ID', 'your_baidu_app_id')
    BAIDU_API_KEY = os.getenv('BAIDU_API_KEY', 'your_baidu_api_key')
    BAIDU_SECRET_KEY = os.getenv('BAIDU_SECRET_KEY', 'your_baidu_secret_key')
    DEFAULT_VOICE_STYLE = os.getenv('DEFAULT_VOICE_STYLE', '知性女声')
    
    # 抖音配置
    DOUYIN_API_BASE = os.getenv('DOUYIN_API_BASE', 'https://live.douyin.com')
    DOUYIN_MONITOR_INTERVAL = int(os.getenv('DOUYIN_MONITOR_INTERVAL', '5'))  # 秒
    
    # 安全配置
    LOGIN_FAILURE_LIMIT = int(os.getenv('LOGIN_FAILURE_LIMIT', '5'))
    LOGIN_LOCK_TIME = int(os.getenv('LOGIN_LOCK_TIME', '300'))  # 秒
    AUTO_LOGOUT_TIME = int(os.getenv('AUTO_LOGOUT_TIME', '30'))  # 分钟
    
    # 管理员配置
    ADMIN_USERNAME = os.getenv('ADMIN_USERNAME', 'admin')
    ADMIN_PASSWORD = os.getenv('ADMIN_PASSWORD', 'admin')
    
    # 性能配置
    WORKER_THREADS = int(os.getenv('WORKER_THREADS', '4'))
    MAX_CONTENT_LENGTH = int(os.getenv('MAX_CONTENT_LENGTH', '16 * 1024 * 1024'))  # 16MB
    
    # 调试配置
    DEBUG = os.getenv('DEBUG', 'False').lower() in ('true', '1', 't')
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    
    # 文件存储配置
    UPLOAD_FOLDER = os.getenv('UPLOAD_FOLDER', 'uploads')
    MAX_AUDIO_FILES = int(os.getenv('MAX_AUDIO_FILES', '100'))
    
    # 备份配置
    BACKUP_DIR = os.getenv('BACKUP_DIR', 'backups')
    BACKUP_FREQUENCY = os.getenv('BACKUP_FREQUENCY', 'daily')  # daily, weekly, monthly
    
    # 邮箱配置（用于通知）
    MAIL_SERVER = os.getenv('MAIL_SERVER', 'smtp.example.com')
    MAIL_PORT = int(os.getenv('MAIL_PORT', '587'))
    MAIL_USE_TLS = os.getenv('MAIL_USE_TLS', 'True').lower() in ('true', '1', 't')
    MAIL_USERNAME = os.getenv('MAIL_USERNAME', 'your_email@example.com')
    MAIL_PASSWORD = os.getenv('MAIL_PASSWORD', 'your_email_password')
    MAIL_DEFAULT_SENDER = os.getenv('MAIL_DEFAULT_SENDER', 'noreply@example.com')
    
    # Redis配置（用于缓存和消息队列）
    REDIS_URL = os.getenv('REDIS_URL', 'redis://localhost:6379/0')
    
    # Celery配置（用于异步任务）
    CELERY_BROKER_URL = os.getenv('CELERY_BROKER_URL', 'redis://localhost:6379/0')
    CELERY_RESULT_BACKEND = os.getenv('CELERY_RESULT_BACKEND', 'redis://localhost:6379/0')
    
    # 跨域配置
    CORS_ORIGINS = os.getenv('CORS_ORIGINS', '').split(',') or ['*']
    
    # 自定义配置
    APP_NAME = os.getenv('APP_NAME', '抖音直播间AI助手')
    APP_VERSION = os.getenv('APP_VERSION', '1.0.0')
    COMPANY_NAME = os.getenv('COMPANY_NAME', 'AI科技有限公司')
    
    # 主题配置
    THEME_COLOR = os.getenv('THEME_COLOR', '#8a2be2')
    SECONDARY_COLOR = os.getenv('SECONDARY_COLOR', '#00c3ff')
    
    @staticmethod
    def init_app(app):
        # 创建必要的目录
        for directory in [Config.UPLOAD_FOLDER, Config.BACKUP_DIR]:
            if not os.path.exists(directory):
                os.makedirs(directory)

class DevelopmentConfig(Config):
    DEBUG = True
    SQLALCHEMY_ECHO = True
    LOG_LEVEL = 'DEBUG'

class TestingConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    WTF_CSRF_ENABLED = False

class ProductionConfig(Config):
    DEBUG = False
    LOG_LEVEL = 'WARNING'

config = {
    'development': DevelopmentConfig,
    'testing': TestingConfig,
    'production': ProductionConfig,
    'default': DevelopmentConfig
}