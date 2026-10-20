"""
Itinerary schemas for AI Itinerary Generation Service.

Defines Pydantic models for structured multi-day itinerary generation,
validation, and serialization.
"""

from datetime import datetime
from enum import Enum
import re
from typing import Any, List, Optional
from pydantic import BaseModel, ConfigDict, Field, field_validator
from app.schemas.trip_planning import CurrentLocation


class ItineraryStatusEnum(str, Enum):
    GENERATED = "GENERATED"
    NEED_MORE_INFORMATION = "NEED_MORE_INFORMATION"
    FAILED = "FAILED"


class BudgetConfidenceEnum(str, Enum):
    CONFIDENT = "CONFIDENT"
    ESTIMATED = "ESTIMATED"
    INSUFFICIENT_DATA = "INSUFFICIENT_DATA"


class ActivityTypeEnum(str, Enum):
    VISIT = "VISIT"
    MEAL = "MEAL"
    REST = "REST"
    TRANSIT = "TRANSIT"
    CHECKIN = "CHECKIN"
    ENTERTAINMENT = "ENTERTAINMENT"
    OTHER = "OTHER"


class ItineraryActivityItem(BaseModel):
    """Activity item within an itinerary day."""

    order_index: int
    activity_type: str = "VISIT"
    place_id: Optional[int] = None
    title: str
    description: Optional[str] = None
    start_time: Optional[str] = None  # Format HH:MM
    end_time: Optional[str] = None    # Format HH:MM
    duration_minutes: Optional[int] = None
    estimated_cost: Optional[float] = None
    travel_duration_minutes: Optional[int] = None
    travel_distance_km: Optional[float] = None
    note: Optional[str] = None

    @field_validator("start_time", "end_time", mode="before")
    @classmethod
    def normalize_time_str(cls, v: Any) -> Optional[str]:
        if v is None:
            return None
        v_str = str(v).strip()
        if not v_str or v_str.lower() in ("none", "null", ""):
            return None
        # Format HH:MM or HH:MM:SS
        m = re.match(r"^(\d{1,2}):(\d{2})(?::\d{2})?$", v_str)
        if m:
            hh, mm = int(m.group(1)), int(m.group(2))
            if 0 <= hh <= 23 and 0 <= mm <= 59:
                return f"{hh:02d}:{mm:02d}"
        return None

    @field_validator("duration_minutes", "travel_duration_minutes", mode="before")
    @classmethod
    def validate_non_negative_int(cls, v: Any) -> Optional[int]:
        if v is None:
            return None
        try:
            val = int(v)
            return val if val >= 0 else None
        except (ValueError, TypeError):
            return None

    @field_validator("estimated_cost", "travel_distance_km", mode="before")
    @classmethod
    def validate_non_negative_float(cls, v: Any) -> Optional[float]:
        if v is None:
            return None
        try:
            val = float(v)
            return val if val >= 0 else None
        except (ValueError, TypeError):
            return None

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class ItineraryDayItem(BaseModel):
    """Itinerary day containing a list of ordered activities."""

    day_number: int
    date: Optional[str] = None  # Format YYYY-MM-DD
    title: Optional[str] = None
    description: Optional[str] = None
    activities: List[ItineraryActivityItem] = Field(default_factory=list)

    @field_validator("date", mode="before")
    @classmethod
    def validate_date(cls, v: Any) -> Optional[str]:
        if v is None:
            return None
        v_str = str(v).strip()
        if not v_str or v_str.lower() in ("none", "null", ""):
            return None
        if re.match(r"^\d{4}-\d{2}-\d{2}$", v_str):
            try:
                datetime.strptime(v_str, "%Y-%m-%d")
                return v_str
            except ValueError:
                return None
        return None

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class BudgetEstimate(BaseModel):
    """Budget estimate and confidence notes."""

    target_total: Optional[float] = None
    estimated_total: Optional[float] = None
    confidence: str = BudgetConfidenceEnum.INSUFFICIENT_DATA.value
    notes: List[str] = Field(default_factory=list)

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class ItineraryGenerationResponse(BaseModel):
    """Top-level response model for AI Itinerary Generation."""

    status: str = ItineraryStatusEnum.GENERATED.value
    trip_id: Optional[int] = None
    title: Optional[str] = None
    summary: Optional[str] = None
    duration_days: Optional[int] = None
    currency: str = "VND"
    budget: Optional[BudgetEstimate] = None
    days: List[ItineraryDayItem] = Field(default_factory=list)
    warnings: List[str] = Field(default_factory=list)
    unresolved_requirements: List[str] = Field(default_factory=list)
    missing_information: List[str] = Field(default_factory=list)

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class ItineraryGenerationRequest(BaseModel):
    """Request payload for itinerary generation endpoint."""

    context: Optional[Any] = None
    save_to_db: bool = True
    allow_overwrite_confirmed: bool = False
    user_prompt: Optional[str] = None
    conversation_id: Optional[int] = None
    current_location: Optional[CurrentLocation] = None


