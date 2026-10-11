"""
Trip domain model — database-agnostic.

Maps to: trips table
"""

from datetime import date
from typing import TYPE_CHECKING, List, Optional

from sqlalchemy import Column, Unicode
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.conversation import Conversation
    from app.models.itinerary_day import ItineraryDay
    from app.models.trip_preference import TripPreference
    from app.models.user import User


class Trip(TimestampMixin, SQLModel, table=True):
    """Trip domain model storing overview of planned trips."""

    __tablename__ = "trips"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    user_id: Optional[int] = Field(
        default=None,
        foreign_key="users.id",
        ondelete="CASCADE",
        index=True,
    )

    conversation_id: Optional[int] = Field(
        default=None,
        foreign_key="conversations.id",
        ondelete="NO ACTION",
        index=True,
    )

    name: Optional[str] = Field(
        default=None,
        sa_column=Column(Unicode(255)),
    )

    destination_city: Optional[str] = Field(
        default=None,
        sa_column=Column(Unicode(255)),
    )

    destination_country: Optional[str] = Field(
        default=None,
        sa_column=Column(Unicode(100)),
    )

    status: str = Field(
        default="DRAFT",
        max_length=50,
    )

    start_date: Optional[date] = Field(
        default=None,
    )

    end_date: Optional[date] = Field(
        default=None,
    )

    # Relationships
    user: Optional["User"] = Relationship(back_populates="trips")
    conversation: Optional["Conversation"] = Relationship(back_populates="trips")
    preferences: Optional["TripPreference"] = Relationship(
        back_populates="trip",
        sa_relationship_kwargs={"cascade": "all, delete-orphan", "uselist": False},
    )
    itinerary_days: List["ItineraryDay"] = Relationship(
        back_populates="trip",
        sa_relationship_kwargs={
            "cascade": "all, delete-orphan",
            "order_by": "ItineraryDay.day_number",
        },
    )
