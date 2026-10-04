"""
OpeningHours model — database-agnostic.

Maps to: opening_hours table

TIME column: SQLAlchemy's generic Time type maps to:
  SQL Server : TIME(7)
  PostgreSQL : TIME
Both databases support this type natively.
"""

from datetime import time
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Column, Time
from sqlmodel import Field, Relationship, SQLModel

if TYPE_CHECKING:
    from app.models.place import Place


class OpeningHours(SQLModel, table=True):
    __tablename__ = "opening_hours"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
        # BIGINT IDENTITY → auto-increment on both SQL Server and PostgreSQL
    )

    place_id: Optional[int] = Field(
        default=None,
        foreign_key="places.id",
        # ON DELETE CASCADE handled in migration
    )

    day_of_week: Optional[int] = Field(
        default=None,
        # INT — convention: 0=Monday … 6=Sunday (or 1=Sunday … 7=Saturday)
        # Choose and document your convention in business logic, not here.
    )

    open_time: Optional[time] = Field(
        default=None,
        sa_column=Column(Time),
        # TIME → SQLAlchemy Time — generic, works on SQL Server and PostgreSQL
    )

    close_time: Optional[time] = Field(
        default=None,
        sa_column=Column(Time),
    )

    # Relationship
    place: Optional["Place"] = Relationship(back_populates="opening_hours")
