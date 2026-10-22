"""
TripPlanningContextExtractionService module for TravelWise.

Handles:
1. Intent detection: distinguishes trip planning requests from general tourism QA.
2. Context extraction & synthesis from multi-turn conversation history.
3. Safe JSON parsing & Pydantic schema validation.
4. Non-destructive context merging (preserves previous valid fields if LLM omits them).
5. Evaluation of planning readiness and missing information.
6. Database persistence with transactional consistency (trips, trip_preferences, ai_context).
"""

from datetime import datetime, timezone
import json
import logging
import re
from typing import Any, Dict, List, Optional

from fastapi import HTTPException, status
from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from sqlmodel import Session, select

from app.db.base import _utcnow
from app.models.ai_context import AIContext
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.trip import Trip
from app.models.trip_preference import TripPreference
from app.models.user import User
from app.rag.llm import extract_response_text, get_chat_llm
from app.schemas.trip_planning import (
    ActivityIntensityEnum,
    ActivityPreferences,
    BudgetAllocation,
    BudgetFlexibilityEnum,
    BudgetInfo,
    BudgetScopeEnum,
    DateFlexibilityEnum,
    DateInfo,
    DestinationFlexibilityEnum,
    DestinationInfo,
    ExtractionMetadata,
    GroupTypeEnum,
    LogisticsInfo,
    MissingInfoImportanceEnum,
    MissingInformationItem,
    PlaceRequirementItem,
    PlaceRequirements,
    PlanningState,
    ScheduleConstraints,
    SchedulePaceEnum,
    SpecialRequirements,
    TravelersInfo,
    TripInfo,
    TripPlanningContext,
    TripPreferencesInfo,
    TripStatusEnum,
)
from app.services.conversation_service import ConversationService

logger = logging.getLogger(__name__)


EXTRACTION_SYSTEM_PROMPT = """Bạn là Chuyên gia trích xuất ngữ cảnh lập kế hoạch du lịch (Trip Planning Context Extraction Agent) của TravelWise.
Nhiệm vụ của bạn là đọc toàn bộ lịch sử cuộc trò chuyện và ngữ cảnh hiện tại (nếu có), trích xuất và cập nhật thông tin chuyến đi vào cấu trúc JSON chuẩn `TripPlanningContext`.

## QUY TẮC BẮT BUỘC:
1. TỔNG HỢP NHIỀU LƯỢT CHAT:
   - Tổng hợp thông tin từ tất cả các lượt trước và lượt hiện tại.
   - Giữ lại thông tin đã xác định từ các lượt trước (ví dụ lượt 1 nói đi Đà Nẵng, lượt 2 nói đi 3 ngày, lượt 3 nói ngân sách 4 triệu -> context phải có cả 3).
2. CẬP NHẬT KHI NGƯỜI DÙNG THAY ĐỔI YÊU CẦU:
   - Nếu người dùng thay đổi yêu cầu (ví dụ: đổi ngân sách từ 4 triệu lên 5 triệu), hãy cập nhật giá trị mới nhất (5 triệu) và không giữ giá trị cũ.
   - Nếu người dùng yêu cầu bỏ một địa điểm khỏi danh sách (ví dụ: "bỏ Bà Nà Hills đi"), hãy loại bỏ khỏi `must_visit` và đưa vào `excluded`.
3. PHÂN BIỆT DỮ LIỆU ĐÃ XÁC NHẬN VÀ SUY ĐOÁN:
   - KHÔNG tự gán giá trị mặc định cho người dùng.
   - Chưa biết hoặc chưa nói đến -> giữ `null` hoặc `[]` hoặc `UNKNOWN`.
   - KHÔNG suy ra số người chỉ từ đại từ nhân xưng (ví dụ "mình" không nhất thiết là 1 người).
   - KHÔNG suy ra là chưa đặt phòng hoặc chưa đặt xe chỉ vì người dùng chưa đề cập.
   - KHÔNG coi địa điểm do AI gợi ý ở các lượt trước là địa điểm người dùng bắt buộc đi (chỉ ghi nhận khi người dùng xác nhận).
4. XỬ LÝ MÂU THUẪN:
   - Ưu tiên yêu cầu mới nhất người dùng xác nhận.
   - Nếu mâu thuẫn không thể giải quyết, ghi nhận vào `extraction_metadata.unresolved_conflicts` và đặt câu hỏi làm rõ trong `planning_state.clarification_questions`.
5. ĐỊNH DẠNG DỮ LIỆU:
   - Ngày tháng: định dạng "YYYY-MM-DD".
   - Ngân sách: số thực hoặc số nguyên (VNĐ).
   - Số người, số ngày: số nguyên >= 0.
   - Không tự sinh ID hệ thống (trip_id, conversation_id, last_processed_message_id) - giữ nguyên từ context cũ hoặc null.

## CẤU TRÚC JSON ĐẦU RA BẮT BUỘC:
Chỉ trả về DUY NHẤT một khối JSON hợp lệ theo đúng cấu trúc sau (không kèm lời giải thích hay văn bản ngoài JSON):
{
  "schema_version": "1.0",
  "trip": {
    "trip_id": null,
    "conversation_id": null,
    "name": null,
    "destination": {
      "city": null,
      "country": null,
      "additional_destinations": [],
      "destination_flexibility": "UNKNOWN"
    },
    "dates": {
      "start_date": null,
      "end_date": null,
      "duration_days": null,
      "nights": null,
      "date_flexibility": "UNKNOWN"
    },
    "travelers": {
      "adults": null,
      "children": null,
      "group_type": "UNKNOWN",
      "special_traveler_needs": []
    },
    "purpose": [],
    "status": "DRAFT"
  },
  "budget": {
    "total": null,
    "currency": "VND",
    "scope": "UNKNOWN",
    "includes_transport_to_destination": null,
    "includes_accommodation": null,
    "includes_food": null,
    "includes_tickets": null,
    "allocation": {
      "transport": null,
      "accommodation": null,
      "food": null,
      "tickets": null,
      "other": null
    },
    "flexibility": "UNKNOWN"
  },
  "preferences": {
    "travel_style": [],
    "interests": [],
    "transport": {
      "preferred": [],
      "available": [],
      "avoid": []
    },
    "accommodation": {
      "type_preferred": [],
      "location_preference": null,
      "must_have_amenities": [],
      "avoid": []
    },
    "food": {
      "interested_in": [],
      "dietary_restrictions": [],
      "disliked_foods": [],
      "preferred_price_range": null
    },
    "activities": {
      "preferred": [],
      "avoided": [],
      "activity_intensity": "UNKNOWN"
    }
  },
  "place_requirements": {
    "must_visit": [],
    "preferred": [],
    "excluded": [],
    "place_categories_to_include": [],
    "place_categories_to_avoid": []
  },
  "schedule_constraints": {
    "pace": "UNKNOWN",
    "max_activities_per_day": null,
    "preferred_start_time": null,
    "preferred_end_time": null,
    "rest_period_required": null,
    "meal_planning": null,
    "avoid_rushing": null,
    "group_nearby_places": null,
    "allow_evening_activities": null
  },
  "logistics": {
    "departure_location": null,
    "arrival_location": null,
    "accommodation_booked": null,
    "transport_booked": null,
    "mobility_constraints": [],
    "max_acceptable_travel_minutes_between_stops": null
  },
  "requirements": {
    "must_include": [],
    "must_avoid": [],
    "special_requests": []
  },
  "planning_state": {
    "known_fields": [],
    "unknown_fields": [],
    "missing_information": [],
    "clarification_questions": [],
    "is_ready_to_generate": false
  },
  "extraction_metadata": {
    "source": "CONVERSATION",
    "last_processed_message_id": null,
    "needs_review": false,
    "unresolved_conflicts": []
  }
}
"""


