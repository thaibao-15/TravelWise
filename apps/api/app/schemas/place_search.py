"""
Place Search schemas for TravelWise AI Itinerary.

Defines request and response structures for searching and ranking places
based on TripPlanningContext from SQL Server.
"""

from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field

from app.schemas.trip_planning import TripPlanningContext


class SearchPlaceItem(BaseModel):
    """A place retrieved from SQL Server and scored for itinerary planning."""

    place_id: int
    name: str
    category: Optional[str] = None
    category_id: Optional[int] = None
    address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    price: Optional[float] = None
    price_info: Optional[str] = None
    opening_hours: Optional[str] = None
    matched_interests: List[str] = Field(default_factory=list)
    is_must_visit: bool = False
    is_preferred: bool = False
    match_reasons: List[str] = Field(default_factory=list)
    score: float = 0.0
    data_completeness: str = "PARTIAL"  # "FULL" | "PARTIAL" | "MINIMAL"
    image_url: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class UnresolvedMustVisitItem(BaseModel):
    """A requested must-visit place that could not be matched in SQL Server."""

    name: str
    priority: Optional[str] = None
    reason: str = "Không tìm thấy trong cơ sở dữ liệu địa phương"

    model_config = ConfigDict(from_attributes=True)


class PlaceSearchResponse(BaseModel):
    """Response payload containing ranked places and diagnostic info."""

    destination: Optional[str] = None
    places: List[SearchPlaceItem] = Field(default_factory=list)
    unresolved_must_visit: List[UnresolvedMustVisitItem] = Field(default_factory=list)
    warnings: List[str] = Field(default_factory=list)
    total: int = 0
    skip: int = 0
    limit: int = 20

    model_config = ConfigDict(from_attributes=True)


class PlaceSearchRequest(BaseModel):
    """Optional request payload allowing client to override or supply context directly."""

    context: Optional[TripPlanningContext] = None
    skip: int = Field(default=0, ge=0)
    limit: int = Field(default=20, ge=1, le=100)

    model_config = ConfigDict(from_attributes=True)
