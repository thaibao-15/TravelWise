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
    ItineraryPlaceSummary,
    ItineraryStatusEnum,
)
from app.schemas.place_search import PlaceSearchResponse, SearchPlaceItem
from app.schemas.trip_planning import TripPlanningContext
from app.services.itinerary_persistence_service import ItineraryPersistenceService
from app.services.place_search_service import PlaceSearchService, haversine_distance

logger = logging.getLogger(__name__)

MAX_DAILY_PLACE_DISTANCE_KM = 15.0


ITINERARY_SYSTEM_PROMPT = """Bạn là Linh AI - Hướng dẫn viên du lịch bản địa thông minh, thân thiện, tinh tế và đồng cảm của TravelWise.
Nhiệm vụ của bạn là tạo hoặc điều chỉnh lịch trình du lịch nhiều ngày chi tiết, hợp lý và hấp dẫn dựa trên thông tin chuyến đi và danh sách các địa điểm THỰC TẾ được cung cấp.

## NGUYÊN TẮC BẮT BUỘC:

1. CHỈ SỬ DỤNG ĐỊA ĐIỂM ĐƯỢC CUNG CẤP:
- Bạn CHỈ ĐƯỢC CHỌN các địa điểm có trong DANH SÁCH ĐỊA ĐIỂM THỰC TẾ dưới đây.
- Mỗi hoạt động tham quan (activity_type = 'VISIT') PHẢI có place_id tương ứng chính xác từ danh sách.
- TUYỆT ĐỐI KHÔNG tự tạo địa điểm mới, không tự bịa place_id, không bịa địa chỉ, tọa độ, giờ mở cửa hoặc giá vé.
- Các hoạt động tự do như ăn uống, nghỉ ngơi, nhận phòng hoặc di chuyển (activity_type là MEAL, REST, TRANSIT, CHECKIN) KHÔNG gắn với địa điểm trong danh sách thì để place_id = null.
- TUYỆT ĐỐI KHÔNG đưa vào lịch trình các địa điểm thuộc danh sách CẦN TRÁNH (Excluded places).

2. PHÂN CHIA LỊCH TRÌNH THEO NGÀY VÀ BẢO TOÀN DỮ LIỆU:
- Tạo chính xác số ngày theo yêu cầu của chuyến đi (day_number từ 1 đến N).
- Nếu người dùng đã cung cấp ngày bắt đầu cụ thể, các ngày tiếp theo tăng dần (YYYY-MM-DD). Nếu chưa có ngày cụ thể, để date = null.
- Phân bổ hoạt động hợp lý theo các buổi: sáng, trưa, chiều, tối.
- Khi CHỈNH SỬA LỊCH TRÌNH CŨ: Bắt buộc giữ nguyên các ngày và hoạt động không liên quan đến yêu cầu thay đổi, chỉ sửa đúng phần du khách mong muốn.

3. SẮP XẾP THỜI GIAN VÀ NHỊP ĐỘ:
- Thứ tự hoạt động trong từng ngày (order_index) phải bắt đầu từ 1 và liên tục tăng dần (1, 2, 3...).
- start_time và end_time theo định dạng "HH:MM" (ví dụ "08:30", "11:00").
- start_time phải trước end_time.
- Các hoạt động trong cùng một ngày KHÔNG ĐƯỢC CHỒNG CHÉO THỜI GIAN (hoạt động sau bắt đầu sau hoặc bằng lúc hoạt động trước kết thúc).
- Dành thời gian nghỉ ngơi, ăn uống và di chuyển hợp lý. Không xếp lịch quá dày nếu du khách chọn phong cách thư giãn hoặc yêu cầu giảm nhịp độ.

4. TÔN TRỌNG NGÂN SÁCH VÀ CHI PHÍ:
- Chỉ sử dụng giá vé/chi phí nếu địa điểm được cung cấp có thông tin giá.
- Nếu không có thông tin chi phí chính xác, để estimated_cost = null. Không tự bịa giá tiền.
- Chi phí không âm.

5. ĐÁP ỨNG SỞ THÍCH VÀ ĐỊA ĐIỂM BẮT BUỘC:
- Ưu tiên các địa điểm bắt buộc (Must-Visit) và ưu tiên (Preferred).
- Nếu địa điểm bắt buộc không thể đưa vào lịch trình, hãy giải thích trong warnings hoặc unresolved_requirements.

6. PHONG CÁCH VÀ TRƯỜNG "summary" (CỰC KỲ QUAN TRỌNG):
- Trường "summary" là lời nhắn trực tiếp từ Hướng dẫn viên Linh AI gửi đến du khách.
- Khi LẬP MỚI: Tóm tắt điểm nhấn hành trình hấp dẫn, truyền cảm hứng (2-3 câu).
- Khi CHỈNH SỬA / ĐIỀU CHỈNH:
  * Phản hồi tự nhiên, duyên dáng, thấu hiểu ngữ cảnh đời thường của du khách (ngủ nướng dậy trễ, mệt mỏi muốn nghỉ khách sạn, trời mưa gió, đổi ý phút chót, thèm ăn ngon...).
  * Giải thích ngắn gọn cách đã điều chỉnh (ví dụ: dời giờ bắt đầu sang 10:00, tinh giản điểm phụ buổi sáng để không bị dồn dập vào giờ ăn trưa, hoặc đổi buổi chiều sang nghỉ ngơi ở khách sạn).
  * Tuyệt đối KHÔNG trả lời theo khuôn mẫu robot (không nói: "Tôi đã ghi nhận...", "Đã cập nhật lịch trình thành công...").
  * KHÔNG sử dụng ký tự Markdown (không dùng dấu *, #, -, `), không chứa JSON hay place_id kỹ thuật trong summary để giọng đọc Text-to-Speech phát âm mượt mà nhất.

## ĐỊNH DẠNG ĐẦU RA BẮT BUỘC:
Chỉ trả về DUY NHẤT một khối JSON hợp lệ theo schema sau (không thêm markdown, không thêm giải thích ngoài JSON):
{
  "title": "Tên lịch trình",
  "summary": "Lời phản hồi tự nhiên, ấm áp và thấu hiểu của Hướng dẫn viên Linh AI gửi du khách",
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
        existing_itinerary: Optional[Any] = None,
    ) -> ItineraryGenerationResponse:
        """Executes the full itinerary generation pipeline.

        Flow:
        1. Check minimum requirements. If insufficient, return NEED_MORE_INFORMATION.
        2. Query candidate places using PlaceSearchService.
        3. Check if places found. If candidate list empty, handle gracefully.
        4. Construct LLM prompt constrained to real places (preserving unaffected existing activities if editing).
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

        # Retrieve existing itinerary if editing and not provided
        if existing_itinerary is None and trip_id:
            try:
                existing_itinerary = ItineraryPersistenceService.get_itinerary_by_trip_id(
                    session=session,
                    trip_id=trip_id,
                    check_ownership=False,
                )
            except Exception as e:
                logger.debug("No existing itinerary found for trip %s: %s", trip_id, e)

        # 2. Query places via PlaceSearchService
        current_location = context.current_location
        place_response: PlaceSearchResponse = PlaceSearchService.search_places_for_itinerary(
            session=session,
            context=context,
            skip=0,
            limit=35,
            reference_lat=current_location.latitude if current_location else None,
            reference_lon=current_location.longitude if current_location else None,
        )

        candidates: List[SearchPlaceItem] = place_response.places
        candidate_map: Dict[int, SearchPlaceItem] = {p.place_id: p for p in candidates}
        candidate_ids: Set[int] = set(candidate_map.keys())
        geographic_groups = cls._build_geographic_groups(candidates, duration_days)

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
            geographic_groups=geographic_groups,
            existing_itinerary=existing_itinerary,
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
        validation_warnings.extend(
            cls._validate_daily_geographic_distance(
                days=validated_response.days,
                candidate_map=candidate_map,
            )
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
        geographic_groups: Optional[Dict[int, int]] = None,
        existing_itinerary: Optional[Any] = None,
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
        current_location = context.current_location
        location_block = (
            f"- Vị trí hiện tại: ({current_location.latitude:.6f}, {current_location.longitude:.6f})"
            if current_location
            else "- Vị trí hiện tại: Không được cung cấp"
        )

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
            group_number = geographic_groups.get(p.place_id) if geographic_groups else None
            group_str = (
                f" | Cụm địa lý ưu tiên: {group_number}"
                if group_number is not None
                else " | Cụm địa lý: Chưa đủ tọa độ"
            )

            places_lines.append(
                f"- ID: {p.place_id} | Tên: {p.name}{flag_str} | Danh mục: {cat_str} | Địa chỉ: {addr_str} | Giờ: {hours_str} | Giá: {price_str}{group_str}"
            )
        places_block = "\n".join(places_lines)
        grouping_rules = f"""
=== QUY TẮC GOM ĐỊA ĐIỂM THEO KHU VỰC ===
- Mỗi địa điểm có tọa độ được gán vào một "Cụm địa lý ưu tiên" trong danh sách trên.
- Ưu tiên xếp các địa điểm cùng cụm vào cùng một ngày; không trộn các cụm xa nhau nếu vẫn còn lựa chọn khác.
- Khoảng cách giữa hai địa điểm trong cùng ngày nên không vượt quá khoảng {MAX_DAILY_PLACE_DISTANCE_KM:g} km.
- Nếu bắt buộc phải kết hợp các địa điểm khác cụm hoặc không có tọa độ, hãy ghi rõ trong warnings.
- Các hoạt động MEAL, REST và TRANSIT nên được đặt gần các địa điểm tham quan của cùng ngày.
"""

        # Existing itinerary preservation block
        existing_itin_block = ""
        if existing_itinerary and hasattr(existing_itinerary, "days") and existing_itinerary.days:
            itin_lines = []
            for d in existing_itinerary.days:
                acts = []
                for a in (d.activities or []):
                    p_info = f" [place_id={a.place_id}]" if getattr(a, "place_id", None) else ""
                    dur_info = f" ({a.duration_minutes} phút)" if getattr(a, "duration_minutes", None) else ""
                    acts.append(f"    * [{a.start_time or '...'}-{a.end_time or '...'}] {a.title}{p_info}{dur_info}: {a.description or ''}")
                acts_str = "\n".join(acts) if acts else "    * (Chưa có hoạt động)"
                itin_lines.append(f"- Ngày {d.day_number} ({d.title or 'Chưa đặt tên'}):\n{acts_str}")
            existing_itin_block = f"""
=== LỊCH TRÌNH HIỆN TẠI ĐANG CÓ (QUY TẮC BẢO TOÀN DỮ LIỆU) ===
{chr(10).join(itin_lines)}

QUY TẮC BẢO TOÀN LỊCH TRÌNH HIỆN CÓ (BẮT BUỘC):
1. BẢO TOÀN HOẠT ĐỘNG: Giữ nguyên tất cả các ngày và các hoạt động KHÔNG BỊ ẢNH HƯỞNG bởi yêu cầu của du khách (giữ nguyên place_id, tiêu đề và vị trí).
2. CHỈ ĐIỀU CHỈNH: Chỉ sửa đúng các mốc thời gian (start_time, end_time), thay thế, thêm hoặc bớt các hoạt động theo đúng mong muốn của du khách.
3. Không tự ý xáo trộn các ngày không liên quan.
"""

        user_req_block = ""
        if user_prompt:
            user_req_block = f"""
=== YÊU CẦU ĐẶC BIỆT / ĐIỀU CHỈNH LỊCH TRÌNH TỪ DU KHÁCH ===
Nội dung yêu cầu từ du khách: "{user_prompt}"

HƯỚNG DẪN XỬ LÝ CÁC TÌNH HUỐNG THỰC TẾ CỦA DU KHÁCH (BẮT BUỘC):
1. TÌNH HUỐNG DẬY MUỘN / NGỦ NƯỚNG (ví dụ: "đổi sang 10 giờ sáng do ngủ quá nhiều", "mai cho đi lúc 10h"):
   - Dời giờ bắt đầu của hoạt động đầu tiên sang đúng giờ du khách yêu cầu (ví dụ: "10:00").
   - Dời các hoạt động tiếp theo phù hợp; nếu buổi sáng không đủ thời gian thì tinh giản điểm phụ để du khách ăn trưa đúng giờ (11:30 - 13:00) không bị dồn dập.
2. TÌNH HUỐNG MỆT MỎI / MUỐN NGHỈ NGƠI (ví dụ: "đi nhiều quá chiều nay muốn nghỉ ở khách sạn", "ngày 2 đi nhẹ nhàng thôi"):
   - Buổi được yêu cầu nghỉ (sáng hoặc chiều) chuyển thành hoạt động nghỉ ngơi thư giãn tại khách sạn (activity_type = 'REST', place_id = null).
   - Dời các điểm tham quan bị lùi sang buổi khác hoặc tinh giản nhịp độ chuyến đi.
3. TÌNH HUỐNG ĐỔI SỞ THÍCH / BỎ ĐỊA ĐIỂM (ví dụ: "tôi không thích bảo tàng", "thay bằng chỗ nào vui hơn"):
   - Bỏ địa điểm du khách không thích khỏi lịch trình.
   - Chọn một địa điểm trải nghiệm/vui chơi hấp dẫn thay thế từ DANH SÁCH ĐỊA ĐIỂM THỰC TẾ dưới đây.
4. TÌNH HUỐNG ĐỔI CHỖ GẦN HƠN (ví dụ: "chỗ này xa quá, đổi chỗ khác gần hơn đi"):
   - Xác định địa điểm bị phàn nàn và thay bằng địa điểm cùng loại nằm trong cùng Cụm địa lý với các điểm khác trong ngày.
5. TÌNH HUỐNG THỜI TIẾT (ví dụ: "nếu chiều mai mưa thì đừng đi biển"):
   - Đổi hoặc chuẩn bị phương án trong nhà (khu vui chơi trong nhà, bảo tàng, quán cafe có view đẹp).

YÊU CẦU ĐỐI VỚI TRƯỜNG "summary":
- summary PHẢI là lời nhắn nhủ, phản hồi trực tiếp, ấm áp, thấu hiểu và dí dỏm của Hướng dẫn viên Linh AI gửi đến du khách (ví dụ: đồng cảm chuyện ngủ nướng, giải thích việc dời giờ sang 10:00 để du khách thong thả nạp lại năng lượng).
- Sử dụng văn phong đối thoại tự nhiên, không dùng Markdown (*, #, -), không chứa ID hay JSON kỹ thuật.
"""

        prompt = f"""=== THÔNG TIN CHUYẾN ĐI CẦN LẬP LỊCH TRÌNH ===
- Điểm đến chính: {city}
- Điểm đến bổ sung: {add_dests or 'Không'}
{location_block}
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
{existing_itin_block}
{user_req_block}
{grouping_rules}
=== DANH SÁCH ĐỊA ĐIỂM THỰC TẾ TRUY VẤN TỪ CƠ SỞ DỮ LIỆU (CHỈ ĐƯỢC CHỌN TỪ ĐÂY) ===
{places_block}

Hãy lập lịch trình chi tiết {duration_days} ngày. Nhắc lại: chỉ dùng place_id có trong danh sách trên!
"""
        return prompt

    @classmethod
    def _build_geographic_groups(
        cls,
        candidates: List[SearchPlaceItem],
        duration_days: int,
    ) -> Dict[int, int]:
        """Assign coordinate-backed candidates to geographic groups for prompt guidance.

        The farthest-point seeds make groups geographically distinct without requiring
        an external routing API. Candidates without coordinates are intentionally
        omitted because their location cannot be verified.
        """
        located = [
            place
            for place in candidates
            if place.latitude is not None and place.longitude is not None
        ]
        group_count = min(max(duration_days, 1), len(located))
        if group_count == 0:
            return {}

        seeds: List[SearchPlaceItem] = [located[0]]
        while len(seeds) < group_count:
            next_place = max(
                (place for place in located if place not in seeds),
                key=lambda place: min(
                    haversine_distance(
                        float(place.latitude),
                        float(place.longitude),
                        float(seed.latitude),
                        float(seed.longitude),
                    )
                    for seed in seeds
                ),
            )
            seeds.append(next_place)

        groups: Dict[int, int] = {}
        for place in located:
            nearest_group = min(
                range(len(seeds)),
                key=lambda index: haversine_distance(
                    float(place.latitude),
                    float(place.longitude),
                    float(seeds[index].latitude),
                    float(seeds[index].longitude),
                ),
            )
            groups[place.place_id] = nearest_group + 1
        return groups

    @classmethod
    def _validate_daily_geographic_distance(
        cls,
        days: List[ItineraryDayItem],
        candidate_map: Dict[int, SearchPlaceItem],
    ) -> List[str]:
        """Report days whose selected places exceed the preferred geographic distance."""
        warnings: List[str] = []
        for day in days:
            places = [
                candidate_map[activity.place_id]
                for activity in day.activities
                if activity.place_id in candidate_map
                and candidate_map[activity.place_id].latitude is not None
                and candidate_map[activity.place_id].longitude is not None
            ]
            if len(places) < 2:
                continue

            max_distance = max(
                haversine_distance(
                    float(first.latitude),
                    float(first.longitude),
                    float(second.latitude),
                    float(second.longitude),
                )
                for index, first in enumerate(places)
                for second in places[index + 1 :]
            )
            if max_distance > MAX_DAILY_PLACE_DISTANCE_KM:
                warnings.append(
                    f"Ngày {day.day_number} có các địa điểm cách nhau tối đa "
                    f"{max_distance:.1f} km, vượt ngưỡng khoảng cách ưu tiên "
                    f"{MAX_DAILY_PLACE_DISTANCE_KM:g} km."
                )
        return warnings

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

                place_summary: Optional[ItineraryPlaceSummary] = None
                if clean_place_id and clean_place_id in candidate_map:
                    cand = candidate_map[clean_place_id]
                    place_summary = ItineraryPlaceSummary(
                        place_id=cand.place_id,
                        name=cand.name,
                        category=cand.category,
                        address=cand.address,
                        description=getattr(cand, "description", None),
                        latitude=cand.latitude,
                        longitude=cand.longitude,
                        image_url=getattr(cand, "image_url", None),
                    )

                item = ItineraryActivityItem(
                    order_index=order_counter,
                    activity_type=act_type,
                    place_id=clean_place_id,
                    place=place_summary,
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

    @classmethod
    def detect_edit_intent(
        cls,
        session: Session,
        trip_id: int,
        message: str,
        conversation_id: Optional[int] = None,
        current_user: Optional[Any] = None,
        llm: Optional[Any] = None,
    ) -> Dict[str, Any]:
        """Uses LLM & RAG context to determine if a user message is an itinerary edit request.

        Evaluates the message against:
        - Current Trip info & Itinerary structure (destination, duration, days, activities)
        - Trip Planning Context
        """
        clean_msg = (message or "").strip()
        if not clean_msg:
            return {
                "is_edit_intent": False,
                "confidence": "HIGH",
                "change_prompt": None,
                "reason": "Tin nhắn rỗng.",
            }

        trip = session.get(Trip, trip_id)
        if not trip:
            return {
                "is_edit_intent": False,
                "confidence": "LOW",
                "change_prompt": None,
                "reason": f"Không tìm thấy chuyến đi ID {trip_id}.",
            }

        # Retrieve current itinerary
        itinerary = None
        try:
            itinerary = ItineraryPersistenceService.get_itinerary_by_trip_id(
                session=session,
                trip_id=trip_id,
                current_user=current_user,
                check_ownership=False,
            )
        except Exception as e:
            logger.warning("Failed to fetch current itinerary for intent detection: %s", e)

        if not itinerary or not itinerary.days:
            clean_lower = clean_msg.lower()
            is_obvious_edit = any(kw in clean_lower for kw in [
                "thêm", "bớt", "xóa", "xoá", "bỏ", "đổi", "thay", "sửa", "dời", "chuyển",
                "cập nhật", "chỉnh", "ngày", "ngay", "buổi", "buoi", "lịch trình", "lich trinh",
                "ghé", "ghe", "đi", "di", "quán", "khách sạn", "hotel", "bà nà", "hội an"
            ])
            if is_obvious_edit:
                return {
                    "is_edit_intent": True,
                    "confidence": "HIGH",
                    "change_prompt": clean_msg,
                    "reason": "Tin nhắn chứa yêu cầu chỉnh sửa/bổ sung lịch trình.",
                }
            return {
                "is_edit_intent": False,
                "confidence": "HIGH",
                "change_prompt": None,
                "reason": "Chuyến đi chưa có lịch trình nào đang hoạt động để chỉnh sửa.",
            }

        # Build concise itinerary overview
        day_lines = []
        for d in itinerary.days:
            act_names = [f"[{a.start_time or '...'}] {a.title}" for a in (d.activities or [])]
            acts_str = ", ".join(act_names) if act_names else "Chưa có hoạt động"
            day_lines.append(f"- Ngày {d.day_number} ({d.title or 'Chưa đặt tên'}): {acts_str}")
        overview_str = "\n".join(day_lines)

        dest_name = trip.destination_city or "Điểm đến"
        duration_days = len(itinerary.days)
        if trip.start_date and trip.end_date:
            try:
                duration_days = (trip.end_date - trip.start_date).days + 1
            except Exception:
                pass

        prompt = f"""Bạn là Chuyên gia AI Phân loại Ý định Chỉnh sửa Lịch trình Du lịch (Travel Itinerary Intent Classifier) của TravelWise.
Nhiệm vụ của bạn là phân tích câu nói của du khách và xác định xem du khách có đang yêu cầu:
- HOÀN TÁC / QUAY LẠI LỊCH CŨ (is_undo = true): Du khách muốn quay lại lịch trước khi sửa, giữ nguyên lịch cũ, hủy sửa đổi vừa rồi.
- CHỈNH SỬA / THAY ĐỔI / CẬP NHẬT (is_edit_intent = true): Du khách muốn sửa giờ, đổi điểm, thêm/bớt hoạt động, nghỉ ngơi, đổi nhịp độ...
- HỎI ĐÁP / TRÒ CHUYỆN THƯỜNG (is_edit_intent = false): Du khách hỏi FAQ, giờ mở cửa, giá vé, thời tiết, khen ngợi...

=== THÔNG TIN LỊCH TRÌNH HIỆN TẠI ===
- Điểm đến: {dest_name}
- Số ngày: {duration_days} ngày
- Các hoạt động hiện có trong lịch trình:
{overview_str}

=== TIN NHẮN TỪ DU KHÁCH ===
"{clean_msg}"

=== TIÊU CHÍ PHÂN LOẠI CHI TIẾT ===
1. LÀ YÊU CẦU HOÀN TÁC / QUAY LẠI LỊCH CŨ (is_undo = true, is_edit_intent = true):
- Du khách nói: "quay lại lịch cũ", "lịch trình trước khi sửa", "hoàn tác", "giữ nguyên lịch cũ nhé", "thôi không sửa nữa, để như cũ".

2. LÀ YÊU CẦU CHỈNH SỬA (is_edit_intent = true):
- Thay đổi thời gian/giờ giấc hoặc ngủ nướng (vd: "mai cho đi lúc 10h", "đổi thành 9 giờ", "dời sang 10 giờ do ngủ quá nhiều", "bắt đầu trễ hơn").
- Mệt mỏi, muốn nghỉ ngơi hoặc giãn nhịp độ (vd: "đi nhiều quá chiều nay muốn nghỉ ở khách sạn thôi", "ngày thứ hai muốn đi nhẹ nhàng thôi", "lịch dày quá giãn bớt").
- Thêm, bớt, bỏ qua hoặc thay thế địa điểm (vd: "thêm quán cà phê sau khi ăn trưa", "bỏ chỗ vừa rồi ra", "tôi không thích bảo tàng, có chỗ nào vui hơn không", "đổi hai địa điểm đó cho nhau").
- Khoảng cách / vị trí (vd: "chỗ này xa quá đổi chỗ gần hơn", "tìm chỗ tương tự nhưng gần hơn").
- Điều kiện thời tiết (vd: "nếu chiều mai mưa thì đừng cho đi biển nhé").
- Tổng hợp nhiều yêu cầu (vd: "mai bắt đầu lúc 10 giờ, bỏ điểm đầu tiên và dành thêm thời gian ăn trưa").

3. KHÔNG PHẢI YÊU CẦU CHỈNH SỬA (is_edit_intent = false):
- Hỏi đáp thông tin tham khảo, tra cứu FAQ, giá vé, giờ mở cửa, khoảng cách, phương tiện (vd: "Bà Nà mở cửa mấy giờ?", "Vé cáp treo bao nhiêu?", "Thời tiết Đà Nẵng mùa này thế nào?").
- Lời chào hỏi, cảm ơn, khen chê (vd: "Cảm ơn bạn", "Linh AI giỏi quá", "Xin chào").
- Yêu cầu tạo mới hoàn toàn chuyến đi khác ở thành phố khác (đây là tạo mới từ đầu).

Chỉ trả về DUY NHẤT một khối JSON hợp lệ theo đúng cấu trúc sau (không kèm markdown ngoài JSON):
{{
  "is_edit_intent": true,
  "is_undo": false,
  "confidence": "HIGH",
  "change_prompt": "Mô tả chuẩn xác yêu cầu thay đổi lịch trình bằng tiếng Việt (hoặc null nếu không phải)",
  "reason": "Giải thích ngắn gọn lý do phân loại"
}}
"""

        try:
            chat_llm = llm or get_chat_llm(temperature=0.0)
            llm_res = chat_llm.invoke([HumanMessage(content=prompt)])
            raw_text = extract_response_text(getattr(llm_res, "content", llm_res)).strip()
            parsed = cls._parse_json_from_llm(raw_text)

            is_undo = bool(parsed.get("is_undo", False))
            is_edit = bool(parsed.get("is_edit_intent", False)) or is_undo
            change_prompt = parsed.get("change_prompt") if is_edit else None
            confidence = parsed.get("confidence", "HIGH")
            reason = parsed.get("reason", "")

            # Rule-based safety check for undo
            clean_lower = clean_msg.lower()
            if any(kw in clean_lower for kw in ["quay lại lịch", "lịch trước khi sửa", "hoàn tác", "giữ nguyên lịch cũ", "như cũ"]):
                is_undo = True
                is_edit = True

            return {
                "is_edit_intent": is_edit,
                "is_undo": is_undo,
                "confidence": confidence,
                "change_prompt": change_prompt or clean_msg if is_edit else None,
                "reason": reason,
            }
        except Exception as e:
            logger.error("Error detecting edit intent with LLM: %s", e)
            # Safe fallback: do not trigger accidental edits on failure
            return {
                "is_edit_intent": False,
                "confidence": "LOW",
                "change_prompt": None,
                "reason": f"Lỗi phân loại ý định: {str(e)}",
            }
