"""
TripPlanningContext schema and submodels.

Standardized Pydantic models for Conversation-Based Trip Planning Context Extraction.
"""

from datetime import datetime
from enum import Enum
import re
from typing import Any, List, Optional, Union
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


# -----------------------------------------------------------------------------
# Base Normalizing Enum
# -----------------------------------------------------------------------------
class RobustEnum(str, Enum):
    """Enum that case-insensitively normalizes values or falls back gracefully."""

    @classmethod
    def _missing_(cls, value: Any):
        if isinstance(value, str):
            normalized = value.strip().upper()
            for member in cls:
                if member.value == normalized:
                    return member
        # Fallback to UNKNOWN if defined on enum
        if hasattr(cls, "UNKNOWN"):
            return cls.UNKNOWN
        return super()._missing_(value)


class DestinationFlexibilityEnum(RobustEnum):
    UNKNOWN = "UNKNOWN"
    FIXED = "FIXED"
    FLEXIBLE = "FLEXIBLE"


class DateFlexibilityEnum(RobustEnum):
    UNKNOWN = "UNKNOWN"
    EXACT = "EXACT"
    FLEXIBLE = "FLEXIBLE"


class GroupTypeEnum(RobustEnum):
    UNKNOWN = "UNKNOWN"
    SOLO = "SOLO"
    COUPLE = "COUPLE"
    FAMILY = "FAMILY"
    FRIENDS = "FRIENDS"
    BUSINESS = "BUSINESS"
    OTHER = "OTHER"


class TripStatusEnum(RobustEnum):
    DRAFT = "DRAFT"
    PLANNING = "PLANNING"
    CONFIRMED = "CONFIRMED"
    COMPLETED = "COMPLETED"


class BudgetScopeEnum(RobustEnum):
    UNKNOWN = "UNKNOWN"
    TOTAL = "TOTAL"
    PER_PERSON = "PER_PERSON"


class BudgetFlexibilityEnum(RobustEnum):
    UNKNOWN = "UNKNOWN"
    STRICT = "STRICT"
    MODERATE = "MODERATE"
    FLEXIBLE = "FLEXIBLE"


class ActivityIntensityEnum(RobustEnum):
    UNKNOWN = "UNKNOWN"
    LOW = "LOW"
    MODERATE = "MODERATE"
    HIGH = "HIGH"


class SchedulePaceEnum(RobustEnum):
    UNKNOWN = "UNKNOWN"
    RELAXED = "RELAXED"
    MODERATE = "MODERATE"
    FAST = "FAST"


class MissingInfoImportanceEnum(RobustEnum):
    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"


# -----------------------------------------------------------------------------
# Sub-models
# -----------------------------------------------------------------------------
class DestinationInfo(BaseModel):
    city: Optional[str] = None
    country: Optional[str] = None
    additional_destinations: List[str] = Field(default_factory=list)
    destination_flexibility: DestinationFlexibilityEnum = DestinationFlexibilityEnum.UNKNOWN

    model_config = ConfigDict(use_enum_values=True)


class DateInfo(BaseModel):
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    duration_days: Optional[int] = None
    nights: Optional[int] = None
    date_flexibility: DateFlexibilityEnum = DateFlexibilityEnum.UNKNOWN

    @field_validator("start_date", "end_date", mode="before")
    @classmethod
    def validate_date_str(cls, v: Any) -> Optional[str]:
        if v is None:
            return None
        v_str = str(v).strip()
        if not v_str:
            return None
        # ISO format YYYY-MM-DD
        if re.match(r"^\d{4}-\d{2}-\d{2}$", v_str):
            try:
                datetime.strptime(v_str, "%Y-%m-%d")
                return v_str
            except ValueError:
                return None
        return None

    @field_validator("duration_days", mode="before")
    @classmethod
    def validate_duration_days(cls, v: Any) -> Optional[int]:
        if v is None:
            return None
        try:
            val = int(v)
            return val if val >= 1 else None
        except (ValueError, TypeError):
            return None

    @field_validator("nights", mode="before")
    @classmethod
    def validate_nights(cls, v: Any) -> Optional[int]:
        if v is None:
            return None
        try:
            val = int(v)
            return val if val >= 0 else None
        except (ValueError, TypeError):
            return None

    model_config = ConfigDict(use_enum_values=True)


class TravelersInfo(BaseModel):
    adults: Optional[int] = None
    children: Optional[int] = None
    group_type: GroupTypeEnum = GroupTypeEnum.UNKNOWN
    special_traveler_needs: List[str] = Field(default_factory=list)

    @field_validator("adults", "children", mode="before")
    @classmethod
    def validate_count(cls, v: Any) -> Optional[int]:
        if v is None:
            return None
        try:
            val = int(v)
            return val if val >= 0 else None
        except (ValueError, TypeError):
            return None

    model_config = ConfigDict(use_enum_values=True)