class TripPlanningContextExtractionService:
    """Service handling TripPlanningContext extraction, synthesis, and database operations."""

    # Keywords signaling trip planning intent
    PLANNING_KEYWORDS = (
        "muốn đi", "định đi", "dự định đi", "sắp đi", "kế hoạch", "lịch trình",
        "lên lịch", "tư vấn đi", "chuyến đi", "ngày đêm", "ngày 2 đêm", "ngày 3 đêm",
        "ngân sách", "kinh phí", "triệu", "chi phí", "với bạn", "với gia đình",
        "2 người", "3 người", "4 người", "đi cùng", "đi chơi", "phượt", "tour",
        "đổi ngân sách", "đổi ngày", "đổi điểm đến", "thêm địa điểm", "bỏ địa điểm",
    )

    # Pure FAQ / knowledge question indicators that lack personal trip planning intent
    FAQ_CUES = (
        "ở đâu", "là gì", "thế nào", "mấy giờ", "bao nhiêu tiền", "có gì đẹp",
        "có gì hay", "có gì đặc biệt", "ở quận nào", "sự tích", "lịch sử",
        "thời tiết", "mùa nào đẹp",
    )

    @classmethod
    def is_planning_intent(
        cls,
        message_content: str,
        existing_context: Optional[TripPlanningContext] = None,
    ) -> bool:
        """Determines whether a message is related to trip planning or general QA.

        Rules:
        - If an active planning context already exists (e.g. has destination or draft trip),
          subsequent messages in this conversation are treated as trip planning updates unless
          purely off-topic.
        - If no context exists, checks for intent indicators vs pure knowledge questions.
        """
        clean_text = (message_content or "").strip().lower()
        if not clean_text:
            return False

        # If a draft trip already exists with destination or budget, follow-up messages are planning updates
        if existing_context and (
            existing_context.trip.destination.city
            or existing_context.trip.dates.duration_days
            or existing_context.budget.total
        ):
            return True

        # Check for explicit planning keywords
        has_planning_cue = any(kw in clean_text for kw in cls.PLANNING_KEYWORDS)

        # Check if user mentions destination + duration/budget/companion
        dest_cues = ("đà nẵng", "hà nội", "sài gòn", "hội an", "nha trang", "đà lạt", "phú quốc", "huế", "quy nhơn")
        has_dest = any(d in clean_text for d in dest_cues)
        has_duration = bool(re.search(r"\d+\s*ngày", clean_text))
        has_budget = bool(re.search(r"\d+\s*(triệu|tr|k|vnd|đ)", clean_text))
        has_travelers = bool(re.search(r"\d+\s*người", clean_text)) or "bạn gái" in clean_text or "gia đình" in clean_text

        if has_planning_cue:
            return True

        if has_dest and (has_duration or has_budget or has_travelers):
            return True

        # Pure knowledge QA without planning intent
        is_pure_faq = any(clean_text.endswith(cue) or f"{cue}?" in clean_text for cue in cls.FAQ_CUES)
        if is_pure_faq:
            return False

        return False

    @classmethod
    def get_planning_context_by_conversation(
        cls,
        session: Session,
        conversation_id: int,
        current_user: Optional[User] = None,
        check_ownership: bool = True,
    ) -> Optional[TripPlanningContext]:
        """Fetch the current TripPlanningContext for a conversation from DB, checking ownership."""
        # 1. Verify conversation ownership
        ConversationService.get_conversation_by_id(
            session=session,
            conversation_id=conversation_id,
            current_user=current_user,
            check_ownership=check_ownership,
        )

        # 2. Check draft Trip for this conversation
        statement = (
            select(Trip)
            .where(Trip.conversation_id == conversation_id, Trip.status == "DRAFT")
            .order_by(Trip.updated_at.desc() if Trip.updated_at is not None else Trip.created_at.desc())
        )
        trip = session.exec(statement).first()
        if not trip:
            # Fallback to AIContext summary if present
            ai_ctx_stmt = select(AIContext).where(AIContext.conversation_id == conversation_id)
            ai_ctx = session.exec(ai_ctx_stmt).first()
            if ai_ctx and ai_ctx.summary:
                try:
                    data = json.loads(ai_ctx.summary)
                    return TripPlanningContext.model_validate(data)
                except Exception:
                    pass
            return None

        # 3. Load from TripPreference snapshot or reconstruct
        pref_stmt = select(TripPreference).where(TripPreference.trip_id == trip.id)
        pref = session.exec(pref_stmt).first()
        if pref and pref.raw_context_snapshot:
            try:
                data = json.loads(pref.raw_context_snapshot)
                ctx = TripPlanningContext.model_validate(data)
                ctx.trip.trip_id = trip.id
                ctx.trip.conversation_id = trip.conversation_id
                return ctx
            except Exception as e:
                logger.warning("Failed to deserialize raw_context_snapshot for trip %s: %s", trip.id, e)

        # Reconstruct from SQL fields if snapshot is empty
        ctx = TripPlanningContext()
        ctx.trip.trip_id = trip.id
        ctx.trip.conversation_id = trip.conversation_id
        ctx.trip.name = trip.name
        ctx.trip.destination.city = trip.destination_city
        ctx.trip.destination.country = trip.destination_country
        ctx.trip.status = TripStatusEnum(trip.status) if trip.status in TripStatusEnum.__members__ else TripStatusEnum.DRAFT
        if trip.start_date:
            ctx.trip.dates.start_date = trip.start_date.isoformat()
        if trip.end_date:
            ctx.trip.dates.end_date = trip.end_date.isoformat()

        if pref:
            ctx.trip.dates.duration_days = pref.duration_days
            ctx.trip.dates.nights = pref.nights
            ctx.trip.travelers.adults = pref.adults
            ctx.trip.travelers.children = pref.children
            if pref.group_type and pref.group_type in GroupTypeEnum.__members__:
                ctx.trip.travelers.group_type = GroupTypeEnum(pref.group_type)
            if pref.budget is not None:
                ctx.budget.total = float(pref.budget)
            if pref.budget_currency:
                ctx.budget.currency = pref.budget_currency
            if pref.budget_scope and pref.budget_scope in BudgetScopeEnum.__members__:
                ctx.budget.scope = BudgetScopeEnum(pref.budget_scope)
            if pref.place_requirements:
                try:
                    p_data = json.loads(pref.place_requirements)
                    ctx.place_requirements = PlaceRequirements.model_validate(p_data)
                except Exception:
                    pass

        return ctx

    @classmethod
    def evaluate_planning_readiness(cls, context: TripPlanningContext) -> TripPlanningContext:
        """Computes known_fields, unknown_fields, missing_information, and is_ready_to_generate.

        Section 6 rules:
        - Destination clear
        - Duration or dates enough to determine itinerary scope
        - Travelers count known if needed
        - No unresolved conflicts
        """
        known: List[str] = []
        unknown: List[str] = []
        missing: List[MissingInformationItem] = []

        # 1. Destination
        if context.trip.destination.city:
            known.append("trip.destination.city")
        else:
            unknown.append("trip.destination.city")
            missing.append(
                MissingInformationItem(
                    field="trip.destination.city",
                    importance=MissingInfoImportanceEnum.HIGH,
                    reason="Cần điểm đến chính để bắt đầu xây dựng lịch trình.",
                )
            )

        # 2. Duration / Dates
        has_duration = context.trip.dates.duration_days is not None and context.trip.dates.duration_days >= 1
        has_dates = bool(context.trip.dates.start_date and context.trip.dates.end_date)
        if has_duration or has_dates:
            known.append("trip.dates.duration")
        else:
            unknown.append("trip.dates.duration")
            missing.append(
                MissingInformationItem(
                    field="trip.dates.duration",
                    importance=MissingInfoImportanceEnum.HIGH,
                    reason="Cần biết số ngày đi hoặc khoảng thời gian để phân bổ các ngày lịch trình.",
                )
            )

        # 3. Travelers
        if context.trip.travelers.adults is not None or context.trip.travelers.group_type != GroupTypeEnum.UNKNOWN:
            known.append("trip.travelers")
        else:
            unknown.append("trip.travelers")
            missing.append(
                MissingInformationItem(
                    field="trip.travelers",
                    importance=MissingInfoImportanceEnum.MEDIUM,
                    reason="Cần số lượng người để tính toán phương tiện và gợi ý chi phí phù hợp.",
                )
            )

        # 4. Budget
        if context.budget.total is not None and context.budget.total > 0:
            known.append("budget.total")
        else:
            unknown.append("budget.total")
            missing.append(
                MissingInformationItem(
                    field="budget.total",
                    importance=MissingInfoImportanceEnum.LOW,
                    reason="Ngân sách dự kiến giúp tối ưu các địa điểm và dịch vụ lưu trú phù hợp.",
                )
            )

        # 5. Readiness check
        has_no_conflicts = len(context.extraction_metadata.unresolved_conflicts) == 0
        dest_ready = bool(context.trip.destination.city)
        duration_ready = has_duration or has_dates

        is_ready = dest_ready and duration_ready and has_no_conflicts

        clarification_qs: List[str] = []
        if not dest_ready:
            clarification_qs.append("Bạn dự định du lịch tại thành phố hoặc điểm đến nào?")
        if not duration_ready:
            clarification_qs.append("Bạn dự kiến chuyến đi kéo dài trong mấy ngày mấy đêm?")
        if context.trip.travelers.adults is None and context.trip.travelers.group_type == GroupTypeEnum.UNKNOWN:
            clarification_qs.append("Bạn sẽ đi cùng ai (một mình, cặp đôi, gia đình hay nhóm bạn)?")
        if not context.preferences.interests:
            clarification_qs.append("Bạn có sở thích đặc biệt nào cho chuyến đi này không (tắm biển, ẩm thực, check-in, nghỉ dưỡng)?")

        context.planning_state.known_fields = known
        context.planning_state.unknown_fields = unknown
        context.planning_state.missing_information = missing
        if not context.planning_state.clarification_questions:
            context.planning_state.clarification_questions = clarification_qs
        context.planning_state.is_ready_to_generate = is_ready

        return context

    @classmethod
    def format_context_summary(cls, context: Optional[TripPlanningContext]) -> str:
        """Formats the current planning context into a concise text block for RAG prompt."""
        if not context:
            return ""

        known_items: List[str] = []
        if context.trip.destination.city:
            known_items.append(f"Điểm đến: {context.trip.destination.city}")
        if context.trip.dates.duration_days:
            known_items.append(f"Thời lượng: {context.trip.dates.duration_days} ngày")
        elif context.trip.dates.start_date and context.trip.dates.end_date:
            known_items.append(f"Thời gian: từ {context.trip.dates.start_date} đến {context.trip.dates.end_date}")
        if context.trip.travelers.adults:
            known_items.append(f"Số người lớn: {context.trip.travelers.adults}")
        group_type = context.trip.travelers.group_type
        if group_type and group_type != GroupTypeEnum.UNKNOWN and group_type != "UNKNOWN":
            group_val = getattr(group_type, "value", str(group_type))
            known_items.append(f"Nhóm: {group_val}")
        if context.budget.total:
            known_items.append(f"Ngân sách: {context.budget.total:,.0f} {context.budget.currency}")
        if context.preferences.interests:
            known_items.append(f"Sở thích: {', '.join(context.preferences.interests)}")
        if context.logistics.departure_location:
            known_items.append(f"Khởi hành từ: {context.logistics.departure_location}")

        missing_items: List[str] = []
        for m in context.planning_state.missing_information:
            field_name = m.field
            if field_name == "trip.destination.city":
                missing_items.append("Điểm đến (Thành phố/Địa danh)")
            elif field_name == "trip.dates.duration":
                missing_items.append("Thời lượng / Số ngày đi (Ví dụ: 3 ngày 2 đêm)")
            elif field_name == "trip.travelers":
                missing_items.append("Số lượng thành viên / Bạn đồng hành")
            elif field_name == "budget.total":
                missing_items.append("Ngân sách dự kiến")

        summary_lines: List[str] = []
        if known_items:
            summary_lines.append(f"THÔNG TIN ĐÃ BIẾT: {'; '.join(known_items)}")
        if missing_items:
            summary_lines.append(f"THÔNG TIN CÒN THIẾU: {'; '.join(missing_items)}")

        return "\n".join(summary_lines)

    @classmethod
    def merge_contexts(
        cls,
        existing: Optional[TripPlanningContext],
        extracted: TripPlanningContext,
        last_message_id: Optional[int] = None,
    ) -> TripPlanningContext:
        """Safely merges an existing context with a newly extracted context.

        Rules:
        - Non-destructive: If LLM returns null/empty for a previously confirmed field,
          preserve the confirmed field from existing context.
        - Updates: If newly extracted context has a non-null/non-empty value, it overwrites.
        - Exclusions: If an item is in newly extracted `excluded`, remove from `must_visit` and `preferred`.
        - Backend IDs are strictly preserved.
        """
        if not existing:
            if last_message_id is not None:
                extracted.extraction_metadata.last_processed_message_id = last_message_id
            return cls.evaluate_planning_readiness(extracted)

        # Clone existing to merge into
        merged = TripPlanningContext.model_validate(existing.model_dump())

        # Backend system IDs
        merged.trip.trip_id = existing.trip.trip_id
        merged.trip.conversation_id = existing.trip.conversation_id
        if last_message_id is not None:
            merged.extraction_metadata.last_processed_message_id = last_message_id
        elif extracted.extraction_metadata.last_processed_message_id:
            merged.extraction_metadata.last_processed_message_id = extracted.extraction_metadata.last_processed_message_id

        # 1. Trip destination & name
        if extracted.trip.name:
            merged.trip.name = extracted.trip.name
        if extracted.trip.destination.city:
            merged.trip.destination.city = extracted.trip.destination.city
        if extracted.trip.destination.country:
            merged.trip.destination.country = extracted.trip.destination.country
        if extracted.trip.destination.additional_destinations:
            merged.trip.destination.additional_destinations = extracted.trip.destination.additional_destinations
        if extracted.trip.destination.destination_flexibility != DestinationFlexibilityEnum.UNKNOWN:
            merged.trip.destination.destination_flexibility = extracted.trip.destination.destination_flexibility

        # 2. Trip dates
        if extracted.trip.dates.start_date:
            merged.trip.dates.start_date = extracted.trip.dates.start_date
        if extracted.trip.dates.end_date:
            merged.trip.dates.end_date = extracted.trip.dates.end_date
        if extracted.trip.dates.duration_days is not None:
            merged.trip.dates.duration_days = extracted.trip.dates.duration_days
        if extracted.trip.dates.nights is not None:
            merged.trip.dates.nights = extracted.trip.dates.nights
        if extracted.trip.dates.date_flexibility != DateFlexibilityEnum.UNKNOWN:
            merged.trip.dates.date_flexibility = extracted.trip.dates.date_flexibility

        # 3. Travelers
        if extracted.trip.travelers.adults is not None:
            merged.trip.travelers.adults = extracted.trip.travelers.adults
        if extracted.trip.travelers.children is not None:
            merged.trip.travelers.children = extracted.trip.travelers.children
        if extracted.trip.travelers.group_type != GroupTypeEnum.UNKNOWN:
            merged.trip.travelers.group_type = extracted.trip.travelers.group_type
        if extracted.trip.travelers.special_traveler_needs:
            merged.trip.travelers.special_traveler_needs = extracted.trip.travelers.special_traveler_needs

        if extracted.trip.purpose:
            merged.trip.purpose = extracted.trip.purpose

        # 4. Budget
        if extracted.budget.total is not None:
            merged.budget.total = extracted.budget.total
        if extracted.budget.currency:
            merged.budget.currency = extracted.budget.currency
        if extracted.budget.scope != BudgetScopeEnum.UNKNOWN:
            merged.budget.scope = extracted.budget.scope
        if extracted.budget.includes_transport_to_destination is not None:
            merged.budget.includes_transport_to_destination = extracted.budget.includes_transport_to_destination
        if extracted.budget.includes_accommodation is not None:
            merged.budget.includes_accommodation = extracted.budget.includes_accommodation
        if extracted.budget.includes_food is not None:
            merged.budget.includes_food = extracted.budget.includes_food
        if extracted.budget.includes_tickets is not None:
            merged.budget.includes_tickets = extracted.budget.includes_tickets
        if extracted.budget.flexibility != BudgetFlexibilityEnum.UNKNOWN:
            merged.budget.flexibility = extracted.budget.flexibility

        # Allocation
        for alloc_field in ("transport", "accommodation", "food", "tickets", "other"):
            val = getattr(extracted.budget.allocation, alloc_field, None)
            if val is not None:
                setattr(merged.budget.allocation, alloc_field, val)

        # 5. Preferences
        if extracted.preferences.travel_style:
            merged.preferences.travel_style = extracted.preferences.travel_style
        if extracted.preferences.interests:
            merged.preferences.interests = extracted.preferences.interests
        if extracted.preferences.transport.preferred:
            merged.preferences.transport.preferred = extracted.preferences.transport.preferred
        if extracted.preferences.transport.avoid:
            merged.preferences.transport.avoid = extracted.preferences.transport.avoid
        if extracted.preferences.accommodation.type_preferred:
            merged.preferences.accommodation.type_preferred = extracted.preferences.accommodation.type_preferred
        if extracted.preferences.accommodation.location_preference:
            merged.preferences.accommodation.location_preference = extracted.preferences.accommodation.location_preference
        if extracted.preferences.food.interested_in:
            merged.preferences.food.interested_in = extracted.preferences.food.interested_in
        if extracted.preferences.food.dietary_restrictions:
            merged.preferences.food.dietary_restrictions = extracted.preferences.food.dietary_restrictions
        if extracted.preferences.food.preferred_price_range:
            merged.preferences.food.preferred_price_range = extracted.preferences.food.preferred_price_range
        if extracted.preferences.activities.preferred:
            merged.preferences.activities.preferred = extracted.preferences.activities.preferred
        if extracted.preferences.activities.activity_intensity != ActivityIntensityEnum.UNKNOWN:
            merged.preferences.activities.activity_intensity = extracted.preferences.activities.activity_intensity

        # 6. Place Requirements & Removals
        # Collect excluded names (lowercase)
        excluded_names = {item.name.lower().strip() for item in extracted.place_requirements.excluded}

        # If extracted has new must_visit items, update/add
        if extracted.place_requirements.must_visit:
            existing_must = {item.name.lower().strip(): item for item in merged.place_requirements.must_visit}
            for item in extracted.place_requirements.must_visit:
                if item.name.lower().strip() not in excluded_names:
                    existing_must[item.name.lower().strip()] = item
            # Remove any excluded items
            merged.place_requirements.must_visit = [
                item for key, item in existing_must.items() if key not in excluded_names
            ]
        else:
            # Still filter out newly excluded items
            merged.place_requirements.must_visit = [
                item for item in merged.place_requirements.must_visit
                if item.name.lower().strip() not in excluded_names
            ]

        # Preferred places
        if extracted.place_requirements.preferred:
            merged.place_requirements.preferred = [
                item for item in extracted.place_requirements.preferred
                if item.name.lower().strip() not in excluded_names
            ]

        # Excluded places
        if extracted.place_requirements.excluded:
            merged.place_requirements.excluded = extracted.place_requirements.excluded

        # Categories
        if extracted.place_requirements.place_categories_to_include:
            merged.place_requirements.place_categories_to_include = extracted.place_requirements.place_categories_to_include
        if extracted.place_requirements.place_categories_to_avoid:
            merged.place_requirements.place_categories_to_avoid = extracted.place_requirements.place_categories_to_avoid

        # 7. Schedule constraints
        if extracted.schedule_constraints.pace != SchedulePaceEnum.UNKNOWN:
            merged.schedule_constraints.pace = extracted.schedule_constraints.pace
        if extracted.schedule_constraints.max_activities_per_day is not None:
            merged.schedule_constraints.max_activities_per_day = extracted.schedule_constraints.max_activities_per_day
        if extracted.schedule_constraints.avoid_rushing is not None:
            merged.schedule_constraints.avoid_rushing = extracted.schedule_constraints.avoid_rushing

        # 8. Logistics
        if extracted.logistics.departure_location:
            merged.logistics.departure_location = extracted.logistics.departure_location
        if extracted.logistics.arrival_location:
            merged.logistics.arrival_location = extracted.logistics.arrival_location
        if extracted.logistics.accommodation_booked is not None:
            merged.logistics.accommodation_booked = extracted.logistics.accommodation_booked
        if extracted.logistics.transport_booked is not None:
            merged.logistics.transport_booked = extracted.logistics.transport_booked

        # 9. Requirements
        if extracted.requirements.must_include:
            merged.requirements.must_include = extracted.requirements.must_include
        if extracted.requirements.must_avoid:
            merged.requirements.must_avoid = extracted.requirements.must_avoid
        if extracted.requirements.special_requests:
            merged.requirements.special_requests = extracted.requirements.special_requests

        # 10. Conflicts & Review
        merged.extraction_metadata.unresolved_conflicts = extracted.extraction_metadata.unresolved_conflicts
        merged.extraction_metadata.needs_review = extracted.extraction_metadata.needs_review
        if extracted.planning_state.clarification_questions:
            merged.planning_state.clarification_questions = extracted.planning_state.clarification_questions

        # Recalculate readiness
        return cls.evaluate_planning_readiness(merged)

    @classmethod
    def extract_from_conversation(
        cls,
        conversation_history: List[Message],
        existing_context: Optional[TripPlanningContext] = None,
        llm: Optional[Any] = None,
    ) -> TripPlanningContext:
        """Calls the LLM to extract and synthesize TripPlanningContext from chat history."""
        chat_llm = llm or get_chat_llm(temperature=0.0)

        # Format conversation messages for prompt
        lines = []
        for msg in conversation_history:
            sender_label = "Người dùng (User)" if msg.sender.upper() == "USER" else "AI"
            lines.append(f"[{sender_label}]: {msg.content}")
        history_text = "\n".join(lines)

        existing_ctx_json = (
            existing_context.model_dump_json(indent=2)
            if existing_context
            else "Chưa có context trước đó (bắt đầu mới)."
        )

        user_prompt_content = (
            "Dưới đây là Ngữ cảnh hiện tại và Lịch sử hội thoại đầy đủ giữa Người dùng và AI:\n\n"
            f"=== NGỮ CẢNH HIỆN TẠI (TRIP PLANNING CONTEXT HIỆN CÓ) ===\n"
            f"{existing_ctx_json}\n\n"
            f"=== LỊCH SỬ HỘI THOẠI ĐẦY ĐỦ ===\n"
            f"{history_text}\n\n"
            "Hãy tổng hợp toàn bộ thông tin và trả về DUY NHẤT một khối JSON hợp lệ theo schema TripPlanningContext."
        )

        messages = [
            SystemMessage(content=EXTRACTION_SYSTEM_PROMPT),
            HumanMessage(content=user_prompt_content),
        ]

        # Call LLM
        response = chat_llm.invoke(messages)
        raw_text = extract_response_text(getattr(response, "content", response)).strip()

        # Extract JSON content
        parsed_data = cls._parse_json_from_llm(raw_text)
        extracted_ctx = TripPlanningContext.model_validate(parsed_data)

        return extracted_ctx

    @classmethod
    def _parse_json_from_llm(cls, text: str) -> Dict[str, Any]:
        """Safely parses JSON from LLM response text, stripping markdown codeblocks."""
        # 1. Try direct parse
        try:
            return json.loads(text)
        except Exception:
            pass

        # 2. Extract from markdown code fences ```json ... ```
        fence_match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text, re.IGNORECASE)
        if fence_match:
            try:
                return json.loads(fence_match.group(1))
            except Exception:
                pass

        # 3. Find first { and last }
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end != -1 and end > start:
            snippet = text[start : end + 1]
            try:
                return json.loads(snippet)
            except Exception:
                pass

        raise ValueError(f"Không thể phân tích dữ liệu JSON từ phản hồi của LLM: {text[:200]}")

    @classmethod
    def save_context_to_db(
        cls,
        session: Session,
        conversation_id: int,
        user_id: Optional[int],
        context: TripPlanningContext,
    ) -> Trip:
        """Persists the extracted TripPlanningContext into SQL Server inside a transaction.

        Updates or creates:
        - `trips` (overview)
        - `trip_preferences` (preferences, budget, travelers, and raw snapshot)
        - `ai_context` (conversation summary/context)
        """
        # 1. Query existing draft trip for this conversation
        statement = select(Trip).where(Trip.conversation_id == conversation_id, Trip.status == "DRAFT")
        trip = session.exec(statement).first()

        now = _utcnow()
        trip_name = context.trip.name
        if not trip_name:
            city_name = context.trip.destination.city or "chưa đặt tên"
            trip_name = f"Chuyến đi {city_name}"

        # Parse dates
        start_date_obj = None
        if context.trip.dates.start_date:
            try:
                start_date_obj = datetime.strptime(context.trip.dates.start_date, "%Y-%m-%d").date()
            except ValueError:
                pass

        end_date_obj = None
        if context.trip.dates.end_date:
            try:
                end_date_obj = datetime.strptime(context.trip.dates.end_date, "%Y-%m-%d").date()
            except ValueError:
                pass

        if trip:
            # Update existing draft trip
            trip.name = trip_name
            trip.destination_city = context.trip.destination.city
            trip.destination_country = context.trip.destination.country
            trip.start_date = start_date_obj
            trip.end_date = end_date_obj
            trip.updated_at = now
            session.add(trip)
        else:
            # Create new draft trip
            trip = Trip(
                user_id=user_id,
                conversation_id=conversation_id,
                name=trip_name,
                destination_city=context.trip.destination.city,
                destination_country=context.trip.destination.country,
                status="DRAFT",
                start_date=start_date_obj,
                end_date=end_date_obj,
                created_at=now,
                updated_at=now,
            )
            session.add(trip)
            session.flush()  # obtain trip.id

        # Update context trip_id and conversation_id
        context.trip.trip_id = trip.id
        context.trip.conversation_id = conversation_id

        # 2. Update or create TripPreference
        pref_stmt = select(TripPreference).where(TripPreference.trip_id == trip.id)
        pref = session.exec(pref_stmt).first()

        travelers_count = None
        if context.trip.travelers.adults is not None:
            travelers_count = context.trip.travelers.adults + (context.trip.travelers.children or 0)

        # Serialized fields
        interests_json = json.dumps(context.preferences.interests, ensure_ascii=False) if context.preferences.interests else None
        special_reqs_json = json.dumps(context.requirements.model_dump(), ensure_ascii=False)
        place_reqs_json = json.dumps(context.place_requirements.model_dump(), ensure_ascii=False)
        schedule_json = json.dumps(context.schedule_constraints.model_dump(), ensure_ascii=False)
        raw_snapshot = context.model_dump_json()

        transport_str = ", ".join(context.preferences.transport.preferred) if context.preferences.transport.preferred else None
        travel_style_str = ", ".join(context.preferences.travel_style) if context.preferences.travel_style else None

        if pref:
            pref.travelers = travelers_count
            pref.adults = context.trip.travelers.adults
            pref.children = context.trip.travelers.children
            pref.group_type = str(context.trip.travelers.group_type)
            pref.budget = context.budget.total
            pref.budget_currency = context.budget.currency
            pref.budget_scope = str(context.budget.scope)
            pref.duration_days = context.trip.dates.duration_days
            pref.nights = context.trip.dates.nights
            pref.transport = transport_str
            pref.travel_style = travel_style_str
            pref.interests = interests_json
            pref.special_requirements = special_reqs_json
            pref.place_requirements = place_reqs_json
            pref.schedule_constraints = schedule_json
            pref.raw_context_snapshot = raw_snapshot
            pref.updated_at = now
            session.add(pref)
        else:
            pref = TripPreference(
                trip_id=trip.id,
                travelers=travelers_count,
                adults=context.trip.travelers.adults,
                children=context.trip.travelers.children,
                group_type=str(context.trip.travelers.group_type),
                budget=context.budget.total,
                budget_currency=context.budget.currency,
                budget_scope=str(context.budget.scope),
                duration_days=context.trip.dates.duration_days,
                nights=context.trip.dates.nights,
                transport=transport_str,
                travel_style=travel_style_str,
                interests=interests_json,
                special_requirements=special_reqs_json,
                place_requirements=place_reqs_json,
                schedule_constraints=schedule_json,
                raw_context_snapshot=raw_snapshot,
                created_at=now,
                updated_at=now,
            )
            session.add(pref)

        # 3. Update or create AIContext
        ai_ctx_stmt = select(AIContext).where(AIContext.conversation_id == conversation_id)
        ai_ctx = session.exec(ai_ctx_stmt).first()
        if ai_ctx:
            ai_ctx.summary = raw_snapshot
            ai_ctx.updated_at = now
            session.add(ai_ctx)
        else:
            ai_ctx = AIContext(
                conversation_id=conversation_id,
                summary=raw_snapshot,
                updated_at=now,
            )
            session.add(ai_ctx)

        session.commit()
        session.refresh(trip)
        return trip

    @classmethod
    def extract_and_update_trip_context(
        cls,
        session: Session,
        conversation_id: int,
        current_user: Optional[User] = None,
        latest_message: Optional[Message] = None,
        llm: Optional[Any] = None,
    ) -> Optional[TripPlanningContext]:
        """Main end-to-end extraction and update flow.

        Flow:
        1. Verifies conversation and ownership.
        2. Retrieves conversation history.
        3. Retrieves existing context.
        4. Checks intent; skips if not trip planning.
        5. Performs multi-turn LLM extraction.
        6. Merges extracted result safely with existing context.
        7. Persists to SQL Server.
        8. Returns updated TripPlanningContext.
        """
        # 1. Verify conversation
        conv = ConversationService.get_conversation_by_id(
            session=session,
            conversation_id=conversation_id,
            current_user=current_user,
            check_ownership=True,
        )

        # 2. Retrieve messages
        messages = ConversationService.get_messages_by_conversation(
            session=session,
            conversation_id=conversation_id,
            current_user=current_user,
            skip=0,
            limit=50,
        )
        if not messages:
            return None

        last_msg = latest_message or messages[-1]

        # 3. Retrieve existing context
        existing_context = cls.get_planning_context_by_conversation(
            session=session,
            conversation_id=conversation_id,
            current_user=current_user,
            check_ownership=False,
        )

        # 4. Check if we already processed this message (idempotency / retry safe)
        if existing_context and existing_context.extraction_metadata.last_processed_message_id == last_msg.id:
            logger.info("Message %s already processed for conversation %s. Skipping duplicate extraction.", last_msg.id, conversation_id)
            return existing_context

        # 5. Check intent
        is_planning = cls.is_planning_intent(last_msg.content or "", existing_context)
        if not is_planning:
            logger.info("Message '%s' in conversation %s determined as not trip planning intent. Skipping extraction.", last_msg.id, conversation_id)
            return existing_context

        # 6. LLM extraction
        try:
            extracted_raw = cls.extract_from_conversation(
                conversation_history=messages,
                existing_context=existing_context,
                llm=llm,
            )
        except Exception as e:
            logger.error("LLM extraction failed for conversation %s: %s", conversation_id, e)
            # Safe degradation: do not break chat, return existing context if any
            return existing_context

        # 7. Merge safely
        merged_context = cls.merge_contexts(
            existing=existing_context,
            extracted=extracted_raw,
            last_message_id=last_msg.id,
        )

        # 8. Save to DB
        user_id = current_user.id if current_user else conv.user_id
        try:
            cls.save_context_to_db(
                session=session,
                conversation_id=conversation_id,
                user_id=user_id,
                context=merged_context,
            )
        except Exception as e:
            session.rollback()
            logger.error("Failed to persist planning context to DB for conversation %s: %s", conversation_id, e)
            # Return merged context in memory without crashing
            return merged_context

        return merged_context
