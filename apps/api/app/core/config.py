"""
Application settings — loaded from environment variables / .env file.

Database strategy:
- Set DATABASE_URL directly to use any SQLAlchemy-compatible database
  (e.g. PostgreSQL, SQLite for tests).
- If DATABASE_URL is not set, falls back to building the mssql+pyodbc URL
  from individual SQLSERVER_* variables (current SQL Server setup).

To migrate to PostgreSQL later:
  1. Set DATABASE_URL=postgresql+psycopg2://user:pass@host/dbname
  2. Remove or ignore SQLSERVER_* variables.
  3. No code changes required outside of this file.
"""

from typing import Optional
from urllib.parse import quote_plus

from pydantic import computed_field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "TravelWise API"
    API_V1_STR: str = "/api/v1"

    # -------------------------------------------------------------------------
    # Primary database URL (database-agnostic).
    # Set this to override all SQLSERVER_* variables below.
    # Examples:
    #   SQL Server : mssql+pyodbc:///?odbc_connect=...
    #   PostgreSQL : postgresql+psycopg2://user:pass@localhost:5432/dbname
    #   SQLite     : sqlite:///./test.db   (for local testing only)
    # -------------------------------------------------------------------------
    DATABASE_URL: Optional[str] = None

    # -------------------------------------------------------------------------
    # SQL Server connection params (used only when DATABASE_URL is not set).
    # These are SQL Server-specific and will NOT be needed after PostgreSQL migration.
    # -------------------------------------------------------------------------
    SQLSERVER_SERVER: str = "localhost"
    SQLSERVER_PORT: int = 1433
    SQLSERVER_USER: str = "sa"
    SQLSERVER_PASSWORD: str = "12345"
    SQLSERVER_DB: str = "TravelWiseDB"
    SQLSERVER_DRIVER: str = "ODBC Driver 17 for SQL Server"
    SQLSERVER_TRUST_CERT: str = "yes"

    # -------------------------------------------------------------------------
    # JWT Configuration
    # -------------------------------------------------------------------------
    JWT_SECRET: str = "your-secret-key"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    # -------------------------------------------------------------------------
    # LLM Configuration (supports "gemini" and "openai")
    # -------------------------------------------------------------------------
    LLM_PROVIDER: str = "gemini"  # "gemini" or "openai"

    # Google Gemini Configuration
    GEMINI_API_KEY: Optional[str] = None
    GEMINI_MODEL: str = "gemini-3.8-flash"

    # OpenAI Configuration
    OPENAI_API_KEY: Optional[str] = None
    OPENAI_MODEL: str = "gpt-4o-mini"
    OPENAI_BASE_URL: Optional[str] = None


    # -------------------------------------------------------------------------
    # RAG & Chroma Vector Store Configuration
    # -------------------------------------------------------------------------
    CHROMA_PERSIST_DIRECTORY: str = "data/chroma"
    CHROMA_COLLECTION_NAME: str = "travelwise_knowledge"
    EMBEDDING_PROVIDER: str = "auto"  # "auto", "openai", "local"
    EMBEDDING_MODEL: str = "text-embedding-3-small"
    RAG_CHUNK_SIZE: int = 500
    RAG_CHUNK_OVERLAP: int = 100
    RAG_TOP_K: int = 3

    @computed_field
    @property
    def SQLALCHEMY_DATABASE_URI(self) -> str:
        """Build the SQLAlchemy connection URL.

        Priority:
        1. DATABASE_URL env var (database-agnostic — use this for PostgreSQL).
        2. Constructed mssql+pyodbc URL from SQLSERVER_* vars (SQL Server fallback).
        """
        if self.DATABASE_URL:
            return self.DATABASE_URL

        # SQL Server-specific URL construction.
        # TODO (PostgreSQL migration): Remove this block and only use DATABASE_URL.
        odbc_params = (
            f"DRIVER={{{self.SQLSERVER_DRIVER}}};"
            f"SERVER={self.SQLSERVER_SERVER},{self.SQLSERVER_PORT};"
            f"DATABASE={self.SQLSERVER_DB};"
            f"UID={self.SQLSERVER_USER};"
            f"PWD={self.SQLSERVER_PASSWORD};"
            f"TrustServerCertificate={self.SQLSERVER_TRUST_CERT};"
        )
        return f"mssql+pyodbc:///?odbc_connect={quote_plus(odbc_params)}"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=True,
    )


settings = Settings()

