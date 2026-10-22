"""
Place Search Service for TravelWise AI Itinerary.

Queries real places from Microsoft SQL Server based on TripPlanningContext.
Implements:
- Geographic / destination filtering (primary & additional destinations).
- Category filtering and synonym mapping.
- Prioritized matching of must-visit and preferred places.
- Exclusion of unwanted places and categories.
- Multi-criteria relevance scoring and ranking.
- Data completeness evaluation and safe handling of missing fields (price, hours).
"""

from decimal import Decimal
import logging
import math
import unicodedata
from typing import Any, Dict, List, Optional, Set, Tuple

from sqlalchemy.orm import selectinload
from sqlmodel import Session, select

from app.models.category import Category
from app.models.hotel_detail import HotelDetail
from app.models.opening_hours import OpeningHours
from app.models.place import Place
from app.models.restaurant_detail import RestaurantDetail
from app.schemas.place_search import (
    PlaceSearchResponse,
    SearchPlaceItem,
    UnresolvedMustVisitItem,
)
from app.schemas.trip_planning import PlaceRequirementItem, TripPlanningContext

logger = logging.getLogger(__name__)


# -----------------------------------------------------------------------------
# Category Synonyms & Aliases Mapping
# Maps database Category.name to common Vietnamese and English search keywords
# -----------------------------------------------------------------------------
CATEGORY_ALIASES: Dict[str, List[str]] = {
    "Restaurant": [
        "restaurant", "nhà hàng", "quán ăn", "ăn uống", "ẩm thực", "dining",
        "seafood", "hải sản", "cơm", "bún", "phở",
    ],
    "Street Food": [
        "street food", "ẩm thực đường phố", "đồ ăn vặt", "quán vỉa hè", "chợ đêm",
        "bánh tráng", "chè",
    ],
    "Cafe": [
        "cafe", "cà phê", "coffee", "trà sữa", "nước uống", "tiệm cafe", "quán cafe",
    ],
    "Hotel": [
        "hotel", "khách sạn", "resort", "homestay", "nghỉ dưỡng", "lưu trú",
        "chỗ ở", "accommodation",
    ],
    "Beach": [
        "beach", "bãi biển", "biển", "tắm biển", "bờ biển", "seaside",
    ],
    "Museum": [
        "museum", "bảo tàng", "di tích", "lịch sử", "văn hóa", "trưng bày",
        "triển lãm", "culture", "history",
    ],
    "Park": [
        "park", "công viên", "khu du lịch", "vui chơi", "giải trí", "thắng cảnh",
        "attraction", "núi", "đồi", "rừng", "nature", "thiên nhiên",
    ],
    "Bar": [
        "bar", "pub", "lounge", "về đêm", "nightlife", "rượu", "bia",
    ],
    "Mall": [
        "mall", "trung tâm thương mại", "mua sắm", "shopping", "chợ", "market",
    ],
    "Temple": [
        "temple", "pagoda", "chùa", "đền", "miếu", "tâm linh", "phật giáo",
        "nhà thờ", "spiritual",
    ],
}

