"""
ItineraryDay domain model.

Maps to: itinerary_days table in SQL Server.
Represents one day within a planned trip itinerary.
"""

import datetime as dt
from typing import TYPE_CHECKING, List, Optional

from sqlalchemy import Column, Unicode, UnicodeText
from sqlmodel import Field, Relationship, SQLModel

if TYPE_CHECKING:
    from app.models.itinerary_activity import ItineraryActivity
    from app.models.trip import Trip


class ItineraryDay(SQLModel, table=True):
    """Domain model storing an itinerary day."""

    __tablename__ = "itinerary_days"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    trip_id: int = Field(
        foreign_key="trips.id",
        ondelete="CASCADE",
        index=True,
    )

    day_number: int = Field(
        index=True,
    )

    date: Optional[dt.date] = Field(
        default=None,
    )

    title: Optional[str] = Field(
        default=None,
        sa_column=Column(Unicode(255)),
    )

    description: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
    )

    # Relationships
    trip: Optional["Trip"] = Relationship(back_populates="itinerary_days")
    activities: List["ItineraryActivity"] = Relationship(
        back_populates="itinerary_day",
        sa_relationship_kwargs={
            "cascade": "all, delete-orphan",
            "order_by": "ItineraryActivity.order_index",
        },
    )
