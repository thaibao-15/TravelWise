"""
Database base utilities — database-agnostic.

Provides shared mixins and utilities for SQLModel/SQLAlchemy models.
All definitions here are compatible with both SQL Server and PostgreSQL.
"""

from datetime import datetime, timezone

from sqlmodel import Field, SQLModel


def _utcnow() -> datetime:
    """Return current UTC datetime (Python-side default for timestamp columns).

    Using Python-side default (instead of server_default) ensures:
    - Compatibility with both SQL Server and PostgreSQL.
    - Value is set before INSERT, available immediately after session.add().
    - No dependency on DB-specific functions like GETDATE() or NOW().
    """
    return datetime.now(timezone.utc)


class TimestampMixin(SQLModel):
    """Mixin that adds created_at / updated_at columns to any SQLModel table.

    Uses Field(default_factory=_utcnow) WITHOUT sa_column so that SQLModel creates
    a fresh Column object per subclass — avoiding the SQLAlchemy error:
    "Column object 'X' already assigned to Table 'Y'"

    SQLModel infers DateTime from the `datetime` annotation — compatible with
    SQL Server DATETIME and PostgreSQL TIMESTAMP on both databases.

    When migrating to PostgreSQL you can override these fields in the model with
    sa_column=Column(DateTime(timezone=True)) for TIMESTAMPTZ support.

    NOTE: server_default intentionally omitted to avoid GETDATE() SQL Server syntax.
    """

    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)