# -----------------------------------------------------------------------------
# Interest Keywords Mapping
# Maps user interest keywords to category names and semantic content cues
# -----------------------------------------------------------------------------
INTEREST_MAPPINGS: Dict[str, Dict[str, Any]] = {
    "beach": {
        "categories": ["Beach"],
        "keywords": ["biển", "bãi biển", "tắm biển", "bờ biển", "cát trắng"],
    },
    "biển": {
        "categories": ["Beach"],
        "keywords": ["biển", "bãi biển", "tắm biển", "bờ biển"],
    },
    "culture": {
        "categories": ["Museum", "Temple"],
        "keywords": ["văn hóa", "lịch sử", "kiến trúc", "di tích", "tâm linh", "phật giáo"],
    },
    "văn hóa": {
        "categories": ["Museum", "Temple"],
        "keywords": ["văn hóa", "lịch sử", "kiến trúc", "di tích", "tâm linh"],
    },
    "history": {
        "categories": ["Museum"],
        "keywords": ["lịch sử", "di tích", "chiến tích", "bảo tàng", "xưa"],
    },
    "lịch sử": {
        "categories": ["Museum"],
        "keywords": ["lịch sử", "di tích", "chiến tích", "bảo tàng"],
    },
    "nature": {
        "categories": ["Park", "Beach"],
        "keywords": ["thiên nhiên", "núi", "rừng", "bán đảo", "sinh thái", "cảnh quan", "đèo"],
    },
    "thiên nhiên": {
        "categories": ["Park", "Beach"],
        "keywords": ["thiên nhiên", "núi", "rừng", "bán đảo", "sinh thái", "cảnh quan", "đèo"],
    },
    "food": {
        "categories": ["Restaurant", "Street Food", "Cafe"],
        "keywords": ["ẩm thực", "hải sản", "món ăn", "đặc sản", "quán ngon"],
    },
    "ẩm thực": {
        "categories": ["Restaurant", "Street Food", "Cafe"],
        "keywords": ["ẩm thực", "hải sản", "món ăn", "đặc sản", "quán ngon"],
    },
    "seafood": {
        "categories": ["Restaurant"],
        "keywords": ["hải sản", "tôm", "cua", "cá", "mực"],
    },
    "hải sản": {
        "categories": ["Restaurant"],
        "keywords": ["hải sản", "tôm", "cua", "cá", "mực"],
    },
    "nightlife": {
        "categories": ["Bar", "Street Food"],
        "keywords": ["về đêm", "buổi tối", "phun lửa", "chiếu sáng", "cầu rồng", "lung linh"],
    },
    "nghỉ dưỡng": {
        "categories": ["Hotel", "Beach"],
        "keywords": ["nghỉ dưỡng", "thư giãn", "resort", "yên tĩnh"],
    },
    "chụp ảnh": {
        "categories": ["Park", "Beach", "Temple"],
        "keywords": ["chụp ảnh", "check-in", "sống ảo", "tầm nhìn", "cảnh đẹp"],
    },
}


