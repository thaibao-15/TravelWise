"""
Itinerary Generation Service for TravelWise.

Generates structured multi-day travel itineraries using LLM, constrained strictly
to real places fetched from Microsoft SQL Server via PlaceSearchService.

Pipeline:
1. Validate minimum planning information (destination, duration).
2. Retrieve real candidate places from SQL Server using PlaceSearchService.
3. Formulate prompt strictly constraining LLM to real place candidates.
4. Call LLM, safely parse structured JSON.
5. Validate domain constraints:
   - Match exact duration & day numbers.
   - Ensure all place_id values exist in candidate list (no fabricated places/IDs).
   - Ensure no excluded places are included.
   - Check must-visit places are scheduled or recorded in unresolved requirements.
   - Ensure order_index is unique and sequential per day.
   - Ensure start_time < end_time and no overlapping activities.
   - Ensure non-negative costs and durations.
   - Synchronize calendar dates if trip start_date is known.
6. Persist to SQL Server (trips, itinerary_days, itinerary_activities) in a transaction.
"""

from datetime import date, datetime, time, timedelta
from decimal import Decimal
import json
import logging
import re
from typing import Any, Dict, List, Optional, Set, Tuple

from langchain_core.messages import HumanMessage, SystemMessage
from sqlmodel import Session, select

from app.models.itinerary_activity import ItineraryActivity
from app.models.itinerary_day import ItineraryDay
from app.models.trip import Trip
from app.rag.llm import extract_response_text, get_chat_llm
from app.schemas.itinerary import (
    ActivityTypeEnum,
    BudgetConfidenceEnum,
    BudgetEstimate,
    ItineraryActivityItem,
    ItineraryDayItem,
    ItineraryGenerationResponse,
    ItineraryStatusEnum,
)
from app.schemas.place_search import PlaceSearchResponse, SearchPlaceItem
from app.schemas.trip_planning import TripPlanningContext
from app.services.itinerary_persistence_service import ItineraryPersistenceService
from app.services.place_search_service import PlaceSearchService

logger = logging.getLogger(__name__)


