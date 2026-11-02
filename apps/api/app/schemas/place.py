from datetime import datetime
from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, ConfigDict


# ─── Sub-schemas for nested detail responses ────────────────────────────────

class RestaurantDetailResponse(BaseModel):
    cuisine_type: Optional[str] = None
    price_range: Optional[str] = None
    is_vegetarian: Optional[bool] = None

    model_config = ConfigDict(from_attributes=True)


class HotelDetailResponse(BaseModel):
    star_rating: Optional[int] = None
    price_per_night: Optional[Decimal] = None
    amenities: Optional[str] = None
    phone: Optional[str] = None
    website: Optional[str] = None
    email: Optional[str] = None
    rooms: Optional[int] = None
    beds: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)


class PlaceImageResponse(BaseModel):
    id: int
    url: Optional[str] = None
    description: Optional[str] = None
    is_primary: bool

    model_config = ConfigDict(from_attributes=True)


class PlaceImageCreate(BaseModel):
    url: str
    description: Optional[str] = None
    is_primary: bool = False


# ─── Place schemas ───────────────────────────────────────────────────────────

class PlaceResponse(BaseModel):
    """Place response with associated images."""
    id: int
    name: str
    description: Optional[str] = None
    address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    category_id: Optional[int] = None
    rating_avg: Optional[float] = 0.0
    review_count: Optional[int] = 0
    is_deleted: bool
    created_at: datetime
    updated_at: datetime
    images: list[PlaceImageResponse] = []

    model_config = ConfigDict(from_attributes=True)


class NearbyPlaceResponse(PlaceResponse):
    distance_km: float


class PlaceDetailResponse(PlaceResponse):
    """Detailed Place response — includes nested relations."""
    restaurant_detail: Optional[RestaurantDetailResponse] = None
    hotel_detail: Optional[HotelDetailResponse] = None

    model_config = ConfigDict(from_attributes=True)


class PlaceCreate(BaseModel):
    name: str
    description: Optional[str] = None
    address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    category_id: Optional[int] = None
