"""
Models package — import all SQLModel table classes here.

All models must be imported in this file so that:
1. SQLModel.metadata is fully populated before Alembic autogenerate runs.
2. Relationship back-references resolve correctly at startup.

Import order: standalone models first, then FK-dependent models.
KnowledgeChunk is deferred to Phase 2 (RAG pipeline).
"""

# Standalone / no FK dependencies
from app.models.user import User
from app.models.category import Category

# FK-dependent models
from app.models.place import Place
from app.models.restaurant_detail import RestaurantDetail
from app.models.hotel_detail import HotelDetail
from app.models.place_image import PlaceImage
from app.models.opening_hours import OpeningHours
from app.models.knowledge import Knowledge
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.trip import Trip
from app.models.trip_preference import TripPreference
from app.models.ai_context import AIContext
from app.models.conversation_summary import ConversationSummary
from app.models.user_profile import UserProfile
from app.models.itinerary_day import ItineraryDay
from app.models.itinerary_activity import ItineraryActivity
from app.models.place_review import PlaceReview, ReviewHelpfulVote, ReviewImage

__all__ = [
    "User",
    "Category",
    "Place",
    "RestaurantDetail",
    "HotelDetail",
    "PlaceImage",
    "PlaceReview",
    "ReviewImage",
    "ReviewHelpfulVote",
    "OpeningHours",
    "Knowledge",
    "Conversation",
    "Message",
    "Trip",
    "TripPreference",
    "AIContext",
    "ConversationSummary",
    "UserProfile",
    "ItineraryDay",
    "ItineraryActivity",
]