class TripInfo(BaseModel):
    trip_id: Optional[int] = None
    conversation_id: Optional[int] = None
    name: Optional[str] = None
    destination: DestinationInfo = Field(default_factory=DestinationInfo)
    dates: DateInfo = Field(default_factory=DateInfo)
    travelers: TravelersInfo = Field(default_factory=TravelersInfo)
    purpose: List[str] = Field(default_factory=list)
    status: TripStatusEnum = TripStatusEnum.DRAFT

    model_config = ConfigDict(use_enum_values=True)


class BudgetAllocation(BaseModel):
    transport: Optional[float] = None
    accommodation: Optional[float] = None
    food: Optional[float] = None
    tickets: Optional[float] = None
    other: Optional[float] = None

    @field_validator("*", mode="before")
    @classmethod
    def validate_allocation(cls, v: Any) -> Optional[float]:
        if v is None:
            return None
        try:
            val = float(v)
            return val if val >= 0 else None
        except (ValueError, TypeError):
            return None


class BudgetInfo(BaseModel):
    total: Optional[float] = None
    currency: str = "VND"
    scope: BudgetScopeEnum = BudgetScopeEnum.UNKNOWN
    includes_transport_to_destination: Optional[bool] = None
    includes_accommodation: Optional[bool] = None
    includes_food: Optional[bool] = None
    includes_tickets: Optional[bool] = None
    allocation: BudgetAllocation = Field(default_factory=BudgetAllocation)
    flexibility: BudgetFlexibilityEnum = BudgetFlexibilityEnum.UNKNOWN

    @field_validator("total", mode="before")
    @classmethod
    def validate_total(cls, v: Any) -> Optional[float]:
        if v is None:
            return None
        if isinstance(v, (int, float)):
            return float(v) if float(v) >= 0 else None
        # String parse e.g. "4000000" or "4 triệu"
        clean = re.sub(r"[^\d.]", "", str(v))
        try:
            val = float(clean)
            return val if val >= 0 else None
        except (ValueError, TypeError):
            return None

    model_config = ConfigDict(use_enum_values=True)


class TransportPreferences(BaseModel):
    preferred: List[str] = Field(default_factory=list)
    available: List[str] = Field(default_factory=list)
    avoid: List[str] = Field(default_factory=list)


class AccommodationPreferences(BaseModel):
    type_preferred: List[str] = Field(default_factory=list)
    location_preference: Optional[str] = None
    must_have_amenities: List[str] = Field(default_factory=list)
    avoid: List[str] = Field(default_factory=list)


class FoodPreferences(BaseModel):
    interested_in: List[str] = Field(default_factory=list)
    dietary_restrictions: List[str] = Field(default_factory=list)
    disliked_foods: List[str] = Field(default_factory=list)
    preferred_price_range: Optional[str] = None


class ActivityPreferences(BaseModel):
    preferred: List[str] = Field(default_factory=list)
    avoided: List[str] = Field(default_factory=list)
    activity_intensity: ActivityIntensityEnum = ActivityIntensityEnum.UNKNOWN

    model_config = ConfigDict(use_enum_values=True)


class TripPreferencesInfo(BaseModel):
    travel_style: List[str] = Field(default_factory=list)
    interests: List[str] = Field(default_factory=list)
    transport: TransportPreferences = Field(default_factory=TransportPreferences)
    accommodation: AccommodationPreferences = Field(default_factory=AccommodationPreferences)
    food: FoodPreferences = Field(default_factory=FoodPreferences)
    activities: ActivityPreferences = Field(default_factory=ActivityPreferences)


class PlaceRequirementItem(BaseModel):
    name: str
    reason: Optional[str] = None
    priority: Optional[str] = None  # HIGH / MEDIUM / LOW

    @model_validator(mode="before")
    @classmethod
    def coerce_item(cls, data: Any) -> Any:
        if isinstance(data, str):
            return {"name": data}
        return data


class PlaceRequirements(BaseModel):
    must_visit: List[PlaceRequirementItem] = Field(default_factory=list)
    preferred: List[PlaceRequirementItem] = Field(default_factory=list)
    excluded: List[PlaceRequirementItem] = Field(default_factory=list)
    place_categories_to_include: List[str] = Field(default_factory=list)
    place_categories_to_avoid: List[str] = Field(default_factory=list)

    @field_validator("must_visit", "preferred", "excluded", mode="before")
    @classmethod
    def validate_places_list(cls, v: Any) -> List[Any]:
        if not isinstance(v, list):
            return []
        coerced = []
        for item in v:
            if isinstance(item, str):
                coerced.append({"name": item})
            elif isinstance(item, dict):
                coerced.append(item)
            elif isinstance(item, PlaceRequirementItem):
                coerced.append(item)
        return coerced


