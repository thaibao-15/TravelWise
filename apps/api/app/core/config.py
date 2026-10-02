from typing import Optional
from urllib.parse import quote_plus
from pydantic import computed_field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "TravelWise API"
    API_V1_STR: str = "/api/v1"

    # SQL Server Database configuration
    SQLSERVER_SERVER: str = "localhost"
    SQLSERVER_PORT: int = 1433
    SQLSERVER_USER: str = "sa"
    SQLSERVER_PASSWORD: str = "12345"
    SQLSERVER_DB: str = "TravelWiseDB"
    SQLSERVER_DRIVER: str = "ODBC Driver 17 for SQL Server"
    SQLSERVER_TRUST_CERT: str = "yes"

    # JWT Configuration
    JWT_SECRET: str = "your-secret-key"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    # Optional custom Database URL override
    DATABASE_URL: Optional[str] = None

    @computed_field
    @property
    def SQLALCHEMY_DATABASE_URI(self) -> str:
        if self.DATABASE_URL:
            return self.DATABASE_URL

        connection_string = (
            f"DRIVER={{{self.SQLSERVER_DRIVER}}};"
            f"SERVER={self.SQLSERVER_SERVER},{self.SQLSERVER_PORT};"
            f"DATABASE={self.SQLSERVER_DB};"
            f"UID={self.SQLSERVER_USER};"
            f"PWD={self.SQLSERVER_PASSWORD};"
            f"TrustServerCertificate={self.SQLSERVER_TRUST_CERT};"
        )
        return f"mssql+pyodbc:///?odbc_connect={quote_plus(connection_string)}"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=True,
    )


settings = Settings()