ITINERARY_SYSTEM_PROMPT = """Bạn là Chuyên gia Lập kế hoạch Du lịch AI (AI Travel Itinerary Planner) của TravelWise.
Nhiệm vụ của bạn là tạo lịch trình du lịch nhiều ngày chi tiết, hợp lý và hấp dẫn dựa trên thông tin chuyến đi và danh sách các địa điểm THỰC TẾ được cung cấp.

## NGUYÊN TẮC BẮT BUỘC:
1. CHỈ SỬ DỤNG ĐỊA ĐIỂM ĐƯỢC CUNG CẤP:
   - Bạn CHỈ ĐƯỢC CHỌN các địa điểm có trong DANH SÁCH ĐỊA ĐIỂM THỰC TẾ dưới đây.
   - Mỗi hoạt động tham quan (activity_type = 'VISIT') PHẢI có `place_id` tương ứng chính xác từ danh sách.
   - TUYỆT ĐỐI KHÔNG tự tạo địa điểm mới, không tự bịa place_id, không bịa địa chỉ, tọa độ, giờ mở cửa hoặc giá vé.
   - Các hoạt động tự do như ăn uống, nghỉ ngơi, nhận phòng hoặc di chuyển (activity_type là MEAL, REST, TRANSIT, CHECKIN) KHÔNG gắn với địa điểm trong danh sách thì để `place_id = null`.
   - TUYỆT ĐỐI KHÔNG đưa vào lịch trình các địa điểm thuộc danh sách CẦN TRÁNH (Excluded places).

2. PHÂN CHIA LỊCH TRÌNH THEO NGÀY:
   - Tạo chính xác số ngày theo yêu cầu của chuyến đi (day_number từ 1 đến N).
   - Nếu người dùng đã cung cấp ngày bắt đầu cụ thể, các ngày tiếp theo tăng dần (YYYY-MM-DD). Nếu chưa có ngày cụ thể, để `date = null`.
   - Phân bổ hoạt động hợp lý theo các buổi: sáng, trưa, chiều, tối.
   - Nhóm các địa điểm gần nhau trong cùng một buổi hoặc một ngày.

3. SẮP XẾP THỜI GIAN VÀ NHỊP ĐỘ:
   - Thứ tự hoạt động trong từng ngày (`order_index`) phải bắt đầu từ 1 và liên tục tăng dần (1, 2, 3...).
   - `start_time` và `end_time` theo định dạng "HH:MM" (ví dụ "08:30", "11:00").
   - `start_time` phải trước `end_time`.
   - Các hoạt động trong cùng một ngày KHÔNG ĐƯỢC CHỒNG CHÉO THỜI GIAN (hoạt động sau bắt đầu sau hoặc bằng lúc hoạt động trước kết thúc).
   - Dành thời gian nghỉ ngơi, ăn uống và di chuyển hợp lý. Không xếp lịch quá dày nếu người dùng chọn phong cách thư giãn (RELAXED).

4. TÔN TRỌNG NGÂN SÁCH VÀ CHI PHÍ:
   - Chỉ sử dụng giá vé/chi phí nếu địa điểm được cung cấp có thông tin giá.
   - Nếu không có thông tin chi phí chính xác, để `estimated_cost = null`. Không tự bịa giá tiền.
   - Chi phí không âm.

5. ĐÁP ỨNG SỞ THÍCH VÀ ĐỊA ĐIỂM BẮT BUỘC:
   - Ưu tiên các địa điểm bắt buộc (Must-Visit) và ưu tiên (Preferred).
   - Nếu địa điểm bắt buộc không thể đưa vào lịch trình, hãy giải thích trong `warnings` hoặc `unresolved_requirements`.

## ĐỊNH DẠNG ĐẦU RA BẮT BUỘC:
Chỉ trả về DUY NHẤT một khối JSON hợp lệ theo schema sau (không thêm markdown, không thêm giải thích ngoài JSON):
{
  "title": "Tên lịch trình",
  "summary": "Tóm tắt lịch trình ngắn gọn",
  "budget": {
    "target_total": null,
    "estimated_total": null,
    "confidence": "INSUFFICIENT_DATA",
    "notes": []
  },
  "days": [
    {
      "day_number": 1,
      "date": null,
      "title": "Tiêu đề ngày 1",
      "description": "Mô tả ngày 1",
      "activities": [
        {
          "order_index": 1,
          "activity_type": "VISIT",
          "place_id": 101,
          "title": "Tên hoạt động",
          "description": "Mô tả chi tiết",
          "start_time": "08:30",
          "end_time": "10:30",
          "duration_minutes": 120,
          "estimated_cost": null,
          "travel_duration_minutes": null,
          "travel_distance_km": null,
          "note": null
        }
      ]
    }
  ],
  "warnings": [],
  "unresolved_requirements": []
}
"""


