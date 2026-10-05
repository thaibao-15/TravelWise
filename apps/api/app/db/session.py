"""
Database session management — database-agnostic.

The engine is configured entirely from settings.SQLALCHEMY_DATABASE_URI, which
is itself driven by the DATABASE_URL env var or SQLSERVER_* vars (see core/config.py).

To switch databases: change DATABASE_URL in .env — no code changes needed here.
"""

from typing import Generator

from sqlalchemy import event
from sqlmodel import Session, create_engine

from app.core.config import settings

# Engine is created from the database URI in settings.
# pool_pre_ping=True works on both SQL Server and PostgreSQL.
# use_setinputsizes=False prevents pyodbc from binding strings as non-Unicode (VARCHAR)
# which causes Vietnamese diacritics to become '?' marks in SQL Server.
engine_kwargs = {
    "echo": False,
    "pool_pre_ping": True,
}
if "mssql+pyodbc" in settings.SQLALCHEMY_DATABASE_URI:
    engine_kwargs["use_setinputsizes"] = False

engine = create_engine(
    settings.SQLALCHEMY_DATABASE_URI,
    **engine_kwargs,
)


@event.listens_for(engine, "connect")
def _handle_pyodbc_udt(dbapi_connection, connection_record):
    """Handle SQL Server GEOGRAPHY / GEOMETRY (-151) UDT columns in pyodbc."""
    if hasattr(dbapi_connection, "add_output_converter"):
        dbapi_connection.add_output_converter(-151, lambda val: bytes(val) if val else None)


def get_session() -> Generator[Session, None, None]:
    """FastAPI dependency that yields a database session."""
    with Session(engine) as session:
        yield session
