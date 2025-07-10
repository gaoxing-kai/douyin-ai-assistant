import os
from datetime import timedelta
from dotenv import load_dotenv

# 加载环境变量
load_dotenv()

class Config:
    """基础配置类"""
    # Flask核心配置
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev_key_change_in_production')
    SESSION_COOKIE_SECURE = os.getenv('FLASK_ENV') == 'production'
    PERMANENT_SESSION_LIFETIME = timedelta(hours=24)
    
    # 数据库配置
    SQLALCHEMY_DATABASE_URI = os.getenv('DATABASE_URI', 'sqlite:///site.db')
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        'pool_recycle': 300,
        'pool_pre_ping': True
    }
    
    # 第三方API配置
    DEEPSEEK_API_KEY = os.getenv('DEEPSEEK_API_KEY', '')
    DEEPSEEK_API_URL = os.getenv('DEEPSEEK_API_URL', 'https://api.deepseek.com/v1/chat/completions')
    DEEPSEEK_MODEL = os.getenv('DEEPSEEK_MODEL', 'deepseek-chat')
    
    BAIDU_APP_ID = os.getenv('BAIDU_APP_ID', '')
    BAIDU_API_KEY = os.getenv('BAIDU_API_KEY', '')
    BAIDU_SECRET_KEY = os.getenv('BAIDU_SECRET_KEY', '')
    
    # 系统配置
    DEBUG = os.getenv('FLASK_ENV') == 'development'
    MAX_COMMENT_HISTORY = 1000
    AI_REPLY_TIMEOUT = 10
    COMMENT_FETCH_INTERVAL = 5
    
    # 日志配置
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    LOG_FILE = os.getenv('LOG_FILE', 'app.log')

class DevelopmentConfig(Config):
    """开发环境配置"""
    DEBUG = True
    SQLALCHEMY_ECHO = True  # 打印SQL语句
    LOG_LEVEL = 'DEBUG'

class ProductionConfig(Config):
    """生产环境配置"""
    DEBUG = False
    # 生产环境强制要求设置密钥
    if not os.getenv('SECRET_KEY'):
        raise ValueError("生产环境必须设置SECRET_KEY环境变量")
    LOG_LEVEL = 'WARNING'

# 配置映射
config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'default': ProductionConfig
}

# 激活当前配置
active_config = config[os.getenv('FLASK_ENV', 'default')]