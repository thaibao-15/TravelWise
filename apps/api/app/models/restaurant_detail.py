"""
RestaurantDetail model — database-agnostic.

Maps to: restaurant_details table
One-to-one relationship with Place (place_id is both PK and FK).
"""

from typing import TYPE_CHECKING, Optional

from sqlmodel import Field, Relationship, SQLModel

if TYPE_CHECKING:
    from app.models.place import Place


class RestaurantDetail(SQLModel, table=True):
    __tablename__ = "restaurant_details"

    place_id: int = Field(
        primary_key=True,
        foreign_key="places.id",
        # BIGINT PRIMARY KEY + FK → ON DELETE CASCADE handled in migration
    )

    cuisine_type: Optional[str] = Field(
        default=None,
        max_length=100,
        # NVARCHAR(100) → String(100)
    )

    price_range: Optional[str] = Field(
        default=None,
        max_length=50,
        # NVARCHAR(50) → String(50)
    )

    is_vegetarian: Optional[bool] = Field(
        default=None,
        # BIT → bool (nullable, not all restaurants have this info)
    )

    # Relationship
    place: Optional["Place"] = Relationship(back_populates="restaurant_detail")
