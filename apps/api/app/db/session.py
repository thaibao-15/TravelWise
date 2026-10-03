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
engine = create_engine(
    settings.SQLALCHEMY_DATABASE_URI,
    echo=False,
    pool_pre_ping=True,
)


@event.listens_for(engine, "connect")
def _configure_pyodbc_encoding(dbapi_connection, connection_record):
    """Configure pyodbc encoding for full Unicode (UTF-8) support.

    ODBC Driver 17 for SQL Server + Vietnamese_CI_AS collation:
    - Without this, parameterized Python str values are sent as VARCHAR via the
      Windows code page (cp1258), which does NOT contain all Unicode characters
      (e.g. u with tilde U+0169 -> '?'). Setting encoding to utf-8 forces wide-char
      (UTF-16) transport for NVARCHAR columns, preserving all Unicode characters.
    - setdecoding ensures strings read back from the driver are decoded as UTF-8.
    """
    if hasattr(dbapi_connection, "setencoding"):
        # Force UTF-8 for both send and receive paths
        dbapi_connection.setencoding(encoding="utf-8")
    if hasattr(dbapi_connection, "setdecoding"):
        import pyodbc
        dbapi_connection.setdecoding(pyodbc.SQL_CHAR, encoding="utf-8")
        dbapi_connection.setdecoding(pyodbc.SQL_WCHAR, encoding="utf-8")

    # Handle SQL Server GEOGRAPHY / GEOMETRY (-151) UDT columns in pyodbc.
    if hasattr(dbapi_connection, "add_output_converter"):
        dbapi_connection.add_output_converter(-151, lambda val: bytes(val) if val else None)


def get_session() -> Generator[Session, None, None]:
    """FastAPI dependency that yields a database session."""
    with Session(engine) as session:
        yield session