class ItineraryEditRequest(BaseModel):
    """Request payload for conversational itinerary modification."""

    change_prompt: str
    target_day: Optional[int] = None
    allow_overwrite: bool = True


class ItineraryDetectIntentRequest(BaseModel):
    """Request payload to determine whether a message is an itinerary edit request."""

    message: str
    conversation_id: Optional[int] = None


class ItineraryDetectIntentResponse(BaseModel):
    """Response returned from LLM & RAG intent classification."""

    is_edit_intent: bool
    confidence: str = "HIGH"
    change_prompt: Optional[str] = None
    reason: Optional[str] = None


class TripCreateRequest(BaseModel):
    """Request payload to create a new Trip entity from Web/API."""

    name: Optional[str] = None
    destination_city: str
    destination_country: Optional[str] = "Việt Nam"
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    duration_days: Optional[int] = 3
    conversation_id: Optional[int] = None
    context: Optional[Any] = None


class TripUpdateRequest(BaseModel):
    """Request payload to update trip metadata."""

    name: Optional[str] = None
    status: Optional[str] = None
    destination_city: Optional[str] = None
    destination_country: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None


class ValidationResult(BaseModel):
    """Result of validation pipeline."""

    is_valid: bool = True
    errors: List[str] = Field(default_factory=list)
    warnings: List[str] = Field(default_factory=list)
    unresolved_requirements: List[str] = Field(default_factory=list)


