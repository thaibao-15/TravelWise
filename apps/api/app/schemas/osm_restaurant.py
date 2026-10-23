from datetime import time
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.core.config import settings


class OSMBoundingBox(BaseModel):
    """Bounding box for Overpass API queries (south, west, north, east)."""

    south: float = Field(default_factory=lambda: settings.DANANG_BBOX_SOUTH)
    west: float = Field(default_factory=lambda: settings.DANANG_BBOX_WEST)
    north: float = Field(default_factory=lambda: settings.DANANG_BBOX_NORTH)
    east: float = Field(default_factory=lambda: settings.DANANG_BBOX_EAST)

    @model_validator(mode="after")
    def validate_bounds(self) -> "OSMBoundingBox":
        if self.south > self.north:
            raise ValueError(f"south ({self.south}) must be <= north ({self.north})")
        if self.west > self.east:
            raise ValueError(f"west ({self.west}) must be <= east ({self.east})")
        if not (-90.0 <= self.south <= 90.0 and -90.0 <= self.north <= 90.0):
            raise ValueError("Latitudes must be between -90 and 90")
        if not (-180.0 <= self.west <= 180.0 and -180.0 <= self.east <= 180.0):
            raise ValueError("Longitudes must be between -180 and 180")
        return self


class OpeningHourSlot(BaseModel):
    """Structured opening hour interval matching the database opening_hours model.

    Convention: 0 = Monday, ..., 6 = Sunday.
    """

    day_of_week: int = Field(ge=0, le=6, description="0=Monday, ..., 6=Sunday")
    open_time: time
    close_time: time

    model_config = ConfigDict(from_attributes=True)


class NormalizedRestaurant(BaseModel):
    """Normalized restaurant structure extracted from OpenStreetMap Overpass elements.

    Designed for clean mapping into places, restaurant_details, place_images, and
    opening_hours tables during subsequent persistence phases. Missing or absent
    attributes are preserved strictly as None without ungrounded heuristics.
    """

    osm_id: int
    osm_type: str  # "node", "way", or "relation"
    name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    address: Optional[str] = None
    street: Optional[str] = None
    housenumber: Optional[str] = None
    quarter: Optional[str] = None
    district: Optional[str] = None
    city: Optional[str] = None
    cuisine: Optional[str] = None
    opening_hours_raw: Optional[str] = None
    opening_hours: list[OpeningHourSlot] = Field(default_factory=list)
    is_vegetarian: Optional[bool] = None
    image_url: Optional[str] = None
    wikimedia_commons: Optional[str] = None
    phone: Optional[str] = None
    website: Optional[str] = None
    raw_tags: dict[str, str] = Field(default_factory=dict)

    model_config = ConfigDict(from_attributes=True)
