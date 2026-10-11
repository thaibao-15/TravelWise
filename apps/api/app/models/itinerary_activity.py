"""
ItineraryActivity domain model.

Maps to: itinerary_activities table in SQL Server.
Represents an activity planned within an itinerary day.
"""

import datetime as dt
from decimal import Decimal
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Column, Numeric, Time, Unicode, UnicodeText
from sqlmodel import Field, Relationship, SQLModel

if TYPE_CHECKING:
    from app.models.itinerary_day import ItineraryDay
    from app.models.place import Place


class ItineraryActivity(SQLModel, table=True):
    """Domain model storing an activity within an itinerary day."""

    __tablename__ = "itinerary_activities"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    itinerary_day_id: int = Field(
        foreign_key="itinerary_days.id",
        ondelete="CASCADE",
        index=True,
    )

    place_id: Optional[int] = Field(
        default=None,
        foreign_key="places.id",
        index=True,
    )

    activity_type: str = Field(
        default="VISIT",
        sa_column=Column(Unicode(30), default="VISIT", nullable=False),
    )

    title: str = Field(
        sa_column=Column(Unicode(255), nullable=False),
    )

    description: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
    )

    start_time: Optional[dt.time] = Field(
        default=None,
        sa_column=Column(Time, nullable=True),
    )

    end_time: Optional[dt.time] = Field(
        default=None,
        sa_column=Column(Time, nullable=True),
    )

    duration_minutes: Optional[int] = Field(
        default=None,
    )

    estimated_cost: Optional[Decimal] = Field(
        default=None,
        sa_column=Column(Numeric(12, 2), nullable=True),
    )

    travel_duration_minutes: Optional[int] = Field(
        default=None,
    )

    travel_distance_km: Optional[Decimal] = Field(
        default=None,
        sa_column=Column(Numeric(10, 2), nullable=True),
    )

    order_index: int = Field(
        index=True,
    )

    note: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
    )

    # Relationships
    itinerary_day: Optional["ItineraryDay"] = Relationship(back_populates="activities")
    place: Optional["Place"] = Relationship()
