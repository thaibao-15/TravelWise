"""
Models package — import all SQLModel table classes here.

All models must be imported in this file so that:
1. SQLModel.metadata is fully populated before Alembic autogenerate runs.
2. Relationship back-references resolve correctly at startup.

Import order: base/standalone models first, then models with FK dependencies.
"""

from app.models.category import Category
from app.models.hotel_detail import HotelDetail
from app.models.knowledge import Knowledge, KnowledgeChunk
from app.models.opening_hours import OpeningHours
from app.models.place import Place
from app.models.place_image import PlaceImage
from app.models.restaurant_detail import RestaurantDetail
from app.models.user import User

__all__ = [
    "User",
    "Category",
    "Place",
    "RestaurantDetail",
    "HotelDetail",
    "PlaceImage",
    "OpeningHours",
    "Knowledge",
    "KnowledgeChunk",
]
