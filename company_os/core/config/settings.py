"""
Company OS Configuration Settings.

Environment-based configuration with validation.
"""

from pydantic_settings import BaseSettings
from pydantic import Field
from typing import Optional
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Application
    app_name: str = "Company OS"
    app_version: str = "0.1.0"
    debug: bool = False
    environment: str = "development"

    # Database
    database_url: str = Field(
        default="postgresql://company_os:dev_password@localhost:5432/company_os",
        description="PostgreSQL connection URL"
    )
    database_pool_size: int = 10
    database_max_overflow: int = 20

    # Redis
    redis_url: str = Field(
        default="redis://localhost:6379",
        description="Redis connection URL"
    )

    # Authentication
    jwt_secret_key: str = Field(
        default="dev-secret-change-in-production",
        description="Secret key for JWT signing"
    )
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 7

    # GitHub OAuth
    github_client_id: Optional[str] = None
    github_client_secret: Optional[str] = None
    github_redirect_uri: str = "http://localhost:8000/api/auth/github/callback"

    # Embedding Service
    embedding_provider: str = "openai"  # openai, sentence-transformers
    openai_api_key: Optional[str] = None
    embedding_model: str = "text-embedding-3-small"
    embedding_dimensions: int = 1536

    # UWS Integration
    uws_root: str = Field(
        default="/home/lab2208/Documents/universal-workflow-system",
        description="Root directory of UWS"
    )

    # Server
    host: str = "0.0.0.0"
    port: int = 8000

    # CORS
    cors_origins: list[str] = ["http://localhost:3000", "http://localhost:8080"]

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