class ItineraryPlaceSummary(BaseModel):
    """Place summary information attached to an activity."""

    place_id: int
    name: str
    category: Optional[str] = None
    address: Optional[str] = None
    description: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    image_url: Optional[str] = None

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class ItineraryActivityDetail(BaseModel):
    """Detailed activity model retrieved from database."""

    id: int
    itinerary_day_id: int
    order_index: int
    activity_type: str = "VISIT"
    place_id: Optional[int] = None
    place: Optional[ItineraryPlaceSummary] = None
    title: str
    description: Optional[str] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    duration_minutes: Optional[int] = None
    estimated_cost: Optional[float] = None
    travel_duration_minutes: Optional[int] = None
    travel_distance_km: Optional[float] = None
    note: Optional[str] = None

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class ItineraryActivityCreate(BaseModel):
    """Request payload to create a new itinerary activity."""

    title: str = Field(..., min_length=1, max_length=255)
    activity_type: str = ActivityTypeEnum.VISIT.value
    place_id: Optional[int] = None
    description: Optional[str] = None
    start_time: Optional[str] = None  # HH:MM
    end_time: Optional[str] = None  # HH:MM
    duration_minutes: Optional[int] = Field(default=None, ge=0)
    estimated_cost: Optional[float] = Field(default=None, ge=0)
    travel_duration_minutes: Optional[int] = Field(default=None, ge=0)
    travel_distance_km: Optional[float] = Field(default=None, ge=0)
    order_index: Optional[int] = Field(
        default=None,
        ge=1,
        description="Thứ tự trong ngày. Bỏ trống để tự gán (max + 1).",
    )
    note: Optional[str] = None

    @field_validator("start_time", "end_time", mode="before")
    @classmethod
    def normalize_time_str(cls, v: Any) -> Optional[str]:
        return ItineraryActivityItem.normalize_time_str(v)

    @field_validator("activity_type", mode="before")
    @classmethod
    def normalize_activity_type(cls, v: Any) -> str:
        if v is None or str(v).strip() == "":
            return ActivityTypeEnum.VISIT.value
        value = str(v).strip().upper()
        allowed = {e.value for e in ActivityTypeEnum}
        if value not in allowed:
            raise ValueError(
                f"activity_type không hợp lệ. Cho phép: {', '.join(sorted(allowed))}."
            )
        return value

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class ItineraryActivityUpdate(BaseModel):
    """Request payload for partial update of an itinerary activity."""

    title: Optional[str] = Field(default=None, min_length=1, max_length=255)
    activity_type: Optional[str] = None
    place_id: Optional[int] = None
    description: Optional[str] = None
    start_time: Optional[str] = None  # HH:MM
    end_time: Optional[str] = None  # HH:MM
    duration_minutes: Optional[int] = Field(default=None, ge=0)
    estimated_cost: Optional[float] = Field(default=None, ge=0)
    travel_duration_minutes: Optional[int] = Field(default=None, ge=0)
    travel_distance_km: Optional[float] = Field(default=None, ge=0)
    order_index: Optional[int] = Field(default=None, ge=1)
    note: Optional[str] = None

    @field_validator("start_time", "end_time", mode="before")
    @classmethod
    def normalize_time_str(cls, v: Any) -> Optional[str]:
        return ItineraryActivityItem.normalize_time_str(v)

    @field_validator("activity_type", mode="before")
    @classmethod
    def normalize_activity_type(cls, v: Any) -> Optional[str]:
        if v is None:
            return None
        value = str(v).strip().upper()
        if not value:
            return None
        allowed = {e.value for e in ActivityTypeEnum}
        if value not in allowed:
            raise ValueError(
                f"activity_type không hợp lệ. Cho phép: {', '.join(sorted(allowed))}."
            )
        return value

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class ItineraryDayDetail(BaseModel):
    """Detailed day model retrieved from database."""

    id: int
    trip_id: int
    day_number: int
    date: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    activities: List[ItineraryActivityDetail] = Field(default_factory=list)

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class ItineraryDetailResponse(BaseModel):
    """Full detailed itinerary response for a trip."""

    trip_id: int
    name: Optional[str] = None
    destination: Optional[str] = None
    destination_city: Optional[str] = None
    destination_country: Optional[str] = None
    status: str
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    duration_days: int = 0
    total_activities: int = 0
    estimated_total_cost: Optional[float] = None
    currency: str = "VND"
    days: List[ItineraryDayDetail] = Field(default_factory=list)
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class TripSummaryItem(BaseModel):
    """Summary item for trip listing endpoint."""

    id: int
    name: Optional[str] = None
    destination_city: Optional[str] = None
    destination_country: Optional[str] = None
    status: str
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    days_count: int = 0
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class TripListResponse(BaseModel):
    """Paginated list of trips."""

    total: int
    skip: int
    limit: int
    items: List[TripSummaryItem] = Field(default_factory=list)

    model_config = ConfigDict(use_enum_values=True, extra="ignore")


class EditStatusEnum(str, Enum):
    EDITED = "EDITED"
    NEED_CLARIFICATION = "NEED_CLARIFICATION"
    ANSWERED = "ANSWERED"
    FAILED = "FAILED"


class ItineraryEditResponse(BaseModel):
    """Response returned after conversational itinerary edit."""

    status: str = EditStatusEnum.EDITED.value
    trip_id: int
    conversation_id: Optional[int] = None
    message: str
    applied_changes: List[str] = Field(default_factory=list)
    clarification_question: Optional[str] = None
    itinerary: Optional[ItineraryDetailResponse] = None
    warnings: List[str] = Field(default_factory=list)

    model_config = ConfigDict(use_enum_values=True, extra="ignore")
