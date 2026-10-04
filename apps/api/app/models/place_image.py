"""
PlaceImage model — database-agnostic.

Maps to: place_images table
"""

from typing import TYPE_CHECKING, Optional

from sqlalchemy import Column, Text
from sqlmodel import Field, Relationship, SQLModel

if TYPE_CHECKING:
    from app.models.place import Place


class PlaceImage(SQLModel, table=True):
    __tablename__ = "place_images"

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

    url: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        # NVARCHAR(MAX) → Text (URLs can be long)
    )

    description: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        # NVARCHAR(MAX) → Text
    )

    is_primary: bool = Field(
        default=False,
        # BIT DEFAULT 0 → bool (False)
    )

    # Relationship
    place: Optional["Place"] = Relationship(back_populates="images")
