"""
Database base utilities — database-agnostic.

Provides shared mixins and utilities for SQLModel/SQLAlchemy models.
All definitions here are compatible with both SQL Server and PostgreSQL.
"""

from datetime import datetime, timezone

from sqlalchemy import DateTime
from sqlmodel import Field, SQLModel


def _utcnow() -> datetime:
    """Return current UTC datetime (timezone-aware).

    Returns a timezone-aware UTC datetime. SQLAlchemy will strip the tzinfo
    when writing to SQL Server DATETIME columns (which are tz-naive by nature).

    PostgreSQL migration note:
    - For TIMESTAMPTZ on PostgreSQL, use DateTime(timezone=True) in the column.
    - This function works unchanged on PostgreSQL.
    """
    return datetime.now(timezone.utc)


class TimestampMixin(SQLModel):
    """Mixin that adds created_at / updated_at columns to any SQLModel table.

    Uses Field(default_factory=_utcnow, sa_type=DateTime) instead of an explicit
    sa_column=Column(...). This ensures SQLModel creates a separate, independent
    Column object for every inheriting table (User, Place, etc.), avoiding the
    SQLAlchemy ArgumentError caused by reusing a single Column object across tables.

    sa_type=DateTime ensures database-agnostic behavior:
      SQL Server : DATETIME (tz-naive in DB; SQLAlchemy strips tzinfo on bind)
      PostgreSQL : TIMESTAMP

    NOTE: server_default intentionally omitted to avoid GETDATE() SQL Server syntax.
    """

    created_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime,
    )

    updated_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime,
    )