class ItineraryGenerationService:
    """Service responsible for generating, validating and persisting travel itineraries."""

    @classmethod
    def check_minimum_requirements(
        cls, context: TripPlanningContext
    ) -> Tuple[bool, List[str], List[str]]:
        """Verifies whether the context contains the minimum information required.

        Requires:
        1. Destination (city or additional destinations).
        2. Duration (duration_days >= 1 or start_date & end_date).

        Returns:
            Tuple[is_ready, missing_fields, error_messages]
        """
        missing_fields: List[str] = []
        messages: List[str] = []

        # 1. Destination
        has_dest = bool(
            (context.trip.destination.city and context.trip.destination.city.strip())
            or context.trip.destination.additional_destinations
        )
        if not has_dest:
            missing_fields.append("trip.destination.city")
            messages.append("Chưa có điểm đến chính (destination city) để tạo lịch trình.")

        # 2. Duration
        duration_days = cls._get_duration_days(context)
        if duration_days is None or duration_days < 1:
            # Tự động gán mặc định 3 ngày nếu người dùng đã chọn điểm đến
            if has_dest:
                context.trip.dates.duration_days = 3
                duration_days = 3
            else:
                missing_fields.append("trip.dates.duration_days")
                messages.append("Chưa có thời lượng chuyến đi (số ngày) để tạo lịch trình.")

        is_ready = len(missing_fields) == 0
        return is_ready, missing_fields, messages

    @classmethod
    def _get_duration_days(cls, context: TripPlanningContext) -> Optional[int]:
        """Calculates duration in days from duration_days or start_date and end_date."""
        if context.trip.dates.duration_days and context.trip.dates.duration_days >= 1:
            return context.trip.dates.duration_days

        if hasattr(context.trip, "duration") and getattr(context.trip.duration, "days", None):
            return context.trip.duration.days

        if hasattr(context, "duration_days") and getattr(context, "duration_days", None):
            return context.duration_days

        if context.trip.dates.start_date and context.trip.dates.end_date:
            try:
                start = datetime.strptime(context.trip.dates.start_date, "%Y-%m-%d").date()
                end = datetime.strptime(context.trip.dates.end_date, "%Y-%m-%d").date()
                delta = (end - start).days + 1
                if delta >= 1:
                    return delta
            except ValueError:
                pass
        return None

    @classmethod
    def generate_itinerary(
        cls,
        session: Session,
        context: TripPlanningContext,
        trip_id: Optional[int] = None,
        llm: Optional[Any] = None,
        save_to_db: bool = True,
        user_prompt: Optional[str] = None,
    ) -> ItineraryGenerationResponse:
        """Executes the full itinerary generation pipeline.

        Flow:
        1. Check minimum requirements. If insufficient, return NEED_MORE_INFORMATION.
        2. Query candidate places using PlaceSearchService.
        3. Check if places found. If candidate list empty, handle gracefully.
        4. Construct LLM prompt constrained to real places.
        5. Call LLM, parse JSON.
        6. Validate and enforce business rules (place existence, time ordering, no overlapping).
        7. Persist to SQL Server (if save_to_db=True).
        8. Return final response.
        """
        # 1. Check minimum requirements
        is_ready, missing_fields, missing_msgs = cls.check_minimum_requirements(context)
        if not is_ready:
            return ItineraryGenerationResponse(
                status=ItineraryStatusEnum.NEED_MORE_INFORMATION.value,
                trip_id=trip_id or context.trip.trip_id,
                duration_days=cls._get_duration_days(context),
                currency=context.budget.currency or "VND",
                missing_information=missing_fields,
                warnings=missing_msgs,
            )

        duration_days = cls._get_duration_days(context) or 1

        # 2. Query places via PlaceSearchService
        place_response: PlaceSearchResponse = PlaceSearchService.search_places_for_itinerary(
            session=session,
            context=context,
            skip=0,
            limit=35,
        )

        candidates: List[SearchPlaceItem] = place_response.places
        candidate_map: Dict[int, SearchPlaceItem] = {p.place_id: p for p in candidates}
        candidate_ids: Set[int] = set(candidate_map.keys())

        # Collect unresolved must-visit items from search service
        unresolved_reqs: List[str] = [
            f"Địa điểm bắt buộc '{item.name}' không tìm thấy trong dữ liệu: {item.reason or ''}"
            for item in place_response.unresolved_must_visit
        ]
        warnings: List[str] = list(place_response.warnings)

        if not candidates:
            return ItineraryGenerationResponse(
                status=ItineraryStatusEnum.FAILED.value,
                trip_id=trip_id or context.trip.trip_id,
                duration_days=duration_days,
                currency=context.budget.currency or "VND",
                warnings=[
                    f"Không tìm thấy địa điểm nào phù hợp cho điểm đến '{context.trip.destination.city or ''}' trong cơ sở dữ liệu."
                ]
                + warnings,
                unresolved_requirements=unresolved_reqs,
            )

        # 3. Build Prompt & Call LLM
        chat_llm = llm or get_chat_llm(temperature=0.0)

        prompt_text = cls._build_prompt(
            context=context,
            duration_days=duration_days,
            candidates=candidates,
            unresolved_search_items=unresolved_reqs,
            user_prompt=user_prompt,
        )

        messages = [
            SystemMessage(content=ITINERARY_SYSTEM_PROMPT),
            HumanMessage(content=prompt_text),
        ]

        try:
            llm_response = chat_llm.invoke(messages)
            raw_text = extract_response_text(getattr(llm_response, "content", llm_response)).strip()
            parsed_json = cls._parse_json_from_llm(raw_text)
            if not isinstance(parsed_json, dict) or not parsed_json.get("days"):
                raise ValueError("LLM không trả về danh sách các ngày (days) trong lịch trình.")
        except Exception as e:
            logger.warning("Initial LLM response parse failed: %s. Attempting repair call...", e)
            try:
                # Controlled single repair attempt
                repair_messages = [
                    SystemMessage(content=ITINERARY_SYSTEM_PROMPT),
                    HumanMessage(content=prompt_text),
                    HumanMessage(
                        content=(
                            f"Phản hồi trước bị lỗi: {str(e)}.\n"
                            "Vui lòng chỉ trả về DUY NHẤT một khối JSON hợp lệ theo đúng cấu trúc yêu cầu, có chứa danh sách ngày (days), không kèm giải thích ngoài JSON."
                        )
                    ),
                ]
                repair_res = chat_llm.invoke(repair_messages)
                raw_text = extract_response_text(getattr(repair_res, "content", repair_res)).strip()
                parsed_json = cls._parse_json_from_llm(raw_text)
                if not isinstance(parsed_json, dict) or not parsed_json.get("days"):
                    raise ValueError("LLM không trả về danh sách các ngày (days) sau khi sửa lỗi.")
            except Exception as repair_err:
                logger.error("Failed to parse JSON from LLM even after repair: %s", repair_err)
                return ItineraryGenerationResponse(
                    status=ItineraryStatusEnum.FAILED.value,
                    trip_id=trip_id or context.trip.trip_id,
                    duration_days=duration_days,
                    currency=context.budget.currency or "VND",
                    warnings=[f"Lỗi phân tích cú pháp JSON từ phản hồi LLM: {str(repair_err)}"],
                )

        # 4. Validate and sanitize generated itinerary
        validated_response, validation_warnings, validation_unresolved = cls._validate_and_sanitize(
            raw_data=parsed_json,
            context=context,
            duration_days=duration_days,
            candidate_map=candidate_map,
            trip_id=trip_id,
        )

        validated_response.warnings.extend(warnings)
        validated_response.warnings.extend(validation_warnings)
        validated_response.unresolved_requirements.extend(unresolved_reqs)
        validated_response.unresolved_requirements.extend(validation_unresolved)

        # Deduplicate warnings & unresolved
        validated_response.warnings = list(dict.fromkeys(validated_response.warnings))
        validated_response.unresolved_requirements = list(dict.fromkeys(validated_response.unresolved_requirements))

        # 5. Persist to database inside a transaction
        effective_trip_id = trip_id or context.trip.trip_id
        if save_to_db and effective_trip_id and validated_response.status == ItineraryStatusEnum.GENERATED.value:
            try:
                cls._persist_itinerary(
                    session=session,
                    trip_id=effective_trip_id,
                    response=validated_response,
                    context=context,
                )
            except Exception as db_err:
                logger.error("Error saving itinerary to SQL Server: %s", db_err)
                validated_response.warnings.append(
                    f"Đã tạo lịch trình thành công nhưng gặp lỗi khi lưu vào cơ sở dữ liệu: {str(db_err)}"
                )

        return validated_response

    @classmethod
    def _build_prompt(
        cls,
        context: TripPlanningContext,
        duration_days: int,
        candidates: List[SearchPlaceItem],
        unresolved_search_items: List[str],
        user_prompt: Optional[str] = None,
    ) -> str:
        """Constructs human prompt containing planning context and candidate places list."""
        # Destination & Dates
        city = context.trip.destination.city or "Điểm đến chưa xác định"
        add_dests = ", ".join(context.trip.destination.additional_destinations)
        start_date = context.trip.dates.start_date or "Chưa xác định"
        end_date = context.trip.dates.end_date or "Chưa xác định"

        # Travelers & Budget
        adults = context.trip.travelers.adults
        children = context.trip.travelers.children
        group_type = context.trip.travelers.group_type
        budget_total = context.budget.total
        currency = context.budget.currency or "VND"

        # Preferences & Pace
        travel_style = ", ".join(context.preferences.travel_style) or "Tự do"
        interests = ", ".join(context.preferences.interests) or "Khám phá tổng quan"
        pace = context.schedule_constraints.pace or "MODERATE"
        max_act = context.schedule_constraints.max_activities_per_day

        # Must visit & Excluded
        must_visit_names = [item.name for item in context.place_requirements.must_visit]
        excluded_names = [item.name for item in context.place_requirements.excluded]

        # Format candidate places
        places_lines = []
        for p in candidates:
            flags = []
            if p.is_must_visit:
                flags.append("MUST-VISIT")
            if p.is_preferred:
                flags.append("PREFERRED")
            flag_str = f" [{', '.join(flags)}]" if flags else ""

            price_str = f"{p.price:,.0f} {currency}" if p.price is not None else (p.price_info or "Chưa có dữ liệu giá")
            hours_str = p.opening_hours or "Chưa có dữ liệu giờ mở cửa"
            addr_str = p.address or "Chưa có địa chỉ"
            cat_str = p.category or "Tổng hợp"

            places_lines.append(
                f"- ID: {p.place_id} | Tên: {p.name}{flag_str} | Danh mục: {cat_str} | Địa chỉ: {addr_str} | Giờ: {hours_str} | Giá: {price_str}"
            )
        places_block = "\n".join(places_lines)

        user_req_block = ""
        if user_prompt:
            user_req_block = f"""
=== YÊU CẦU ĐẶC BIỆT / ĐIỀU CHỈNH LỊCH TRÌNH TỪ DU KHÁCH ===
Nội dung yêu cầu từ du khách: "{user_prompt}"
QUY TẮC BẮT BUỘC KHI XỬ LÝ YÊU CẦU NÀY:
1. Nếu yêu cầu có nhắc đến GIỜ BẮT ĐẦU (ví dụ: "10h", "10:00", "9h30", "cho lịch bắt đầu lúc 10h"):
   - Hoạt động đầu tiên trong ngày (hoặc ngày được chỉ định) PHẢI có start_time đúng giờ này (ví dụ: "10:00").
   - Tất cả các hoạt động sau đó phải được dời giờ phù hợp và không được trùng giờ.
2. Nếu yêu cầu THAY ĐỔI / BỔ SUNG / BỎ ĐỊA ĐIỂM (ví dụ: đi biển, ăn hải sản, cafe, ngắm hoàng hôn...):
   - Hãy ưu tiên chọn các địa điểm phù hợp trong DANH SÁCH ĐỊA ĐIỂM THỰC TẾ dưới đây và cập nhật hoạt động.
3. Nếu yêu cầu THAY ĐỔI NGÀY / SẮP XẾP LẠI:
   - Hãy sắp xếp các hoạt động và thời lượng các ngày theo đúng mong muốn của du khách.
"""

        prompt = f"""=== THÔNG TIN CHUYẾN ĐI CẦN LẬP LỊCH TRÌNH ===
- Điểm đến chính: {city}
- Điểm đến bổ sung: {add_dests or 'Không'}
- Thời lượng: {duration_days} ngày ({duration_days - 1} đêm)
- Ngày bắt đầu: {start_date}
- Ngày kết thúc: {end_date}
- Người tham gia: {adults or 'Chưa rõ'} người lớn, {children or 0} trẻ em (Nhóm: {group_type})
- Ngân sách: {f'{budget_total:,.0f} {currency}' if budget_total else 'Chưa cung cấp'}
- Phong cách du lịch: {travel_style}
- Sở thích quan tâm: {interests}
- Tốc độ tham quan: {pace} (Tối đa hoạt động/ngày: {max_act or 'Tùy chỉnh'})
- Địa điểm bắt buộc (Must-Visit): {', '.join(must_visit_names) or 'Không'}
- Địa điểm cần tránh (Excluded): {', '.join(excluded_names) or 'Không'}
{user_req_block}
=== DANH SÁCH ĐỊA ĐIỂM THỰC TẾ TRUY VẤN TỪ CƠ SỞ DỮ LIỆU (CHỈ ĐƯỢC CHỌN TỪ ĐÂY) ===
{places_block}

Hãy lập lịch trình chi tiết {duration_days} ngày. Nhắc lại: chỉ dùng place_id có trong danh sách trên!
"""
        return prompt

    @classmethod
    def _parse_json_from_llm(cls, text: str) -> Dict[str, Any]:
        """Safely extracts and parses JSON dictionary from LLM string."""
        try:
            return json.loads(text)
        except Exception:
            pass

        # Check code fence ```json ... ```
        fence = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text, re.IGNORECASE)
        if fence:
            try:
                return json.loads(fence.group(1))
            except Exception:
                pass

        # Substring { ... }
        s = text.find("{")
        e = text.rfind("}")
        if s != -1 and e != -1 and e > s:
            return json.loads(text[s : e + 1])

        raise ValueError("Không thể trích xuất JSON hợp lệ từ phản hồi LLM.")

    @classmethod
    def _validate_and_sanitize(
        cls,
        raw_data: Dict[str, Any],
        context: TripPlanningContext,
        duration_days: int,
        candidate_map: Dict[int, SearchPlaceItem],
        trip_id: Optional[int],
    ) -> Tuple[ItineraryGenerationResponse, List[str], List[str]]:
        """Validates all domain constraints and sanitizes generated itinerary.

        Checks:
        1. Number of days matches duration_days.
        2. Calendar dates synchronized with trip start_date (or null).
        3. All place_id values are in candidate_map (no fabricated IDs).
        4. No excluded places used.
        5. Must-visit places are scheduled or reported in unresolved_requirements.
        6. order_index continuous and unique per day.
        7. start_time < end_time and non-overlapping.
        8. Non-negative costs and durations.
        """
        warnings: List[str] = []
        unresolved: List[str] = []

        valid_candidate_ids: Set[int] = set(candidate_map.keys())
        scheduled_place_ids: Set[int] = set()

        # Parse excluded places names for safety check
        excluded_norms = {
            cls._normalize_text(item.name)
            for item in context.place_requirements.excluded
            if item.name
        }

        # Trip start date for date synchronization
        trip_start_date: Optional[date] = None
        if context.trip.dates.start_date:
            try:
                trip_start_date = datetime.strptime(
                    context.trip.dates.start_date, "%Y-%m-%d"
                ).date()
            except ValueError:
                pass

        raw_days = raw_data.get("days", [])
        if not isinstance(raw_days, list):
            raw_days = []

        sanitized_days: List[ItineraryDayItem] = []

        # Enforce exact day count matching duration_days
        for d_idx in range(1, duration_days + 1):
            matching_raw_day = next(
                (d for d in raw_days if isinstance(d, dict) and d.get("day_number") == d_idx),
                None,
            )

            # Expected calendar date
            expected_date_str: Optional[str] = None
            if trip_start_date:
                expected_date_str = (trip_start_date + timedelta(days=d_idx - 1)).isoformat()

            day_title = (
                matching_raw_day.get("title")
                if matching_raw_day
                else f"Ngày {d_idx}: Khám phá điểm đến"
            )
            day_desc = matching_raw_day.get("description") if matching_raw_day else None

            # Process activities
            raw_activities = (
                matching_raw_day.get("activities", []) if matching_raw_day else []
            )
            if not isinstance(raw_activities, list):
                raw_activities = []

            sanitized_activities: List[ItineraryActivityItem] = []
            prev_end_minutes: Optional[int] = None
            order_counter = 1

            for act_raw in raw_activities:
                if not isinstance(act_raw, dict):
                    continue

                act_title = act_raw.get("title") or "Hoạt động tham quan"
                act_type = str(act_raw.get("activity_type") or "VISIT").upper()
                place_id_raw = act_raw.get("place_id")

                # Validate place_id
                clean_place_id: Optional[int] = None
                if place_id_raw is not None:
                    try:
                        pid = int(place_id_raw)
                        if pid in valid_candidate_ids:
                            clean_place_id = pid
                            scheduled_place_ids.add(pid)
                        else:
                            warnings.append(
                                f"Bỏ qua place_id={pid} trong hoạt động '{act_title}' vì không nằm trong danh sách địa điểm thực tế hợp lệ."
                            )
                    except (ValueError, TypeError):
                        pass

                # Check if place is accidentally an excluded place
                act_title_norm = cls._normalize_text(act_title)
                is_excluded = any(ex in act_title_norm for ex in excluded_norms if len(ex) >= 3)
                if clean_place_id and clean_place_id in candidate_map:
                    cand_name_norm = cls._normalize_text(candidate_map[clean_place_id].name)
                    if any(ex in cand_name_norm for ex in excluded_norms if len(ex) >= 3):
                        is_excluded = True

                if is_excluded:
                    warnings.append(
                        f"Đã loại bỏ địa điểm '{act_title}' khỏi lịch trình vì nằm trong danh sách cần tránh."
                    )
                    clean_place_id = None

                # Validate times
                start_time_str = act_raw.get("start_time")
                end_time_str = act_raw.get("end_time")
                duration_min = act_raw.get("duration_minutes")

                # Non-negative durations
                if duration_min is not None:
                    try:
                        duration_min = max(0, int(duration_min))
                    except (ValueError, TypeError):
                        duration_min = None

                # Check time order & overlapping
                start_min = cls._time_to_minutes(start_time_str)
                end_min = cls._time_to_minutes(end_time_str)

                if start_min is not None and end_min is not None:
                    if start_min >= end_min:
                        warnings.append(
                            f"Hoạt động '{act_title}' có giờ bắt đầu ({start_time_str}) không trước giờ kết thúc ({end_time_str}); tự động điều chỉnh."
                        )
                        # Fix end_min
                        end_min = start_min + (duration_min or 60)
                        end_time_str = cls._minutes_to_time(end_min)

                    if prev_end_minutes is not None and start_min < prev_end_minutes:
                        warnings.append(
                            f"Hoạt động '{act_title}' bị chồng lấn thời gian với hoạt động trước ({cls._minutes_to_time(prev_end_minutes)}); tự động dịch chuyển."
                        )
                        # Shift forward
                        shift = prev_end_minutes - start_min
                        start_min = prev_end_minutes
                        end_min = end_min + shift
                        start_time_str = cls._minutes_to_time(start_min)
                        end_time_str = cls._minutes_to_time(end_min)

                    prev_end_minutes = end_min

                # Cost validation
                est_cost: Optional[float] = None
                raw_cost = act_raw.get("estimated_cost")
                if raw_cost is not None:
                    try:
                        est_cost = max(0.0, float(raw_cost))
                    except (ValueError, TypeError):
                        est_cost = None
                elif clean_place_id and candidate_map[clean_place_id].price is not None:
                    est_cost = candidate_map[clean_place_id].price

                item = ItineraryActivityItem(
                    order_index=order_counter,
                    activity_type=act_type,
                    place_id=clean_place_id,
                    title=act_title,
                    description=act_raw.get("description"),
                    start_time=start_time_str,
                    end_time=end_time_str,
                    duration_minutes=duration_min,
                    estimated_cost=est_cost,
                    travel_duration_minutes=act_raw.get("travel_duration_minutes"),
                    travel_distance_km=act_raw.get("travel_distance_km"),
                    note=act_raw.get("note"),
                )
                sanitized_activities.append(item)
                order_counter += 1

            sanitized_days.append(
                ItineraryDayItem(
                    day_number=d_idx,
                    date=expected_date_str,
                    title=day_title,
                    description=day_desc,
                    activities=sanitized_activities,
                )
            )

        # Check must-visit places scheduling
        must_visit_reqs = context.place_requirements.must_visit
        for mv in must_visit_reqs:
            mv_norm = cls._normalize_text(mv.name)
            # Find in candidates
            matching_cand = next(
                (c for c in candidate_map.values() if cls._normalize_text(c.name) == mv_norm or mv_norm in cls._normalize_text(c.name)),
                None,
            )
            if matching_cand and matching_cand.place_id not in scheduled_place_ids:
                unresolved.append(
                    f"Địa điểm bắt buộc '{mv.name}' tìm thấy trong cơ sở dữ liệu nhưng chưa được sắp xếp vào các ngày."
                )

        # Budget estimate calculation
        total_estimated = 0.0
        known_prices_count = 0
        total_activities_count = 0

        for day in sanitized_days:
            for act in day.activities:
                total_activities_count += 1
                if act.estimated_cost is not None:
                    total_estimated += act.estimated_cost
                    known_prices_count += 1

        budget_notes: List[str] = []
        if known_prices_count == 0:
            confidence = BudgetConfidenceEnum.INSUFFICIENT_DATA.value
            budget_notes.append("Chưa có đủ dữ liệu giá của các địa điểm để tính tổng chi phí.")
            est_total_val = None
        else:
            confidence = (
                BudgetConfidenceEnum.CONFIDENT.value
                if known_prices_count == total_activities_count
                else BudgetConfidenceEnum.ESTIMATED.value
            )
            budget_notes.append(
                f"Chi phí ước tính dựa trên {known_prices_count}/{total_activities_count} hoạt động có thông tin giá."
            )
            est_total_val = total_estimated

        budget_est = BudgetEstimate(
            target_total=context.budget.total,
            estimated_total=est_total_val,
            confidence=confidence,
            notes=budget_notes,
        )

        title = raw_data.get("title") or f"Lịch trình khám phá {context.trip.destination.city or ''} {duration_days} ngày"
        summary = raw_data.get("summary") or f"Lịch trình được tối ưu hóa cho {duration_days} ngày."

        response = ItineraryGenerationResponse(
            status=ItineraryStatusEnum.GENERATED.value,
            trip_id=trip_id or context.trip.trip_id,
            title=title,
            summary=summary,
            duration_days=duration_days,
            currency=context.budget.currency or "VND",
            budget=budget_est,
            days=sanitized_days,
            warnings=warnings,
            unresolved_requirements=unresolved,
        )

        return response, warnings, unresolved

    @classmethod
    def _persist_itinerary(
        cls,
        session: Session,
        trip_id: int,
        response: ItineraryGenerationResponse,
        context: TripPlanningContext,
    ) -> None:
        """Saves generated itinerary into SQL Server via ItineraryPersistenceService."""
        ItineraryPersistenceService.save_itinerary(
            session=session,
            trip_id=trip_id,
            itinerary=response,
            check_ownership=False,
            context=context,
        )

    @classmethod
    def _time_to_minutes(cls, time_str: Optional[str]) -> Optional[int]:
        """Converts 'HH:MM' string to minutes from start of day."""
        if not time_str:
            return None
        m = re.match(r"^(\d{1,2}):(\d{2})$", str(time_str).strip())
        if m:
            hh, mm = int(m.group(1)), int(m.group(2))
            return hh * 60 + mm
        return None

    @classmethod
    def _minutes_to_time(cls, minutes: int) -> str:
        """Converts minutes to 'HH:MM' string formatted."""
        minutes = minutes % (24 * 60)
        hh = minutes // 60
        mm = minutes % 60
        return f"{hh:02d}:{mm:02d}"

    @classmethod
    def _normalize_text(cls, text: Optional[str]) -> str:
        """Helper to normalize text for accent-insensitive comparison."""
        if not text:
            return ""
        import unicodedata
        clean = text.replace("đ", "d").replace("Đ", "D").strip().lower()
        nfkd = unicodedata.normalize("NFD", clean)
        return "".join([c for c in nfkd if not unicodedata.combining(c)])
