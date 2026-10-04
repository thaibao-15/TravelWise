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

    model_config = ConfigDict(from_attributes=True)


class PlaceImageResponse(BaseModel):
    id: int
    url: Optional[str] = None
    description: Optional[str] = None
    is_primary: bool

    model_config = ConfigDict(from_attributes=True)


# ─── Place schemas ───────────────────────────────────────────────────────────

class PlaceResponse(BaseModel):
    """Flat Place response (list endpoints)."""
    id: int
    name: str
    description: Optional[str] = None
    address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    category_id: Optional[int] = None
    is_deleted: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PlaceDetailResponse(PlaceResponse):
    """Detailed Place response — includes nested relations."""
    restaurant_detail: Optional[RestaurantDetailResponse] = None
    hotel_detail: Optional[HotelDetailResponse] = None
    images: list[PlaceImageResponse] = []

    model_config = ConfigDict(from_attributes=True)


class PlaceCreate(BaseModel):
    name: str
    description: Optional[str] = None
    address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    category_id: Optional[int] = None
