"""
TripPreference domain model — database-agnostic.

Maps to: trip_preferences table
"""

from decimal import Decimal
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Column, Numeric, Unicode, UnicodeText
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.trip import Trip


class TripPreference(TimestampMixin, SQLModel, table=True):
    """Detailed trip preferences, budget, constraints and JSON snapshot."""

    __tablename__ = "trip_preferences"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    trip_id: int = Field(
        foreign_key="trips.id",
        ondelete="CASCADE",
        unique=True,
        index=True,
    )

    travelers: Optional[int] = Field(default=None)
    adults: Optional[int] = Field(default=None)
    children: Optional[int] = Field(default=None)
    group_type: Optional[str] = Field(default=None, max_length=50)

    budget: Optional[Decimal] = Field(
        default=None,
        sa_column=Column(Numeric(12, 2)),
    )
    budget_currency: Optional[str] = Field(default="VND", max_length=10)
    budget_scope: Optional[str] = Field(default=None, max_length=50)

    duration_days: Optional[int] = Field(default=None)
    nights: Optional[int] = Field(default=None)

    transport: Optional[str] = Field(
        default=None,
        sa_column=Column(Unicode(100)),
    )
    travel_style: Optional[str] = Field(
        default=None,
        sa_column=Column(Unicode(100)),
    )
    interests: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
    )
    special_requirements: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
    )

    place_requirements: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
    )
    schedule_constraints: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
    )
    raw_context_snapshot: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
    )

    # Relationships
    trip: Optional["Trip"] = Relationship(back_populates="preferences")
