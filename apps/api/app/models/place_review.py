"""
PlaceReview and ReviewImage models — database-agnostic.

Maps to: place_reviews, review_images tables
"""

from datetime import date, datetime
from typing import TYPE_CHECKING, List, Optional

from sqlalchemy import Column, Text
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import TimestampMixin, _utcnow

if TYPE_CHECKING:
    from app.models.place import Place
    from app.models.user import User


class PlaceReview(TimestampMixin, SQLModel, table=True):
    __tablename__ = "place_reviews"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    user_id: int = Field(
        foreign_key="users.id",
        nullable=False,
    )

    place_id: int = Field(
        foreign_key="places.id",
        nullable=False,
    )

    rating: int = Field(
        nullable=False,
        description="Điểm đánh giá từ 1 đến 5 sao",
    )

    title: Optional[str] = Field(
        default=None,
        max_length=255,
    )

    comment: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
    )

    trip_type: Optional[str] = Field(
        default=None,
        max_length=20,
        description="Loại chuyến đi: solo, couple, family, friends, business",
    )

    visited_at: Optional[date] = Field(
        default=None,
        description="Thời điểm thực tế trải nghiệm",
    )

    helpful_count: int = Field(
        default=0,
        nullable=False,
    )

    owner_reply: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
    )

    owner_replied_at: Optional[datetime] = Field(
        default=None,
    )

    is_visible: bool = Field(
        default=True,
        nullable=False,
    )

    is_deleted: bool = Field(
        default=False,
        nullable=False,
    )

    # Relationships
    place: Optional["Place"] = Relationship(back_populates="reviews")
    user: Optional["User"] = Relationship()
    images: List["ReviewImage"] = Relationship(back_populates="review")


class ReviewImage(SQLModel, table=True):
    __tablename__ = "review_images"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    review_id: int = Field(
        foreign_key="place_reviews.id",
        nullable=False,
    )

    image_url: str = Field(
        max_length=2048,
        nullable=False,
    )

    caption: Optional[str] = Field(
        default=None,
        max_length=255,
    )

    display_order: int = Field(
        default=0,
        nullable=False,
    )

    created_at: datetime = Field(
        default_factory=_utcnow,
        nullable=False,
    )

    # Relationships
    review: Optional["PlaceReview"] = Relationship(back_populates="images")


class ReviewHelpfulVote(SQLModel, table=True):
    __tablename__ = "review_helpful_votes"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    review_id: int = Field(
        foreign_key="place_reviews.id",
        nullable=False,
    )

    user_id: int = Field(
        foreign_key="users.id",
        nullable=False,
    )

    created_at: datetime = Field(
        default_factory=_utcnow,
        nullable=False,
    )

    # Relationships
    review: Optional["PlaceReview"] = Relationship()
    user: Optional["User"] = Relationship()
