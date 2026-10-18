"""Travel profile model for an authenticated user."""

from datetime import date, datetime
from decimal import Decimal
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Column, Date, DateTime, Numeric, Unicode, UnicodeText
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import _utcnow

if TYPE_CHECKING:
    from app.models.user import User


class UserProfile(SQLModel, table=True):
    """One-to-one travel preferences and profile data for a user."""

    __tablename__ = "user_profiles"

    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(
        foreign_key="users.id",
        nullable=False,
        unique=True,
        ondelete="CASCADE",
    )
    phone: str | None = Field(
        default=None,
        sa_column=Column(Unicode(20), nullable=True),
    )
    date_of_birth: date | None = Field(
        default=None,
        sa_column=Column(Date, nullable=True),
    )
    gender: str | None = Field(
        default=None,
        sa_column=Column(Unicode(20), nullable=True),
    )
    nationality: str | None = Field(
        default=None,
        sa_column=Column(Unicode(100), nullable=True),
    )
    preferred_language: str = Field(
        default="vi",
        sa_column=Column(Unicode(10), nullable=False),
    )
    travel_style: str | None = Field(
        default=None,
        sa_column=Column(Unicode(50), nullable=True),
    )
    favorite_categories: str | None = Field(
        default=None,
        sa_column=Column(UnicodeText, nullable=True),
    )
    interests: str | None = Field(
        default=None,
        sa_column=Column(UnicodeText, nullable=True),
    )
    budget_min: Decimal | None = Field(
        default=None,
        sa_column=Column(Numeric(12, 2), nullable=True),
    )
    budget_max: Decimal | None = Field(
        default=None,
        sa_column=Column(Numeric(12, 2), nullable=True),
    )
    currency: str = Field(
        default="VND",
        sa_column=Column(Unicode(10), nullable=False),
    )
    preferred_transport: str | None = Field(
        default=None,
        sa_column=Column(Unicode(50), nullable=True),
    )
    accommodation_type: str | None = Field(
        default=None,
        sa_column=Column(Unicode(50), nullable=True),
    )
    dietary_preferences: str | None = Field(
        default=None,
        sa_column=Column(UnicodeText, nullable=True),
    )
    accessibility_needs: str | None = Field(
        default=None,
        sa_column=Column(UnicodeText, nullable=True),
    )
    preferred_travel_pace: str | None = Field(
        default=None,
        sa_column=Column(Unicode(30), nullable=True),
    )
    additional_preferences: str | None = Field(
        default=None,
        sa_column=Column(UnicodeText, nullable=True),
    )
    created_at: datetime = Field(default_factory=_utcnow, sa_type=DateTime)
    updated_at: datetime = Field(default_factory=_utcnow, sa_type=DateTime)

    user: Optional["User"] = Relationship(  # noqa: UP045, UP037
        back_populates="profile"
    )
