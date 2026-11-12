"""Application configuration loaded from environment variables."""

import os

from dotenv import load_dotenv

load_dotenv()


class Config:
    """Default configuration. Database URL must point to the existing MySQL schema."""

    SECRET_KEY = os.getenv("SECRET_KEY", "dev-secret-change-me")
    SQLALCHEMY_DATABASE_URI = SQLALCHEMY_DATABASE_URI = 'mysql+pymysql://root:votre_mot_de_passe@localhost/resource_db'
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True}
    WTF_CSRF_ENABLED = True
    PER_PAGE = 10
