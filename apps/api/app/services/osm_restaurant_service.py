import asyncio
from datetime import time
import logging
import re
from typing import Any, Optional
from urllib.parse import quote

from fastapi import HTTPException, status
import httpx

from app.core.config import settings
from app.schemas.osm_restaurant import (
    NormalizedRestaurant,
    OSMBoundingBox,
    OpeningHourSlot,
)

logger = logging.getLogger(__name__)

# Map English 2-letter OSM day abbreviations to 0=Monday ... 6=Sunday
_DAY_MAP: dict[str, int] = {
    "mo": 0,
    "tu": 1,
    "we": 2,
    "th": 3,
    "fr": 4,
    "sa": 5,
    "su": 6,
}
_DAY_KEYS = list(_DAY_MAP.keys())


class OSMRestaurantService:
    """Service to fetch and normalize restaurant data from OpenStreetMap via Overpass API."""

    @staticmethod
    def build_overpass_query(bbox: OSMBoundingBox, timeout_seconds: int = 30) -> str:
        """Construct Overpass QL query for amenity=restaurant within bounding box.

        Includes node, way, and relation elements with 'out body center' to ensure
        ways and relations have center coordinates computed by Overpass.
        """
        bbox_str = f"{bbox.south},{bbox.west},{bbox.north},{bbox.east}"
        return (
            f"[out:json][timeout:{timeout_seconds}];\n"
            f"(\n"
            f'  node["amenity"="restaurant"]({bbox_str});\n'
            f'  way["amenity"="restaurant"]({bbox_str});\n'
            f'  relation["amenity"="restaurant"]({bbox_str});\n'
            f");\n"
            f"out body center;\n"
        )

    @staticmethod
    def extract_coordinates(
        element: dict[str, Any],
    ) -> tuple[Optional[float], Optional[float]]:
        """Extract latitude and longitude for node, way, or relation without guessing.

        For nodes, lat and lon are at the root level.
        For ways and relations, lat and lon are inside the 'center' sub-dict.
        Returns (None, None) if missing or non-numeric.
        """
        lat: Optional[float] = None
        lon: Optional[float] = None

        # Check root level (nodes or direct coordinates)
        if "lat" in element and "lon" in element:
            try:
                lat = float(element["lat"])
                lon = float(element["lon"])
            except (ValueError, TypeError):
                lat, lon = None, None

        # Fallback to center dict (ways / relations)
        if (lat is None or lon is None) and isinstance(element.get("center"), dict):
            center = element["center"]
            if "lat" in center and "lon" in center:
                try:
                    lat = float(center["lat"])
                    lon = float(center["lon"])
                except (ValueError, TypeError):
                    lat, lon = None, None

        # Validate coordinate ranges
        if lat is not None and lon is not None:
            if -90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0:
                return lat, lon

        return None, None

    @staticmethod
    def extract_name(tags: dict[str, Any]) -> Optional[str]:
        """Extract restaurant name from primary or localized tags."""
        name = tags.get("name") or tags.get("name:vi") or tags.get("name:en") or tags.get("int_name")
        if name and isinstance(name, str):
            clean = name.strip()
            return clean if clean else None
        return None

    @staticmethod
    def extract_address(
        tags: dict[str, Any],
    ) -> tuple[
        Optional[str],
        Optional[str],
        Optional[str],
        Optional[str],
        Optional[str],
        Optional[str],
    ]:
        """Extract address components and full address from addr:* or contact:* tags.

        Returns (full_address, street, housenumber, quarter, district, city).
        Never invents missing parts.
        """
        housenumber = tags.get("addr:housenumber") or tags.get("contact:housenumber")
        street = tags.get("addr:street") or tags.get("contact:street")
        quarter = (
            tags.get("addr:suburb")
            or tags.get("addr:quarter")
            or tags.get("addr:neighbourhood")
        )
        district = tags.get("addr:district")
        city = tags.get("addr:city") or tags.get("contact:city")

        def _clean(val: Any) -> Optional[str]:
            if val and isinstance(val, str):
                s = val.strip()
                return s if s else None
            return None

        housenumber = _clean(housenumber)
        street = _clean(street)
        quarter = _clean(quarter)
        district = _clean(district)
        city = _clean(city)

        full_addr = _clean(tags.get("addr:full"))
        if not full_addr:
            parts: list[str] = []
            if housenumber and street:
                parts.append(f"{housenumber} {street}")
            elif street:
                parts.append(street)
            elif housenumber:
                parts.append(housenumber)

            if quarter:
                parts.append(quarter)
            if district:
                parts.append(district)
            if city:
                parts.append(city)

            if parts:
                full_addr = ", ".join(parts)

        return full_addr, street, housenumber, quarter, district, city

    @staticmethod
    def extract_cuisine(tags: dict[str, Any]) -> Optional[str]:
        """Extract cuisine tag, trimming whitespace."""
        cuisine = tags.get("cuisine")
        if cuisine and isinstance(cuisine, str):
            cleaned = cuisine.strip()
            return cleaned if cleaned else None
        return None

    @staticmethod
    def extract_vegetarian(tags: dict[str, Any]) -> Optional[bool]:
        """Determine vegetarian indicator strictly from diet:vegetarian or vegetarian tags.

        Returns True for 'yes' or 'only', False for 'no', otherwise None.
        Never guesses based on restaurant name or cuisine text.
        """
        veg_tag = (tags.get("diet:vegetarian") or tags.get("vegetarian") or "").strip().lower()
        if veg_tag in {"yes", "only"}:
            return True
        if veg_tag == "no":
            return False
        return None

    @staticmethod
    def extract_media(tags: dict[str, Any]) -> tuple[Optional[str], Optional[str]]:
        """Extract media URL and Wikimedia Commons reference.

        Returns (image_url, wikimedia_commons).
        Converts Commons File references into direct Wikimedia media file paths.
        """
        image_val = tags.get("image") or tags.get("image:url") or tags.get("contact:image")
        commons_val = tags.get("wikimedia_commons") or tags.get("image:commons")

        image_url: Optional[str] = None
        wikimedia_commons: Optional[str] = None

        if isinstance(image_val, str) and image_val.strip():
            clean_image = image_val.strip()
            if clean_image.lower().startswith(("http://", "https://")):
                image_url = clean_image
            elif clean_image.lower().startswith("file:"):
                wikimedia_commons = clean_image
                encoded = quote(clean_image[5:].strip().replace(" ", "_"))
                image_url = f"https://commons.wikimedia.org/wiki/Special:FilePath/{encoded}"

        if isinstance(commons_val, str) and commons_val.strip():
            clean_commons = commons_val.strip()
            if not wikimedia_commons:
                wikimedia_commons = clean_commons
            if not image_url:
                file_name = clean_commons
                if file_name.lower().startswith("file:"):
                    file_name = file_name[5:].strip()
                encoded = quote(file_name.replace(" ", "_"))
                image_url = f"https://commons.wikimedia.org/wiki/Special:FilePath/{encoded}"

        return image_url, wikimedia_commons

    @classmethod
    def parse_opening_hours(cls, raw: Optional[str]) -> list[OpeningHourSlot]:
        """Defensively parse standard OSM opening_hours string into OpeningHourSlot list.

        Supports standard expressions such as:
          - '24/7'
          - '08:00-22:00'
          - 'Mo-Su 08:00-22:00'
          - 'Mo-Fr 07:00-21:00; Sa-Su 08:00-22:00'
          - 'Mo,Tu,We,Th,Fr 08:00-17:00'
        If an expression cannot be cleanly parsed, returns an empty list without guessing.
        """
        if not raw or not isinstance(raw, str):
            return []

        clean_raw = raw.strip()
        if not clean_raw:
            return []

        if clean_raw.lower() == "24/7":
            return [
                OpeningHourSlot(
                    day_of_week=d,
                    open_time=time(0, 0),
                    close_time=time(23, 59),
                )
                for d in range(7)
            ]

        slots: list[OpeningHourSlot] = []

        # Split multiple day rules separated by semicolon
        sections = [sec.strip() for sec in clean_raw.split(";") if sec.strip()]

        for section in sections:
            # Match optional day range/list followed by time range
            # e.g. "Mo-Fr 08:00-22:00", "08:00-22:00", "Mo,We,Fr 09:00-18:00"
            m = re.match(
                r"^(?:([A-Za-z,\s-]+)\s+)?(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})$",
                section,
            )
            if not m:
                continue

            day_part, start_str, end_str = m.groups()

            try:
                sh, sm = map(int, start_str.split(":"))
                eh, em = map(int, end_str.split(":"))
                # Cap 24:00 at 23:59 for standard time object
                if eh == 24 and em == 0:
                    eh, em = 23, 59
                open_t = time(sh, sm)
                close_t = time(eh, em)
            except (ValueError, TypeError):
                continue

            days: list[int] = []
            if not day_part:
                # Applies to all 7 days if no days specified
                days = list(range(7))
            else:
                day_clean = day_part.strip().lower()
                # Check for range: Mo-Fr
                range_match = re.match(r"^([a-z]{2})\s*-\s*([a-z]{2})$", day_clean)
                if range_match:
                    d_from, d_to = range_match.groups()
                    if d_from in _DAY_MAP and d_to in _DAY_MAP:
                        idx_from = _DAY_MAP[d_from]
                        idx_to = _DAY_MAP[d_to]
                        if idx_from <= idx_to:
                            days = list(range(idx_from, idx_to + 1))
                        else:
                            # Wraps around week (e.g. Fr-Mo)
                            days = list(range(idx_from, 7)) + list(range(0, idx_to + 1))
                else:
                    # Comma separated days e.g. Mo,Tu,We
                    for sub in day_clean.split(","):
                        sub_str = sub.strip()
                        if sub_str in _DAY_MAP:
                            days.append(_DAY_MAP[sub_str])

            for day_idx in days:
                slots.append(
                    OpeningHourSlot(
                        day_of_week=day_idx,
                        open_time=open_t,
                        close_time=close_t,
                    )
                )

        return slots

    @classmethod
    def normalize_element(cls, element: dict[str, Any]) -> NormalizedRestaurant:
        """Normalize a raw Overpass element (node, way, or relation) into NormalizedRestaurant."""
        osm_id = int(element.get("id", 0))
        osm_type = str(element.get("type", "node")).lower()
        tags: dict[str, Any] = element.get("tags") or {}

        # 1. Coordinates
        lat, lon = cls.extract_coordinates(element)

        # 2. Name
        name = cls.extract_name(tags)

        # 3. Address
        full_addr, street, housenumber, quarter, district, city = cls.extract_address(tags)

        # 4. Cuisine
        cuisine = cls.extract_cuisine(tags)

        # 5. Vegetarian
        is_veg = cls.extract_vegetarian(tags)

        # 6. Opening hours
        raw_hours = tags.get("opening_hours")
        if raw_hours and isinstance(raw_hours, str):
            raw_hours_clean = raw_hours.strip() or None
        else:
            raw_hours_clean = None
        parsed_hours = cls.parse_opening_hours(raw_hours_clean)

        # 7. Media
        image_url, wikimedia_commons = cls.extract_media(tags)

        # 8. Contact
        phone = tags.get("phone") or tags.get("contact:phone")
        if phone and isinstance(phone, str):
            phone = phone.strip() or None
        else:
            phone = None

        website = tags.get("website") or tags.get("contact:website")
        if website and isinstance(website, str):
            website = website.strip() or None
        else:
            website = None

        # Clean raw_tags
        clean_raw_tags: dict[str, str] = {
            str(k): str(v) for k, v in tags.items() if v is not None
        }

        return NormalizedRestaurant(
            osm_id=osm_id,
            osm_type=osm_type,
            name=name,
            latitude=lat,
            longitude=lon,
            address=full_addr,
            street=street,
            housenumber=housenumber,
            quarter=quarter,
            district=district,
            city=city,
            cuisine=cuisine,
            opening_hours_raw=raw_hours_clean,
            opening_hours=parsed_hours,
            is_vegetarian=is_veg,
            image_url=image_url,
            wikimedia_commons=wikimedia_commons,
            phone=phone,
            website=website,
            raw_tags=clean_raw_tags,
        )

    @classmethod
    def normalize_elements(
        cls,
        elements: list[dict[str, Any]],
        skip_unnamed: bool = False,
        skip_missing_coords: bool = False,
    ) -> list[NormalizedRestaurant]:
        """Normalize multiple Overpass elements into NormalizedRestaurant list.

        Optionally filters out elements lacking names or coordinates if requested
        by caller (default keeps all elements with None fields).
        """
        results: list[NormalizedRestaurant] = []
        for el in elements:
            try:
                normalized = cls.normalize_element(el)
                if skip_unnamed and not normalized.name:
                    continue
                if skip_missing_coords and (
                    normalized.latitude is None or normalized.longitude is None
                ):
                    continue
                results.append(normalized)
            except Exception as exc:
                logger.warning(
                    "Error normalizing OSM element %s (id=%s): %s",
                    el.get("type"),
                    el.get("id"),
                    exc,
                )
        return results

    @classmethod
    async def fetch_raw_elements(
        cls,
        bbox: Optional[OSMBoundingBox] = None,
        client: Optional[httpx.AsyncClient] = None,
        max_retries: Optional[int] = None,
    ) -> list[dict[str, Any]]:
        """Call Overpass API interpreter using HTTP POST to fetch raw restaurant elements.

        Applies limited retries with backoff for HTTP 429, 5xx, timeouts, and network issues.
        """
        if bbox is None:
            bbox = OSMBoundingBox()

        retries = max_retries if max_retries is not None else settings.OVERPASS_MAX_RETRIES
        query = cls.build_overpass_query(
            bbox=bbox,
            timeout_seconds=int(settings.OVERPASS_TIMEOUT_SECONDS),
        )

        close_client_after = False
        if client is None:
            client = httpx.AsyncClient(timeout=settings.OVERPASS_TIMEOUT_SECONDS)
            close_client_after = True

        attempt = 0
        backoff = settings.OVERPASS_RETRY_BACKOFF_SECONDS

        try:
            while True:
                attempt += 1
                try:
                    logger.info(
                        "Calling Overpass API at %s (attempt %d/%d)",
                        settings.OVERPASS_API_URL,
                        attempt,
                        retries + 1,
                    )
                    response = await client.post(
                        settings.OVERPASS_API_URL,
                        data={"data": query},
                        headers={
                            "Accept": "application/json",
                            "User-Agent": "TravelWise-OSM-Importer/1.0",
                        },
                    )

                    # Handle 429 Too Many Requests or 5xx Server Errors
                    if response.status_code in {429, 500, 502, 503, 504}:
                        if attempt <= retries:
                            logger.warning(
                                "Overpass API returned HTTP %d, retrying in %.1fs...",
                                response.status_code,
                                backoff,
                            )
                            await asyncio.sleep(backoff)
                            backoff *= 2.0
                            continue
                        response.raise_for_status()

                    response.raise_for_status()

                    try:
                        data = response.json()
                    except ValueError as exc:
                        logger.error("Overpass returned invalid JSON: %s", exc)
                        raise HTTPException(
                            status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="Overpass API returned invalid JSON",
                        ) from exc

                    if not isinstance(data, dict) or "elements" not in data:
                        logger.error("Overpass response missing 'elements' key")
                        raise HTTPException(
                            status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="Overpass response missing elements list",
                        )

                    elements: list[dict[str, Any]] = data["elements"]
                    logger.info("Successfully fetched %d OSM elements", len(elements))
                    return elements

                except (httpx.TimeoutException, httpx.NetworkError) as net_err:
                    if attempt <= retries:
                        logger.warning(
                            "Overpass network/timeout error (%s), retrying in %.1fs...",
                            net_err,
                            backoff,
                        )
                        await asyncio.sleep(backoff)
                        backoff *= 2.0
                        continue
                    logger.error("Overpass API request failed after %d attempts: %s", attempt, net_err)
                    raise HTTPException(
                        status_code=status.HTTP_504_GATEWAY_TIMEOUT
                        if isinstance(net_err, httpx.TimeoutException)
                        else status.HTTP_502_BAD_GATEWAY,
                        detail="Overpass API service request failed or timed out",
                    ) from net_err

                except httpx.HTTPStatusError as http_err:
                    logger.error("Overpass HTTP error %s", http_err)
                    raise HTTPException(
                        status_code=status.HTTP_502_BAD_GATEWAY,
                        detail=f"Overpass API returned error status {http_err.response.status_code}",
                    ) from http_err

        finally:
            if close_client_after:
                await client.aclose()

    @classmethod
    async def get_normalized_restaurants(
        cls,
        bbox: Optional[OSMBoundingBox] = None,
        client: Optional[httpx.AsyncClient] = None,
        skip_unnamed: bool = False,
        skip_missing_coords: bool = False,
    ) -> list[NormalizedRestaurant]:
        """Fetch restaurants from Overpass API and return normalized restaurant models."""
        elements = await cls.fetch_raw_elements(bbox=bbox, client=client)
        return cls.normalize_elements(
            elements,
            skip_unnamed=skip_unnamed,
            skip_missing_coords=skip_missing_coords,
        )
