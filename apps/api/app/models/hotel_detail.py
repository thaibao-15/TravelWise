"""
HotelDetail model — database-agnostic.

Maps to: hotel_details table
One-to-one relationship with Place (place_id is both PK and FK).
"""

from decimal import Decimal
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Column, Numeric, Text
from sqlmodel import Field, Relationship, SQLModel

if TYPE_CHECKING:
    from app.models.place import Place


class HotelDetail(SQLModel, table=True):
    __tablename__ = "hotel_details"

    place_id: int = Field(
        primary_key=True,
        foreign_key="places.id",
        # BIGINT PRIMARY KEY + FK → ON DELETE CASCADE handled in migration
    )

    star_rating: Optional[int] = Field(
        default=None,
        # INT → int
    )

    price_per_night: Optional[Decimal] = Field(
        default=None,
        sa_column=Column(
            Numeric(10, 2),
            nullable=True,
        ),
        # DECIMAL(10,2) → Numeric(10, 2) — works on both SQL Server and PostgreSQL
    )

    amenities: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        # NVARCHAR(MAX) → Text
    )

    # Relationship
    place: Optional["Place"] = Relationship(back_populates="hotel_detail")
