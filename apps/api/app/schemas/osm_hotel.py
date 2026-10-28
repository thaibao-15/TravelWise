from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class NormalizedHotel(BaseModel):
    """Normalized hotel structure extracted from OpenStreetMap Overpass elements.

    Designed for clean mapping into places, hotel_details, place_images, and
    opening_hours tables during subsequent persistence phases.
    Strictly avoids ungrounded heuristics: absent attributes remain None or empty list.
    """

    osm_id: int
    osm_type: str  # "node", "way", or "relation"
    name: str
    latitude: float
    longitude: float
    address: Optional[str] = None
    street: Optional[str] = None
    housenumber: Optional[str] = None
    district: Optional[str] = None
    city: Optional[str] = None
    postcode: Optional[str] = None
    phone: Optional[str] = None
    website: Optional[str] = None
    email: Optional[str] = None
    star_rating: Optional[int] = None
    rooms: Optional[int] = None
    beds: Optional[int] = None
    opening_hours_raw: Optional[str] = None
    amenities: list[str] = Field(default_factory=list)
    image_url: Optional[str] = None
    wikimedia_commons: Optional[str] = None
    raw_tags: dict[str, str] = Field(default_factory=dict)

    model_config = ConfigDict(from_attributes=True)
