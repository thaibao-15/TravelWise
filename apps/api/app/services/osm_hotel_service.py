import asyncio
import logging
import re
from typing import Any, Optional
from urllib.parse import quote

from fastapi import HTTPException, status
import httpx

from app.core.config import settings
from app.schemas.osm_hotel import NormalizedHotel
from app.schemas.osm_restaurant import OSMBoundingBox

logger = logging.getLogger(__name__)


class OSMHotelService:
    """Service to fetch and normalize hotel data from OpenStreetMap via Overpass API."""

    @staticmethod
    def build_overpass_query(bbox: OSMBoundingBox, timeout_seconds: int = 60) -> str:
        """Construct Overpass QL query for tourism=hotel within bounding box.

        Includes node, way, and relation elements with 'out body center' to ensure
        ways and relations have center coordinates computed by Overpass.
        """
        bbox_str = f"{bbox.south},{bbox.west},{bbox.north},{bbox.east}"
        return (
            f"[out:json][timeout:{timeout_seconds}];\n"
            f"(\n"
            f'  node["tourism"="hotel"]({bbox_str});\n'
            f'  way["tourism"="hotel"]({bbox_str});\n'
            f'  relation["tourism"="hotel"]({bbox_str});\n'
            f");\n"
            f"out body center;\n"
        )

    @staticmethod
    def extract_coordinates(
        element: dict[str, Any],
    ) -> tuple[Optional[float], Optional[float]]:
        """Extract latitude and longitude for node, way, or relation.

        For nodes, lat and lon are at the root level.
        For ways and relations with 'out center', lat and lon are in element['center'].
        Returns (lat, lon) or (None, None) if invalid/absent.
        """
        lat: Optional[float] = None
        lon: Optional[float] = None

        # Check root level first (nodes)
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
        """Extract hotel name from primary or localized tags."""
        name = tags.get("name") or tags.get("name:vi") or tags.get("name:en") or tags.get("int_name")
        if name and isinstance(name, str):
            clean = name.strip()
            return clean if clean else None
        return None

    @staticmethod
    def extract_star_rating(tags: dict[str, Any]) -> Optional[int]:
        """Extract integer star rating if stars tag is present in OSM.

        Supports formats like '5', '4', '3.5', '4 stars'. Returns None if absent or invalid.
        """
        raw_stars = tags.get("stars")
        if not raw_stars:
            return None

        clean = str(raw_stars).strip()
        match = re.search(r"\d+(\.\d+)?", clean)
        if match:
            try:
                val = float(match.group(0))
                int_val = int(round(val))
                if 1 <= int_val <= 7:
                    return int_val
            except (ValueError, TypeError):
                pass
        return None

    @staticmethod
    def extract_integer_tag(tags: dict[str, Any], key: str) -> Optional[int]:
        """Extract integer count for tags like rooms or beds.

        Returns None if absent or non-numeric.
        """
        val = tags.get(key)
        if not val:
            return None

        clean = str(val).strip()
        match = re.search(r"^\d+", clean)
        if match:
            try:
                num = int(match.group(0))
                if num > 0:
                    return num
            except (ValueError, TypeError):
                pass
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
        """Extract address components and synthesized full address without heuristics.

        Returns (full_address, street, housenumber, district, city, postcode).
        """
        def _clean(val: Any) -> Optional[str]:
            if val and isinstance(val, str):
                s = val.strip()
                return s if s else None
            return None

        housenumber = _clean(tags.get("addr:housenumber") or tags.get("contact:housenumber"))
        street = _clean(tags.get("addr:street") or tags.get("contact:street"))
        district = _clean(
            tags.get("addr:district")
            or tags.get("addr:subdistrict")
            or tags.get("addr:suburb")
            or tags.get("addr:quarter")
        )
        city = _clean(tags.get("addr:city") or tags.get("contact:city"))
        postcode = _clean(tags.get("addr:postcode") or tags.get("contact:postcode"))

        # Explicit full address from tag
        full_addr = _clean(tags.get("addr:full"))
        if not full_addr:
            parts: list[str] = []
            if housenumber and street:
                parts.append(f"{housenumber} {street}")
            elif street:
                parts.append(street)
            elif housenumber:
                parts.append(housenumber)

            if district:
                parts.append(district)
            if city:
                parts.append(city)

            full_addr = ", ".join(parts) if parts else None

        return full_addr, street, housenumber, district, city, postcode

    @staticmethod
    def extract_contact_info(
        tags: dict[str, Any],
    ) -> tuple[Optional[str], Optional[str], Optional[str]]:
        """Extract phone, website, and email from standard and contact:* tags."""
        def _clean(val: Any) -> Optional[str]:
            if val and isinstance(val, str):
                s = val.strip()
                return s if s else None
            return None

        phone = _clean(tags.get("phone") or tags.get("contact:phone"))
        website = _clean(tags.get("website") or tags.get("contact:website") or tags.get("url"))
        email = _clean(tags.get("email") or tags.get("contact:email"))

        return phone, website, email

    @staticmethod
    def extract_image(
        tags: dict[str, Any],
    ) -> tuple[Optional[str], Optional[str]]:
        """Extract and sanitize image URL and Wikimedia Commons identifier.

        Returns (image_url, wikimedia_commons).
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

    @staticmethod
    def extract_amenities(tags: dict[str, Any]) -> list[str]:
        """Extract hotel amenities verified strictly against existing OSM tags.

        Does not invent or assume any amenities without explicit tag presence.
        """
        amenities: list[str] = []

        # Internet / Wifi
        net = str(tags.get("internet_access", "")).lower().strip()
        wifi = str(tags.get("wifi", "")).lower().strip()
        if net in {"yes", "wlan", "wifi", "wired", "terminal"} or wifi in {"yes", "free"}:
            amenities.append("wifi")
            if str(tags.get("internet_access:fee", "")).lower().strip() == "no" or wifi == "free":
                amenities.append("free_wifi")

        # Swimming pool
        pool = str(tags.get("swimming_pool", "")).lower().strip()
        if pool in {"yes", "outdoor", "indoor"} or str(tags.get("pool", "")).lower().strip() == "yes":
            amenities.append("swimming_pool")

        # Air conditioning
        if str(tags.get("air_conditioning", "")).lower().strip() == "yes":
            amenities.append("air_conditioning")

        # Parking
        parking = str(tags.get("parking", "")).lower().strip()
        if parking in {"yes", "surface", "underground", "multi-storey", "dedicated", "private"}:
            amenities.append("parking")
            if str(tags.get("parking:fee", "")).lower().strip() == "no":
                amenities.append("free_parking")

        # Accessibility
        wheelchair = str(tags.get("wheelchair", "")).lower().strip()
        if wheelchair in {"yes", "designated", "limited"}:
            amenities.append("wheelchair_accessible")

        # Breakfast
        breakfast = str(tags.get("breakfast", "")).lower().strip()
        if breakfast in {"yes", "included", "buffet"}:
            amenities.append("breakfast")

        # Restaurant / Bar
        if str(tags.get("restaurant", "")).lower().strip() == "yes" or tags.get("amenity") == "restaurant":
            amenities.append("restaurant")
        if str(tags.get("bar", "")).lower().strip() == "yes" or tags.get("amenity") == "bar":
            amenities.append("bar")

        # Wellness / Fitness
        if str(tags.get("spa", "")).lower().strip() == "yes" or tags.get("leisure") == "spa":
            amenities.append("spa")
        if (
            str(tags.get("gym", "")).lower().strip() == "yes"
            or str(tags.get("fitness_centre", "")).lower().strip() == "yes"
            or tags.get("leisure") == "fitness_centre"
        ):
            amenities.append("fitness_centre")

        # Elevator
        lift = str(tags.get("elevator", "")).lower().strip() or str(tags.get("lift", "")).lower().strip()
        if lift in {"yes", "true"}:
            amenities.append("elevator")

        # Smoking rules
        smoking = str(tags.get("smoking", "")).lower().strip()
        if smoking in {"no", "none"}:
            amenities.append("non_smoking")
        elif smoking in {"yes", "dedicated", "separated", "outside"}:
            amenities.append("smoking_area")

        # Outdoor seating
        if str(tags.get("outdoor_seating", "")).lower().strip() == "yes":
            amenities.append("outdoor_seating")

        # Self-service
        if str(tags.get("self_service", "")).lower().strip() == "yes":
            amenities.append("self_service")

        return sorted(list(set(amenities)))

    @classmethod
    def normalize_element(
        cls,
        element: dict[str, Any],
    ) -> tuple[Optional[NormalizedHotel], Optional[str]]:
        """Normalize a raw Overpass hotel element into NormalizedHotel.

        Returns:
            (NormalizedHotel, None) if valid.
            (None, rejection_reason) if invalid.
        """
        osm_id = element.get("id")
        osm_type = element.get("type")
        if not osm_id or not osm_type:
            return None, "Missing osm_id or osm_type"

        tags: dict[str, Any] = element.get("tags") or {}

        # 1. Name check
        name = cls.extract_name(tags)
        if not name:
            lat, lon = cls.extract_coordinates(element)
            if lat is None or lon is None:
                return None, "Missing both name and coordinates"
            return None, "Missing name"

        # 2. Coordinates check
        lat, lon = cls.extract_coordinates(element)
        if lat is None or lon is None:
            return None, "Missing coordinates"

        # 3. Address components
        full_addr, street, housenumber, district, city, postcode = cls.extract_address(tags)

        # 4. Contact info
        phone, website, email = cls.extract_contact_info(tags)

        # 5. Hotel attributes
        star_rating = cls.extract_star_rating(tags)
        rooms = cls.extract_integer_tag(tags, "rooms")
        beds = cls.extract_integer_tag(tags, "beds")

        # 6. Opening hours
        opening_hours_raw = tags.get("opening_hours")
        if opening_hours_raw and isinstance(opening_hours_raw, str):
            opening_hours_raw = opening_hours_raw.strip() or None
        else:
            opening_hours_raw = None

        # 7. Amenities
        amenities = cls.extract_amenities(tags)

        # 8. Images
        image_url, wikimedia_commons = cls.extract_image(tags)

        # 9. Raw tags copy
        raw_tags = {str(k): str(v) for k, v in tags.items() if v is not None}

        hotel = NormalizedHotel(
            osm_id=int(osm_id),
            osm_type=str(osm_type),
            name=name,
            latitude=lat,
            longitude=lon,
            address=full_addr,
            street=street,
            housenumber=housenumber,
            district=district,
            city=city,
            postcode=postcode,
            phone=phone,
            website=website,
            email=email,
            star_rating=star_rating,
            rooms=rooms,
            beds=beds,
            opening_hours_raw=opening_hours_raw,
            amenities=amenities,
            image_url=image_url,
            wikimedia_commons=wikimedia_commons,
            raw_tags=raw_tags,
        )

        return hotel, None

    @classmethod
    def normalize_elements(
        cls,
        elements: list[dict[str, Any]],
    ) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
        """Normalize raw hotel elements into valid list, discarded list, and statistics.

        Deduplicates strictly by (osm_type, osm_id).
        """
        seen_keys: set[tuple[str, int]] = set()
        valid_records: list[dict[str, Any]] = []
        discarded_records: list[dict[str, Any]] = []
        duplicate_count = 0

        rejection_breakdown: dict[str, int] = {}

        for el in elements:
            el_type = str(el.get("type", ""))
            el_id = el.get("id")

            # Check duplication
            if el_id is not None:
                key = (el_type, int(el_id))
                if key in seen_keys:
                    duplicate_count += 1
                    discarded_records.append({
                        "osm_type": el_type,
                        "osm_id": el_id,
                        "reason": "Duplicate element (osm_type + osm_id)",
                        "tags": el.get("tags") or {},
                    })
                    rejection_breakdown["Duplicate element"] = rejection_breakdown.get("Duplicate element", 0) + 1
                    continue
                seen_keys.add(key)

            hotel, reason = cls.normalize_element(el)
            if hotel:
                valid_records.append(hotel.model_dump(mode="json"))
            else:
                reason_str = reason or "Invalid element"
                rejection_breakdown[reason_str] = rejection_breakdown.get(reason_str, 0) + 1
                discarded_records.append({
                    "osm_type": el_type,
                    "osm_id": el_id,
                    "reason": reason_str,
                    "tags": el.get("tags") or {},
                })

        # Calculate statistics
        with_image = sum(1 for h in valid_records if h.get("image_url") or h.get("wikimedia_commons"))
        with_stars = sum(1 for h in valid_records if h.get("star_rating") is not None)
        with_website = sum(1 for h in valid_records if h.get("website"))
        with_phone = sum(1 for h in valid_records if h.get("phone"))
        with_email = sum(1 for h in valid_records if h.get("email"))
        with_address = sum(1 for h in valid_records if h.get("address"))
        with_amenities = sum(1 for h in valid_records if len(h.get("amenities") or []) > 0)
        with_rooms = sum(1 for h in valid_records if h.get("rooms") is not None)

        stats = {
            "total_input": len(elements),
            "valid_count": len(valid_records),
            "discarded_count": len(discarded_records),
            "duplicate_count": duplicate_count,
            "rejection_breakdown": rejection_breakdown,
            "attributes": {
                "with_image": with_image,
                "with_star_rating": with_stars,
                "with_website": with_website,
                "with_phone": with_phone,
                "with_email": with_email,
                "with_address": with_address,
                "with_amenities": with_amenities,
                "with_rooms": with_rooms,
            },
        }

        return valid_records, discarded_records, stats

    @classmethod
    async def fetch_raw_elements(
        cls,
        bbox: Optional[OSMBoundingBox] = None,
        client: Optional[httpx.AsyncClient] = None,
        max_retries: Optional[int] = None,
    ) -> list[dict[str, Any]]:
        """Call Overpass API interpreter using HTTP POST to fetch raw hotel elements."""
        if bbox is None:
            bbox = OSMBoundingBox(
                south=15.9,
                west=107.8,
                north=16.3,
                east=108.4,
            )

        retries = max_retries if max_retries is not None else settings.OVERPASS_MAX_RETRIES
        query = cls.build_overpass_query(
            bbox=bbox,
            timeout_seconds=int(settings.OVERPASS_TIMEOUT_SECONDS),
        )

        close_client_after = False
        if client is None:
            client = httpx.AsyncClient(timeout=settings.OVERPASS_TIMEOUT_SECONDS)
            close_client_after = True

        backoff = float(settings.OVERPASS_RETRY_BACKOFF_SECONDS)
        headers = {
            "User-Agent": "TravelWise-OSM-Importer/1.0 (contact: info@travelwise.local)",
            "Accept": "application/json",
        }

        try:
            for attempt in range(1, retries + 2):
                try:
                    logger.info(
                        "Overpass hotel query attempt %d/%d (endpoint=%s)",
                        attempt,
                        retries + 1,
                        settings.OVERPASS_API_URL,
                    )
                    resp = await client.post(
                        settings.OVERPASS_API_URL,
                        data={"data": query},
                        headers=headers,
                    )

                    # Transient rate limits or upstream errors
                    if resp.status_code in {429, 500, 502, 503, 504}:
                        if attempt <= retries:
                            logger.warning(
                                "Overpass API returned status %d. Retrying in %.1fs...",
                                resp.status_code,
                                backoff,
                            )
                            await asyncio.sleep(backoff)
                            backoff *= 2.0
                            continue
                        resp.raise_for_status()

                    resp.raise_for_status()

                    try:
                        data = resp.json()
                    except ValueError as exc:
                        logger.error("Overpass response is not valid JSON: %s", exc)
                        raise HTTPException(
                            status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="Overpass API returned an invalid JSON response.",
                        ) from exc

                    elements = data.get("elements")
                    if not isinstance(elements, list):
                        raise HTTPException(
                            status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="Overpass API response missing 'elements' list.",
                        )

                    logger.info(
                        "Successfully fetched %d raw hotel elements from Overpass.",
                        len(elements),
                    )
                    return elements

                except (httpx.TimeoutException, httpx.NetworkError) as net_err:
                    if attempt <= retries:
                        logger.warning(
                            "Network/Timeout contacting Overpass API (%s). Retrying in %.1fs...",
                            net_err,
                            backoff,
                        )
                        await asyncio.sleep(backoff)
                        backoff *= 2.0
                        continue
                    logger.error(
                        "Exhausted retries connecting to Overpass API: %s", net_err
                    )
                    raise HTTPException(
                        status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                        detail=f"Unable to reach Overpass API after {retries + 1} attempts.",
                    ) from net_err

                except httpx.HTTPStatusError as http_err:
                    logger.error(
                        "Overpass HTTP error %d: %s",
                        http_err.response.status_code,
                        http_err,
                    )
                    raise HTTPException(
                        status_code=status.HTTP_502_BAD_GATEWAY,
                        detail=f"Overpass API returned HTTP error: {http_err.response.status_code}",
                    ) from http_err

            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail="Overpass API request failed after all retry attempts.",
            )

        finally:
            if close_client_after:
                await client.aclose()