class ScheduleConstraints(BaseModel):
    pace: SchedulePaceEnum = SchedulePaceEnum.UNKNOWN
    max_activities_per_day: Optional[int] = None
    preferred_start_time: Optional[str] = None
    preferred_end_time: Optional[str] = None
    rest_period_required: Optional[bool] = None
    meal_planning: Optional[str] = None
    avoid_rushing: Optional[bool] = None
    group_nearby_places: Optional[bool] = None
    allow_evening_activities: Optional[bool] = None

    model_config = ConfigDict(use_enum_values=True)


class LogisticsInfo(BaseModel):
    departure_location: Optional[str] = None
    arrival_location: Optional[str] = None
    accommodation_booked: Optional[bool] = None
    transport_booked: Optional[bool] = None
    mobility_constraints: List[str] = Field(default_factory=list)
    max_acceptable_travel_minutes_between_stops: Optional[int] = None


class SpecialRequirements(BaseModel):
    must_include: List[str] = Field(default_factory=list)
    must_avoid: List[str] = Field(default_factory=list)
    special_requests: List[str] = Field(default_factory=list)


class MissingInformationItem(BaseModel):
    field: str
    importance: MissingInfoImportanceEnum = MissingInfoImportanceEnum.MEDIUM
    reason: Optional[str] = None

    @model_validator(mode="before")
    @classmethod
    def coerce_item(cls, data: Any) -> Any:
        if isinstance(data, str):
            return {"field": data, "importance": "MEDIUM", "reason": f"Thiếu thông tin cho trường {data}"}
        return data

    model_config = ConfigDict(use_enum_values=True)


class PlanningState(BaseModel):
    known_fields: List[str] = Field(default_factory=list)
    unknown_fields: List[str] = Field(default_factory=list)
    missing_information: List[MissingInformationItem] = Field(default_factory=list)
    clarification_questions: List[str] = Field(default_factory=list)
    is_ready_to_generate: bool = False

    @field_validator("missing_information", mode="before")
    @classmethod
    def validate_missing_info(cls, v: Any) -> List[Any]:
        if not isinstance(v, list):
            return []
        coerced = []
        for item in v:
            if isinstance(item, str):
                coerced.append({"field": item, "importance": "MEDIUM", "reason": f"Thiếu thông tin {item}"})
            elif isinstance(item, dict):
                coerced.append(item)
            elif isinstance(item, MissingInformationItem):
                coerced.append(item)
        return coerced


class ExtractionMetadata(BaseModel):
    source: str = "CONVERSATION"
    last_processed_message_id: Optional[int] = None
    needs_review: bool = False
    unresolved_conflicts: List[str] = Field(default_factory=list)


class CurrentLocation(BaseModel):
    """Optional device location used as a starting point for itinerary planning."""

    latitude: float
    longitude: float

    @field_validator("latitude")
    @classmethod
    def validate_latitude(cls, value: float) -> float:
        if not -90 <= value <= 90:
            raise ValueError("Latitude phải nằm trong khoảng -90 đến 90.")
        return value

    @field_validator("longitude")
    @classmethod
    def validate_longitude(cls, value: float) -> float:
        if not -180 <= value <= 180:
            raise ValueError("Longitude phải nằm trong khoảng -180 đến 180.")
        return value


# -----------------------------------------------------------------------------
# Root Model: TripPlanningContext
# -----------------------------------------------------------------------------
class TripPlanningContext(BaseModel):
    schema_version: str = "1.0"
    trip: TripInfo = Field(default_factory=TripInfo)
    budget: BudgetInfo = Field(default_factory=BudgetInfo)
    preferences: TripPreferencesInfo = Field(default_factory=TripPreferencesInfo)
    place_requirements: PlaceRequirements = Field(default_factory=PlaceRequirements)
    schedule_constraints: ScheduleConstraints = Field(default_factory=ScheduleConstraints)
    logistics: LogisticsInfo = Field(default_factory=LogisticsInfo)
    requirements: SpecialRequirements = Field(default_factory=SpecialRequirements)
    current_location: Optional[CurrentLocation] = None
    planning_state: PlanningState = Field(default_factory=PlanningState)
    extraction_metadata: ExtractionMetadata = Field(default_factory=ExtractionMetadata)

    model_config = ConfigDict(
        use_enum_values=True,
        validate_default=True,
        extra="ignore",
    )
