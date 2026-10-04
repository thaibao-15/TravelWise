"""
Place model — database-agnostic core, with isolated GIS field.

Maps to: places table

GIS strategy:
- `latitude` / `longitude` (Float) are the primary, database-agnostic location data.
  They work on any database and are used for all standard queries.
- `location` (GEOGRAPHY) is SQL Server-specific spatial data, kept here because the
  project currently uses it for spatial indexing / proximity queries.
  It is isolated so it can be replaced without touching business logic.

PostgreSQL migration note for `location`:
  Replace  : sa_column=Column(NullType)  ← current placeholder / SQL Server GEOGRAPHY
  With     : sa_column=Column(Geometry("POINT", srid=4326))  ← GeoAlchemy2
  Install  : pip install geoalchemy2
  No other model / service changes needed.
"""

from typing import TYPE_CHECKING, List, Optional

from sqlalchemy import Column, Float, LargeBinary, Text
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.category import Category
    from app.models.hotel_detail import HotelDetail
    from app.models.knowledge import Knowledge
    from app.models.opening_hours import OpeningHours
    from app.models.place_image import PlaceImage
    from app.models.restaurant_detail import RestaurantDetail


class Place(TimestampMixin, SQLModel, table=True):
    __tablename__ = "places"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
        # BIGINT IDENTITY → IDENTITY on SQL Server, SERIAL on PostgreSQL (auto)
    )

    name: str = Field(
        max_length=255,
        nullable=False,
        # NVARCHAR(255) NOT NULL
    )

    description: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        # NVARCHAR(MAX) → Text (SQL Server: NVARCHAR(MAX), PostgreSQL: TEXT)
    )

    address: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        # NVARCHAR(MAX) → Text
    )

    # -------------------------------------------------------------------------
    # Coordinates — database-agnostic (Float on all databases).
    # These are the primary source of truth for location data.
    # -------------------------------------------------------------------------
    latitude: Optional[float] = Field(
        default=None,
        sa_column=Column(Float),
        # FLOAT → Float (Double precision on PostgreSQL, FLOAT on SQL Server)
    )

    longitude: Optional[float] = Field(
        default=None,
        sa_column=Column(Float),
    )

    # -------------------------------------------------------------------------
    # SQL Server-specific GEOGRAPHY column.
    #
    # Currently stored as raw bytes (LargeBinary) because SQLAlchemy has no
    # generic Geography type. SQL Server returns GEOGRAPHY as binary via pyodbc.
    #
    # WARNING: This field is SQL Server-specific. Spatial index
    # (CREATE SPATIAL INDEX) must be created via a raw migration script.
    #
    # PostgreSQL migration:
    #   1. pip install geoalchemy2
    #   2. from geoalchemy2 import Geometry
    #   3. Replace: sa_column=Column(LargeBinary, nullable=True)
    #      With   : sa_column=Column(Geometry("POINT", srid=4326), nullable=True)
    # -------------------------------------------------------------------------
    location: Optional[bytes] = Field(
        default=None,
        sa_column=Column(
            LargeBinary,
            nullable=True,
            # SQL Server: GEOGRAPHY — stored as binary blob via pyodbc.
            # PostgreSQL: Replace with GeoAlchemy2 Geometry column.
            # [SQL-SERVER-SPECIFIC]
        ),
    )

    # Foreign key
    category_id: Optional[int] = Field(
        default=None,
        foreign_key="categories.id",
    )

    is_deleted: bool = Field(
        default=False,
        # BIT DEFAULT 0 → bool (False)
    )

    # created_at / updated_at inherited from TimestampMixin

    # Relationships
    category: Optional["Category"] = Relationship(back_populates="places")
    images: List["PlaceImage"] = Relationship(back_populates="place")
    opening_hours: List["OpeningHours"] = Relationship(back_populates="place")
    restaurant_detail: Optional["RestaurantDetail"] = Relationship(back_populates="place")
    hotel_detail: Optional["HotelDetail"] = Relationship(back_populates="place")
    knowledge_items: List["Knowledge"] = Relationship(back_populates="place")