def remove_accents(text: Optional[str]) -> str:
    """Normalize Vietnamese text by stripping accents and lowercasing."""
    if not text:
        return ""
    clean = text.replace("đ", "d").replace("Đ", "D").strip()
    nfkd = unicodedata.normalize("NFD", clean)
    stripped = "".join([c for c in nfkd if not unicodedata.combining(c)])
    return stripped.lower()


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculates great-circle distance in kilometers between two lat/lon coordinates."""
    r = 6371.0  # Earth's radius in km
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return r * c


def evaluate_data_completeness(place: Place) -> str:
    """Evaluates place data completeness based on available fields."""
    has_coords = place.latitude is not None and place.longitude is not None
    has_addr = bool(place.address and place.address.strip())
    has_desc = bool(place.description and place.description.strip())
    has_cat = place.category_id is not None
    has_details = bool(place.restaurant_detail or place.hotel_detail or place.images)

    if has_coords and has_addr and has_desc and has_cat and has_details:
        return "FULL"
    if has_coords and has_addr and (has_desc or has_cat):
        return "PARTIAL"
    return "MINIMAL"


def format_opening_hours(hours: List[OpeningHours]) -> Optional[str]:
    """Formats list of OpeningHours into readable display string."""
    if not hours:
        return None
    # Pick first available or standard weekday time
    h = hours[0]
    if h.open_time and h.close_time:
        return f"{h.open_time.strftime('%H:%M')} - {h.close_time.strftime('%H:%M')}"
    return None


def extract_price_and_info(place: Place) -> Tuple[Optional[float], Optional[str]]:
    """Extracts numeric price and text price_info safely without guessing."""
    if place.hotel_detail and place.hotel_detail.price_per_night is not None:
        val = float(place.hotel_detail.price_per_night)
        return val, f"{val:,.0f} VND/đêm"

    if place.restaurant_detail and place.restaurant_detail.price_range:
        return None, place.restaurant_detail.price_range

    return None, None


class PlaceSearchService:
    """Service responsible for searching, filtering and scoring places from SQL Server."""

    @classmethod
    def search_places_for_itinerary(
        cls,
        session: Session,
        context: TripPlanningContext,
        skip: int = 0,
        limit: int = 100,
        reference_lat: Optional[float] = None,
        reference_lon: Optional[float] = None,
    ) -> PlaceSearchResponse:
        """Executes full place search pipeline for itinerary planning.

        Steps:
        1. Parse context requirements (destinations, must_visit, excluded, categories, interests).
        2. Query all active places from SQL Server with eager-loaded relations (avoids N+1).
        3. Match requested must_visit items; resolve found vs unresolved.
        4. Apply hard filters (is_deleted, excluded places, categories to avoid, destination filtering).
        5. Score and rank candidates based on relevance, interests, preferred, completeness, distance.
        6. Paginate results and return PlaceSearchResponse.
        """
        warnings: List[str] = []

        # 1. Parse Destinations
        primary_city = (context.trip.destination.city or "").strip()
        additional_destinations = [
            d.strip() for d in context.trip.destination.additional_destinations if d and d.strip()
        ]

        target_destinations = []
        if primary_city:
            target_destinations.append(primary_city)
        target_destinations.extend(additional_destinations)

        if not target_destinations:
            if reference_lat is not None and reference_lon is not None:
                warnings.append("Đang ưu tiên các địa điểm trong bán kính 50 km từ vị trí hiện tại.")
            else:
                warnings.append("Chuyến đi chưa có điểm đến cụ thể; kết quả tìm kiếm không bị giới hạn theo khu vực.")

        # 2. Query all active places with eager-loaded relations
        statement = (
            select(Place)
            .where(Place.is_deleted == False)  # noqa: E712
            .options(
                selectinload(Place.category),
                selectinload(Place.restaurant_detail),
                selectinload(Place.hotel_detail),
                selectinload(Place.opening_hours),
                selectinload(Place.images),
            )
        )
        all_places = list(session.exec(statement).all())

        if not all_places:
            return PlaceSearchResponse(
                destination=primary_city or None,
                places=[],
                unresolved_must_visit=[],
                warnings=warnings,
                total=0,
                skip=skip,
                limit=limit,
            )

        # 3. Match Must-Visit places
        must_visit_reqs = context.place_requirements.must_visit
        resolved_must_visit_ids: Set[int] = set()
        unresolved_must_visit: List[UnresolvedMustVisitItem] = []

        for mv_item in must_visit_reqs:
            mv_name = mv_item.name.strip()
            mv_norm = remove_accents(mv_name)
            matched_place: Optional[Place] = None

            for p in all_places:
                p_norm = remove_accents(p.name)
                # Exact or reciprocal substring matching
                if mv_norm == p_norm or (len(mv_norm) >= 4 and mv_norm in p_norm) or (len(p_norm) >= 4 and p_norm in mv_norm):
                    matched_place = p
                    break

            if matched_place:
                resolved_must_visit_ids.add(matched_place.id)
            else:
                unresolved_must_visit.append(
                    UnresolvedMustVisitItem(
                        name=mv_name,
                        priority=mv_item.priority,
                        reason="Không tìm thấy trong cơ sở dữ liệu địa phương",
                    )
                )

        # 4. Parse Excluded & Categories to Avoid (Hard Filters)
        excluded_names_norm: Set[str] = {
            remove_accents(item.name.strip())
            for item in context.place_requirements.excluded
            if item.name and item.name.strip()
        }

        categories_to_avoid_norm: Set[str] = {
            remove_accents(c.strip())
            for c in context.place_requirements.place_categories_to_avoid
            if c and c.strip()
        }

        # Categories to Include
        categories_to_include_norm: Set[str] = {
            remove_accents(c.strip())
            for c in context.place_requirements.place_categories_to_include
            if c and c.strip()
        }

        # Preferred Places
        preferred_names_norm: Set[str] = {
            remove_accents(item.name.strip())
            for item in context.place_requirements.preferred
            if item.name and item.name.strip()
        }

        # User Interests & Preferences
        user_interests = [
            i.strip() for i in context.preferences.interests if i and i.strip()
        ]
        user_interests.extend([
            s.strip() for s in context.preferences.travel_style if s and s.strip()
        ])
        user_interests.extend([
            f.strip() for f in context.preferences.food.interested_in if f and f.strip()
        ])

        # 5. Filter and Score Candidates
        scored_candidates: List[SearchPlaceItem] = []

        for place in all_places:
            p_name_norm = remove_accents(place.name)
            p_addr_norm = remove_accents(place.address or "")
            p_desc_norm = remove_accents(place.description or "")
            cat_name = place.category.name if place.category else None
            cat_name_norm = remove_accents(cat_name or "")

            is_must_visit = place.id in resolved_must_visit_ids

            if (
                not target_destinations
                and reference_lat is not None
                and reference_lon is not None
                and place.latitude is not None
                and place.longitude is not None
                and haversine_distance(reference_lat, reference_lon, place.latitude, place.longitude) > 50
                and not is_must_visit
            ):
                continue

            # HARD FILTER: Excluded places by name
            if not is_must_visit and any(
                ex_norm in p_name_norm or p_name_norm in ex_norm
                for ex_norm in excluded_names_norm
                if len(ex_norm) >= 3
            ):
                continue

            # HARD FILTER: Categories to avoid
            should_avoid = False
            if not is_must_visit and categories_to_avoid_norm:
                if cat_name_norm and any(
                    avoid_norm in cat_name_norm or cat_name_norm in avoid_norm
                    for avoid_norm in categories_to_avoid_norm
                ):
                    should_avoid = True

                if not should_avoid:
                    for avoid_item in categories_to_avoid_norm:
                        if avoid_item in p_name_norm:
                            should_avoid = True
                            break
                        for db_cat, aliases in CATEGORY_ALIASES.items():
                            db_cat_norm = remove_accents(db_cat)
                            alias_norms = [remove_accents(a) for a in aliases]
                            if avoid_item == db_cat_norm or avoid_item in alias_norms:
                                if any(a in p_name_norm for a in alias_norms if len(a) >= 4):
                                    should_avoid = True
                                    break
                        if should_avoid:
                            break

            if should_avoid:
                continue

            # GEOGRAPHIC FILTER:
            # If destinations specified, check if place address or name matches
            matches_primary_destination = False
            matches_additional_destination = False

            if target_destinations:
                if primary_city:
                    prim_norm = remove_accents(primary_city)
                    if prim_norm in p_addr_norm or prim_norm in p_name_norm:
                        matches_primary_destination = True

                for add_dest in additional_destinations:
                    add_norm = remove_accents(add_dest)
                    if add_norm in p_addr_norm or add_norm in p_name_norm:
                        matches_additional_destination = True
                        break

                # If place does not match any specified destination and is NOT a must-visit, filter out
                if not matches_primary_destination and not matches_additional_destination and not is_must_visit:
                    continue

            # SCORING & MATCH REASONS
            score = 0.0
            match_reasons: List[str] = []
            matched_interests: List[str] = []

            # (1) Must-visit boost
            if is_must_visit:
                score += 10.0
                match_reasons.append("Địa điểm bắt buộc trong kế hoạch (Must-Visit)")

            # (2) Preferred place boost
            is_preferred = any(
                pref_norm in p_name_norm or p_name_norm in pref_norm
                for pref_norm in preferred_names_norm
                if len(pref_norm) >= 3
            )
            if is_preferred:
                score += 2.0
                match_reasons.append("Địa điểm được ưu tiên yêu cầu")

            # (3) Destination relevance
            if matches_primary_destination:
                score += 1.5
                match_reasons.append(f"Thuộc điểm đến chính '{primary_city}'")
            elif matches_additional_destination:
                score += 1.0
                match_reasons.append("Thuộc điểm đến kết hợp trong chuyến đi")

            # (4) Category inclusion filter/boost
            if categories_to_include_norm:
                cat_match = False
                for inc_cat in categories_to_include_norm:
                    # Check direct or synonym match
                    if (cat_name_norm and (inc_cat in cat_name_norm or cat_name_norm in inc_cat)) or (inc_cat in p_name_norm):
                        cat_match = True
                        break
                    # Check synonyms
                    for db_cat, aliases in CATEGORY_ALIASES.items():
                        db_cat_norm = remove_accents(db_cat)
                        alias_norms = [remove_accents(a) for a in aliases]
                        if inc_cat == db_cat_norm or inc_cat in alias_norms:
                            if cat_name_norm == db_cat_norm or any(a in p_name_norm for a in alias_norms if len(a) >= 4):
                                cat_match = True
                                break
                    if cat_match:
                        break
                if cat_match:
                    score += 1.5
                    match_reasons.append(f"Thuộc danh mục quan tâm: {cat_name or place.name}")

            # (5) Interest matching
            for interest in user_interests:
                int_norm = remove_accents(interest)
                interest_matched = False

                # Check pre-defined interest mapping
                mapping = INTEREST_MAPPINGS.get(int_norm)
                if mapping:
                    if cat_name in mapping["categories"]:
                        interest_matched = True
                    elif any(kw in p_desc_norm or kw in p_name_norm for kw in mapping["keywords"]):
                        interest_matched = True
                else:
                    # Generic semantic search in description, name or category
                    if (
                        int_norm in p_desc_norm
                        or int_norm in p_name_norm
                        or int_norm in cat_name_norm
                    ):
                        interest_matched = True

                if interest_matched and interest not in matched_interests:
                    matched_interests.append(interest)
                    score += 1.0
                    match_reasons.append(f"Phù hợp với sở thích '{interest}'")

            # (6) Data Completeness
            completeness = evaluate_data_completeness(place)
            if completeness == "FULL":
                score += 0.5
            elif completeness == "PARTIAL":
                score += 0.3
            else:
                score += 0.1

            # (7) Proximity / Distance
            ref_lat = reference_lat
            ref_lon = reference_lon
            # If no reference coordinates provided, pick first must-visit place coordinates if available
            if ref_lat is None and resolved_must_visit_ids:
                first_mv = next((p for p in all_places if p.id in resolved_must_visit_ids and p.latitude), None)
                if first_mv:
                    ref_lat = first_mv.latitude
                    ref_lon = first_mv.longitude

            if ref_lat is not None and ref_lon is not None and place.latitude and place.longitude:
                dist_km = haversine_distance(ref_lat, ref_lon, place.latitude, place.longitude)
                # Closer places get small distance bonus
                dist_bonus = max(0.0, 1.0 - (dist_km / 50.0))
                score += dist_bonus

            # Extract price and hours
            price_val, price_info_text = extract_price_and_info(place)
            opening_hours_text = format_opening_hours(place.opening_hours)

            item = SearchPlaceItem(
                place_id=place.id,
                name=place.name,
                category=cat_name,
                category_id=place.category_id,
                address=place.address,
                latitude=place.latitude,
                longitude=place.longitude,
                price=price_val,
                price_info=price_info_text,
                opening_hours=opening_hours_text,
                matched_interests=matched_interests,
                is_must_visit=is_must_visit,
                is_preferred=is_preferred,
                match_reasons=match_reasons,
                score=round(score, 2),
                data_completeness=completeness,
            )
            scored_candidates.append(item)

        # 6. Sort by score descending, then by name ascending
        scored_candidates.sort(key=lambda x: (-x.score, x.name))

        total_count = len(scored_candidates)
        paginated_places = scored_candidates[skip : skip + limit]

        return PlaceSearchResponse(
            destination=primary_city or None,
            places=paginated_places,
            unresolved_must_visit=unresolved_must_visit,
            warnings=warnings,
            total=total_count,
            skip=skip,
            limit=limit,
        )
