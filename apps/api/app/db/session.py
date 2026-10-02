"""
Database session management — database-agnostic.

The engine is configured entirely from settings.SQLALCHEMY_DATABASE_URI, which
is itself driven by the DATABASE_URL env var or SQLSERVER_* vars (see core/config.py).

To switch databases: change DATABASE_URL in .env — no code changes needed here.
"""

from typing import Generator

from sqlmodel import Session, create_engine

from app.core.config import settings

# Engine is created from the database URI in settings.
# pool_pre_ping=True works on both SQL Server and PostgreSQL.
engine = create_engine(
    settings.SQLALCHEMY_DATABASE_URI,
    echo=False,
    pool_pre_ping=True,
)


def get_session() -> Generator[Session, None, None]:
    """FastAPI dependency that yields a database session."""
    with Session(engine) as session:
        yield session
