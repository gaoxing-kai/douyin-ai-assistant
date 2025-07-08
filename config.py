import os
from datetime import timedelta
from dotenv import load_dotenv

# 加载环境变量（优先从.env文件读取）
load_dotenv()

class Config:
    """基础配置类"""
    # Flask核心配置
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev_secret_key_123')  # 生产环境必须更换
    SESSION_COOKIE_SECURE = os.getenv('FLASK_ENV', 'production') == 'production'  # 生产环境启用HTTPS cookie
    PERMANENT_SESSION_LIFETIME = timedelta(hours=24)  # 会话有效期24小时

    # 数据库配置
    SQLALCHEMY_DATABASE_URI = os.getenv(
        'DATABASE_URI', 
        'sqlite:///site.db'  # 默认使用SQLite，生产环境建议更换为MySQL
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False  # 关闭修改跟踪，提升性能
    SQLALCHEMY_ENGINE_OPTIONS = {
        'pool_recycle': 300,  # 连接池回收时间（秒）
        'pool_pre_ping': True  # 连接前检查有效性
    }

    # 第三方API配置
    # DeepSeek AI（评论分析）
    DEEPSEEK_API_KEY = os.getenv('DEEPSEEK_API_KEY', '')
    DEEPSEEK_API_URL = os.getenv('DEEPSEEK_API_URL', 'https://api.deepseek.com/v1/chat/completions')
    DEEPSEEK_MODEL = os.getenv('DEEPSEEK_MODEL', 'deepseek-chat')

    # 百度语音合成
    BAIDU_APP_ID = os.getenv('BAIDU_APP_ID', '')
    BAIDU_API_KEY = os.getenv('BAIDU_API_KEY', '')
    BAIDU_SECRET_KEY = os.getenv('BAIDU_SECRET_KEY', '')
    BAIDU_TTS_SPEED = int(os.getenv('BAIDU_TTS_SPEED', 5))  # 语速（0-15）
    BAIDU_TTS_VOLUME = int(os.getenv('BAIDU_TTS_VOLUME', 5))  # 音量（0-15）

    # 系统行为配置
    DEBUG = os.getenv('FLASK_ENV', 'production') == 'development'  # 开发模式开关
    MAX_COMMENT_HISTORY = 1000  # 最大评论历史缓存数
    AI_REPLY_TIMEOUT = 10  # AI回复超时时间（秒）
    COMMENT_FETCH_INTERVAL = 5  # 默认评论采集间隔（秒）

    # 日志配置
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    LOG_FILE = os.getenv('LOG_FILE', 'app.log')


class DevelopmentConfig(Config):
    """开发环境配置（继承基础配置并覆盖）"""
    DEBUG = True
    SQLALCHEMY_ECHO = True  # 打印SQL语句，便于调试
    LOG_LEVEL = 'DEBUG'


class ProductionConfig(Config):
    """生产环境配置"""
    DEBUG = False
    # 生产环境强制要求设置密钥
    SECRET_KEY = os.getenv('SECRET_KEY')
    if not SECRET_KEY:
        raise ValueError("生产环境必须设置SECRET_KEY环境变量")
    LOG_LEVEL = 'WARNING'  # 生产环境减少日志输出


# 配置映射，便于根据环境变量切换配置
config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'default': ProductionConfig
}

# 根据环境变量选择配置
active_config = config[os.getenv('FLASK_ENV', 'default')]