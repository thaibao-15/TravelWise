"""
Tools and Execution Engine for conversational itinerary modifications via LLM Function Calling.
"""

from datetime import datetime, time, timedelta
from decimal import Decimal
import json
import logging
import re
import unicodedata
from typing import Any, Dict, List, Optional, Tuple

from pydantic import BaseModel, Field
from sqlmodel import Session, select

from app.db.base import _utcnow
from app.models.itinerary_activity import ItineraryActivity
from app.models.itinerary_day import ItineraryDay
from app.models.place import Place
from app.models.trip import Trip
from app.models.trip_preference import TripPreference
from app.schemas.itinerary import (
    EditStatusEnum,
    ItineraryDetailResponse,
    ItineraryEditResponse,
    ItineraryGenerationResponse,
)
from app.services.itinerary_persistence_service import ItineraryPersistenceService
from app.services.place_service import PlaceService

logger = logging.getLogger(__name__)


# =============================================================================
# 1. Pydantic Tool Schemas for LLM Function Calling
# =============================================================================

class update_activity_time(BaseModel):
    """Điều chỉnh thời gian bắt đầu hoặc kết thúc của một hoạt động cụ thể (ví dụ: dậy trễ, dời giờ, bắt đầu muộn hơn)."""
    day_number: int = Field(description="Số thứ tự ngày trong lịch trình (1, 2, 3...)")
    place_name: Optional[str] = Field(None, description="Tên địa điểm hoặc hoạt động cần đổi giờ (nếu áp dụng cho địa điểm cụ thể)")
    new_start_time: str = Field(description="Giờ bắt đầu mới theo định dạng HH:MM, ví dụ '10:00'")
    new_end_time: Optional[str] = Field(None, description="Giờ kết thúc mới theo định dạng HH:MM")


class remove_activity(BaseModel):
    """Xóa một hoạt động hoặc địa điểm khỏi một ngày cụ thể (ví dụ: bỏ bảo tàng, bỏ bớt điểm mệt mỏi)."""
    day_number: int = Field(description="Số thứ tự ngày trong lịch trình (1, 2, 3...)")
    place_name: Optional[str] = Field(None, description="Tên địa điểm cần xóa khỏi lịch trình")
    time_slot: Optional[str] = Field(None, description="Buổi muốn xóa nếu hủy cả buổi (morning, afternoon, evening)")


class add_activity(BaseModel):
    """Thêm một hoạt động tham quan, ăn uống hoặc nghỉ ngơi mới vào lịch trình."""
    day_number: int = Field(description="Số thứ tự ngày trong lịch trình (1, 2, 3...)")
    place_name: str = Field(description="Tên địa điểm hoặc hoạt động muốn thêm (ví dụ 'Cà phê Trình', 'Bánh xèo Bà Dưỡng')")
    preferred_time: Optional[str] = Field(None, description="Khung giờ dự kiến HH:MM hoặc buổi (sáng/trưa/chiều/tối)")
    insert_after_place: Optional[str] = Field(None, description="Tên địa điểm đứng trước nếu muốn chèn ngay sau")
    note: Optional[str] = Field(None, description="Ghi chú thêm về hoạt động")


class replace_activity(BaseModel):
    """Thay thế một địa điểm hoặc hoạt động cũ bằng một địa điểm/hoạt động mới tương đương."""
    day_number: int = Field(description="Số thứ tự ngày trong lịch trình (1, 2, 3...)")
    old_place_name: str = Field(description="Tên địa điểm cũ cần thay thế")
    new_place_or_category: str = Field(description="Tên địa điểm mới hoặc loại hình mới muốn đổi sang (ví dụ 'quán cà phê', 'Bánh xèo Bà Dưỡng')")


class swap_activities(BaseModel):
    """Tráo đổi vị trí/thứ tự giữa hai hoạt động trong cùng một ngày hoặc giữa hai ngày khác nhau."""
    day_number_1: int = Field(description="Ngày của hoạt động thứ nhất (1, 2, 3...)")
    place_name_1: str = Field(description="Tên địa điểm hoặc hoạt động thứ nhất")
    day_number_2: Optional[int] = Field(None, description="Ngày của hoạt động thứ hai (nếu khác ngày thứ nhất, mặc định cùng ngày)")
    place_name_2: str = Field(description="Tên địa điểm hoặc hoạt động thứ hai")


class change_activity_duration(BaseModel):
    """Tăng hoặc giảm thời lượng (thời gian tham quan) của một hoạt động và tự động tịnh tiến các hoạt động sau."""
    day_number: int = Field(description="Số thứ tự ngày trong lịch trình (1, 2, 3...)")
    place_name: str = Field(description="Tên địa điểm muốn tăng/giảm thời gian")
    new_duration_minutes: int = Field(description="Thời lượng mới tính bằng phút (ví dụ: 60, 90, 120, 180)")


class clear_day_activities(BaseModel):
    """Xóa toàn bộ hoạt động trong một ngày để dành trọn ngày nghỉ ngơi hoặc tự do khám phá."""
    day_number: int = Field(description="Số thứ tự ngày muốn để trống / nghỉ ngơi (1, 2, 3...)")
    note: Optional[str] = Field("Nghỉ ngơi và tự do khám phá", description="Mục đích của ngày tự do")


class review_current_itinerary(BaseModel):
    """Đọc, tóm tắt và đánh giá tổng quan toàn bộ lịch trình chuyến đi hiện tại (các ngày, địa điểm, thời gian, nhịp độ)."""
    focus_day: Optional[int] = Field(None, description="Nếu du khách chỉ muốn review riêng một ngày cụ thể (1, 2, 3...)")
    perspective: Optional[str] = Field("overview", description="Góc nhìn review: 'overview' (toàn cảnh), 'pace' (nhịp độ), 'budget' (chi phí)")


class undo_last_edit(BaseModel):
    """Khôi phục lại lịch trình trước khi có lần chỉnh sửa gần nhất (hoàn tác / quay lại lịch cũ)."""
    confirm: bool = Field(True, description="Xác nhận hoàn tác về lịch cũ")


ITINERARY_EDIT_TOOLS = [
    update_activity_time,
    remove_activity,
    add_activity,
    replace_activity,
    swap_activities,
    change_activity_duration,
    clear_day_activities,
    review_current_itinerary,
    undo_last_edit,
]


# =============================================================================
# 2. Database Executor for Itinerary Tool Calls
# =============================================================================

class ItineraryToolExecutor:
    """Executes validated tool calls directly against SQL Server within a transaction."""

    @staticmethod
    def _normalize(text: Optional[str]) -> str:
        """Helper to normalize text for accent-insensitive and lowercase fuzzy matching."""
        if not text:
            return ""
        clean = text.replace("đ", "d").replace("Đ", "D").strip().lower()
        nfkd = unicodedata.normalize("NFD", clean)
        return "".join([c for c in nfkd if unicodedata.category(c) != "Mn"])

    @staticmethod
    def _parse_time(time_str: Optional[str]) -> Optional[time]:
        if not time_str:
            return None
        match = re.search(r"(\d{1,2}):(\d{2})", str(time_str))
        if match:
            h, m = int(match.group(1)), int(match.group(2))
            return time(max(0, min(23, h)), max(0, min(59, m)))
        return None

    @classmethod
    def execute_update_time(
        cls,
        session: Session,
        trip_id: int,
        day_number: int,
        new_start_time: str,
        place_name: Optional[str] = None,
        new_end_time: Optional[str] = None,
    ) -> Tuple[bool, str]:
        """Update activity start and end times, shifting subsequent events if necessary."""
        day = session.exec(
            select(ItineraryDay)
            .where(ItineraryDay.trip_id == trip_id, ItineraryDay.day_number == day_number)
        ).first()
        if not day:
            return False, f"Không tìm thấy ngày {day_number} trong lịch trình."

        activities = session.exec(
            select(ItineraryActivity)
            .where(ItineraryActivity.itinerary_day_id == day.id)
            .order_by(ItineraryActivity.order_index)
        ).all()
        if not activities:
            return False, f"Ngày {day_number} chưa có hoạt động nào để điều chỉnh."

        target_act = None
        if place_name:
            norm_name = cls._normalize(place_name)
            for act in activities:
                title_norm = cls._normalize(act.title)
                place_norm = cls._normalize(act.place.name) if act.place else ""
                if norm_name in title_norm or norm_name in place_norm or title_norm in norm_name:
                    target_act = act
                    break
        else:
            # If no place specified (e.g. "wake up at 10:00"), adjust the very first activity of the day
            target_act = activities[0]

        if not target_act:
            target_act = activities[0]

        parsed_start = cls._parse_time(new_start_time)
        if not parsed_start:
            return False, f"Giờ bắt đầu không hợp lệ: {new_start_time}"

        dur_mins = target_act.duration_minutes or 90
        parsed_end = cls._parse_time(new_end_time)
        if not parsed_end:
            start_dt = datetime.combine(datetime.today(), parsed_start)
            end_dt = start_dt + timedelta(minutes=dur_mins)
            parsed_end = end_dt.time()

        target_act.start_time = parsed_start
        target_act.end_time = parsed_end
        session.add(target_act)

        # Shift subsequent activities if they overlap
        curr_end_dt = datetime.combine(datetime.today(), parsed_end)
        for act in activities:
            if act.order_index > target_act.order_index and act.start_time:
                act_start_dt = datetime.combine(datetime.today(), act.start_time)
                if act_start_dt < curr_end_dt:
                    act_dur = act.duration_minutes or 60
                    new_act_start = curr_end_dt + timedelta(minutes=15)
                    act.start_time = new_act_start.time()
                    act.end_time = (new_act_start + timedelta(minutes=act_dur)).time()
                    curr_end_dt = new_act_start + timedelta(minutes=act_dur)
                    session.add(act)

        session.commit()
        act_name = target_act.place.name if target_act.place else target_act.title
        return True, f"Đã dời giờ bắt đầu {act_name} sang {new_start_time}."

    @classmethod
    def execute_remove_activity(
        cls,
        session: Session,
        trip_id: int,
        day_number: int,
        place_name: Optional[str] = None,
        time_slot: Optional[str] = None,
    ) -> Tuple[bool, str]:
        """Remove specified activity or activities in a timeslot and reindex remaining."""
        day = session.exec(
            select(ItineraryDay)
            .where(ItineraryDay.trip_id == trip_id, ItineraryDay.day_number == day_number)
        ).first()
        if not day:
            return False, f"Không tìm thấy ngày {day_number}."

        activities = session.exec(
            select(ItineraryActivity)
            .where(ItineraryActivity.itinerary_day_id == day.id)
            .order_by(ItineraryActivity.order_index)
        ).all()
        if not activities:
            return False, f"Ngày {day_number} không có hoạt động nào để xóa."

        removed_names = []
        norm_name = cls._normalize(place_name) if place_name else None

        for act in activities:
            to_remove = False
            title_norm = cls._normalize(act.title)
            p_norm = cls._normalize(act.place.name) if act.place else ""

            if norm_name and (norm_name in title_norm or norm_name in p_norm or title_norm in norm_name or (p_norm and p_norm in norm_name)):
                to_remove = True
            elif time_slot:
                st = act.start_time.hour if act.start_time else 12
                if time_slot == "morning" and st < 12:
                    to_remove = True
                elif time_slot == "afternoon" and 12 <= st < 18:
                    to_remove = True
                elif time_slot == "evening" and st >= 18:
                    to_remove = True

            if to_remove:
                name_display = act.place.name if act.place else act.title
                removed_names.append(name_display)
                session.delete(act)

        if not removed_names:
            return False, f"Không tìm thấy hoạt động '{place_name or time_slot}' trong ngày {day_number}."

        session.commit()

        # Re-index remaining activities
        remaining = session.exec(
            select(ItineraryActivity)
            .where(ItineraryActivity.itinerary_day_id == day.id)
            .order_by(ItineraryActivity.order_index)
        ).all()
        for idx, act in enumerate(remaining, start=1):
            act.order_index = idx
            session.add(act)
        session.commit()

        return True, f"Đã xóa {', '.join(removed_names)} khỏi ngày {day_number}."

    @classmethod
    def execute_add_activity(
        cls,
        session: Session,
        trip_id: int,
        day_number: int,
        place_name: str,
        preferred_time: Optional[str] = None,
        insert_after_place: Optional[str] = None,
        note: Optional[str] = None,
    ) -> Tuple[bool, str]:
        """Find matching real place in DB and insert activity at correct slot."""
        day = session.exec(
            select(ItineraryDay)
            .where(ItineraryDay.trip_id == trip_id, ItineraryDay.day_number == day_number)
        ).first()
        if not day:
            return False, f"Không tìm thấy ngày {day_number}."

        matched_place = None
        places = PlaceService.search_places_by_keyword(session, place_name, limit=5)
        if places:
            matched_place = places[0]

        activities = session.exec(
            select(ItineraryActivity)
            .where(ItineraryActivity.itinerary_day_id == day.id)
            .order_by(ItineraryActivity.order_index)
        ).all()

        parsed_start = cls._parse_time(preferred_time)
        if not parsed_start:
            if activities and activities[-1].end_time:
                last_end_dt = datetime.combine(datetime.today(), activities[-1].end_time)
                parsed_start = (last_end_dt + timedelta(minutes=30)).time()
            else:
                parsed_start = time(15, 0)

        start_dt = datetime.combine(datetime.today(), parsed_start)
        parsed_end = (start_dt + timedelta(minutes=90)).time()

        insert_idx = len(activities) + 1
        if insert_after_place:
            norm_after = insert_after_place.lower().strip()
            for act in activities:
                title_lower = (act.title or "").lower()
                p_name = (act.place.name or "").lower() if act.place else ""
                if norm_after in title_lower or norm_after in p_name:
                    insert_idx = act.order_index + 1
                    break

        # Shift activities after insert_idx
        for act in activities:
            if act.order_index >= insert_idx:
                act.order_index += 1
                session.add(act)

        title = f"Tham quan {matched_place.name}" if matched_place else place_name
        new_act = ItineraryActivity(
            itinerary_day_id=day.id,
            place_id=matched_place.id if matched_place else None,
            activity_type="VISIT" if matched_place else "REST",
            title=title,
            description=matched_place.description if matched_place else note,
            start_time=parsed_start,
            end_time=parsed_end,
            duration_minutes=90,
            order_index=insert_idx,
            note=note,
        )
        session.add(new_act)
        session.commit()

        display_name = matched_place.name if matched_place else place_name
        return True, f"Đã thêm '{display_name}' vào ngày {day_number} lúc {parsed_start.strftime('%H:%M')}."

    @classmethod
    def execute_replace_activity(
        cls,
        session: Session,
        trip_id: int,
        day_number: int,
        old_place_name: str,
        new_place_or_category: str,
    ) -> Tuple[bool, str]:
        """Replace an activity place with another candidate."""
        day = session.exec(
            select(ItineraryDay)
            .where(ItineraryDay.trip_id == trip_id, ItineraryDay.day_number == day_number)
        ).first()
        if not day:
            return False, f"Không tìm thấy ngày {day_number}."

        activities = session.exec(
            select(ItineraryActivity)
            .where(ItineraryActivity.itinerary_day_id == day.id)
            .order_by(ItineraryActivity.order_index)
        ).all()

        target_act = None
        norm_old = cls._normalize(old_place_name)
        for act in activities:
            title_norm = cls._normalize(act.title)
            p_norm = cls._normalize(act.place.name) if act.place else ""
            if norm_old in title_norm or norm_old in p_norm or title_norm in norm_old:
                target_act = act
                break

        if not target_act:
            return False, f"Không tìm thấy địa điểm '{old_place_name}' trong ngày {day_number} để thay thế."

        places = PlaceService.search_places_by_keyword(session, new_place_or_category, limit=5)
        new_place = places[0] if places else None

        if new_place:
            target_act.place_id = new_place.id
            target_act.title = f"Tham quan {new_place.name}"
            target_act.description = new_place.description
        else:
            target_act.title = new_place_or_category
            target_act.place_id = None

        session.add(target_act)
        session.commit()

        new_name = new_place.name if new_place else new_place_or_category
        return True, f"Đã đổi '{old_place_name}' thành '{new_name}' ở ngày {day_number}."

    @classmethod
    def execute_swap_activities(
        cls,
        session: Session,
        trip_id: int,
        day_number_1: int,
        place_name_1: str,
        day_number_2: Optional[int],
        place_name_2: str,
    ) -> Tuple[bool, str]:
        """Swap order or schedule between two activities (same day or different days)."""
        d2_num = day_number_2 or day_number_1
        day1 = session.exec(
            select(ItineraryDay)
            .where(ItineraryDay.trip_id == trip_id, ItineraryDay.day_number == day_number_1)
        ).first()
        day2 = session.exec(
            select(ItineraryDay)
            .where(ItineraryDay.trip_id == trip_id, ItineraryDay.day_number == d2_num)
        ).first()
        if not day1 or not day2:
            return False, f"Không tìm thấy ngày {day_number_1} hoặc ngày {d2_num}."

        acts1 = session.exec(
            select(ItineraryActivity).where(ItineraryActivity.itinerary_day_id == day1.id)
        ).all()
        acts2 = (
            acts1
            if day1.id == day2.id
            else session.exec(
                select(ItineraryActivity).where(ItineraryActivity.itinerary_day_id == day2.id)
            ).all()
        )

        norm_p1 = cls._normalize(place_name_1)
        norm_p2 = cls._normalize(place_name_2)

        act1 = None
        for a in acts1:
            t_norm = cls._normalize(a.title)
            p_norm = cls._normalize(a.place.name) if a.place else ""
            if norm_p1 in t_norm or norm_p1 in p_norm or t_norm in norm_p1:
                act1 = a
                break

        act2 = None
        for a in acts2:
            if a.id == getattr(act1, "id", None):
                continue
            t_norm = cls._normalize(a.title)
            p_norm = cls._normalize(a.place.name) if a.place else ""
            if norm_p2 in t_norm or norm_p2 in p_norm or t_norm in norm_p2:
                act2 = a
                break

        if not act1 or not act2:
            return False, f"Không tìm thấy '{place_name_1}' hoặc '{place_name_2}' để tráo đổi."

        # Swap start_time, end_time, order_index, and day if different
        if day1.id == day2.id:
            act1.order_index, act2.order_index = act2.order_index, act1.order_index
            act1.start_time, act2.start_time = act2.start_time, act1.start_time
            act1.end_time, act2.end_time = act2.end_time, act1.end_time
        else:
            act1.itinerary_day_id, act2.itinerary_day_id = day2.id, day1.id
            act1.order_index, act2.order_index = act2.order_index, act1.order_index
            act1.start_time, act2.start_time = act2.start_time, act1.start_time
            act1.end_time, act2.end_time = act2.end_time, act1.end_time

        session.add(act1)
        session.add(act2)
        session.commit()

        name1 = act1.place.name if act1.place else act1.title
        name2 = act2.place.name if act2.place else act2.title
        return True, f"Đã tráo đổi vị trí giữa '{name1}' và '{name2}'."

    @classmethod
    def execute_change_duration(
        cls,
        session: Session,
        trip_id: int,
        day_number: int,
        place_name: str,
        new_duration_minutes: int,
    ) -> Tuple[bool, str]:
        """Adjust duration of an activity and shift subsequent events."""
        day = session.exec(
            select(ItineraryDay)
            .where(ItineraryDay.trip_id == trip_id, ItineraryDay.day_number == day_number)
        ).first()
        if not day:
            return False, f"Không tìm thấy ngày {day_number}."

        activities = session.exec(
            select(ItineraryActivity)
            .where(ItineraryActivity.itinerary_day_id == day.id)
            .order_by(ItineraryActivity.order_index)
        ).all()

        norm_p = cls._normalize(place_name)
        target_act = None
        for a in activities:
            t_norm = cls._normalize(a.title)
            p_norm = cls._normalize(a.place.name) if a.place else ""
            if norm_p in t_norm or norm_p in p_norm or t_norm in norm_p:
                target_act = a
                break

        if not target_act:
            return False, f"Không tìm thấy hoạt động '{place_name}' trong ngày {day_number}."

        duration = max(15, min(600, int(new_duration_minutes)))
        target_act.duration_minutes = duration

        if target_act.start_time:
            st_dt = datetime.combine(datetime.today(), target_act.start_time)
            end_dt = st_dt + timedelta(minutes=duration)
            target_act.end_time = end_dt.time()
            session.add(target_act)

            # Shift subsequent events
            curr_end_dt = end_dt
            for act in activities:
                if act.order_index > target_act.order_index and act.start_time:
                    act_st_dt = datetime.combine(datetime.today(), act.start_time)
                    if act_st_dt < curr_end_dt:
                        act_dur = act.duration_minutes or 60
                        new_st = curr_end_dt + timedelta(minutes=15)
                        act.start_time = new_st.time()
                        act.end_time = (new_st + timedelta(minutes=act_dur)).time()
                        curr_end_dt = new_st + timedelta(minutes=act_dur)
                        session.add(act)

        session.commit()
        act_name = target_act.place.name if target_act.place else target_act.title
        return True, f"Đã chỉnh thời lượng tham quan '{act_name}' thành {duration} phút."

    @classmethod
    def execute_clear_day(
        cls,
        session: Session,
        trip_id: int,
        day_number: int,
        note: Optional[str] = "Nghỉ ngơi và tự do khám phá",
    ) -> Tuple[bool, str]:
        """Clear all activities of a day and set as free leisure day."""
        day = session.exec(
            select(ItineraryDay)
            .where(ItineraryDay.trip_id == trip_id, ItineraryDay.day_number == day_number)
        ).first()
        if not day:
            return False, f"Không tìm thấy ngày {day_number}."

        activities = session.exec(
            select(ItineraryActivity).where(ItineraryActivity.itinerary_day_id == day.id)
        ).all()
        for act in activities:
            session.delete(act)
        session.commit()

        free_act = ItineraryActivity(
            itinerary_day_id=day.id,
            activity_type="REST",
            title=note or "Nghỉ ngơi và tự do khám phá",
            description="Dành trọn vẹn thời gian nghỉ ngơi thư giãn tại khách sạn hoặc tự do dạo phố.",
            start_time=time(9, 0),
            end_time=time(21, 0),
            duration_minutes=720,
            order_index=1,
            note=note,
        )
        session.add(free_act)
        session.commit()
        return True, f"Đã xóa các hoạt động ngày {day_number} để dành trọn ngày {note}."

    @classmethod
    def execute_review_itinerary(
        cls,
        session: Session,
        trip_id: int,
        focus_day: Optional[int] = None,
        perspective: Optional[str] = "overview",
        current_user: Optional[Any] = None,
    ) -> Tuple[bool, str]:
        """Read and formulate a warm, natural and detailed conversational summary of the itinerary."""
        details = ItineraryPersistenceService.get_itinerary_by_trip_id(
            session=session,
            trip_id=trip_id,
            current_user=current_user,
            check_ownership=True if current_user else False,
        )
        if not details or not details.days:
            return False, "Chuyến đi này hiện chưa có lịch trình nào được lưu để review."

        target_days = [d for d in details.days if not focus_day or d.day_number == focus_day]
        if not target_days:
            return False, f"Không tìm thấy ngày {focus_day} trong lịch trình."

        day_descriptions = []
        for d in target_days:
            day_title_part = f" - {d.title}" if d.title else ""
            acts = d.activities or []
            if not acts:
                day_descriptions.append(f"Ngày {d.day_number}{day_title_part}: Hôm nay bạn dành trọn thời gian tự do khám phá và nghỉ ngơi.")
                continue

            act_texts = []
            for a in acts:
                p_name = a.place.name if a.place else a.title
                st = a.start_time.strftime("%H:%M") if hasattr(a.start_time, "strftime") else (str(a.start_time)[:5] if a.start_time else "")
                et = a.end_time.strftime("%H:%M") if hasattr(a.end_time, "strftime") else (str(a.end_time)[:5] if a.end_time else "")
                time_span = f"lúc {st}" if st and not et else (f"từ {st} đến {et}" if st and et else "")
                act_texts.append(f"{p_name} ({time_span})".strip())

            day_descriptions.append(f"• Ngày {d.day_number}{day_title_part}: Bắt đầu với " + ", sau đó là ".join(act_texts) + ".")

        all_days_speech = "\n".join(day_descriptions)

        if focus_day:
            return True, f"Dưới đây là chi tiết lịch trình ngày {focus_day} của bạn nè:\n{all_days_speech}\nBạn có muốn điều chỉnh thêm điểm nào trong ngày này không?"

        dest_name = details.destination_city or "chuyến đi"
        total_days = len(details.days)
        review_msg = (
            f"Dạ, Linh AI xin tóm tắt toàn bộ lịch trình {dest_name} {total_days} ngày của bạn như sau:\n\n"
            f"{all_days_speech}\n\n"
            f"Lịch trình được sắp xếp rất thong thả và tiện cung đường di chuyển rồi đó! Bạn muốn đổi điểm hay dời giờ nào thì cứ bảo mình nhé."
        )
        return True, review_msg

    @classmethod
    def execute_undo(
        cls,
        session: Session,
        trip_id: int,
        current_user: Optional[Any] = None,
        allow_overwrite: bool = True,
    ) -> Tuple[bool, str]:
        """Restore previous itinerary backup snapshot."""
        pref = session.exec(select(TripPreference).where(TripPreference.trip_id == trip_id)).first()
        if not pref or not pref.special_requirements:
            return False, "Không tìm thấy phiên bản lịch trình trước đó để khôi phục."

        try:
            stored = json.loads(pref.special_requirements)
            if not isinstance(stored, dict) or "backup_itinerary" not in stored:
                return False, "Không có dữ liệu lịch trình cũ để hoàn tác."

            backup_data = stored["backup_itinerary"]
            backup_itin = ItineraryGenerationResponse.model_validate(backup_data)
            ItineraryPersistenceService.save_itinerary(
                session=session,
                trip_id=trip_id,
                itinerary=backup_itin,
                current_user=current_user,
                allow_overwrite_confirmed=allow_overwrite,
                check_ownership=True if current_user else False,
            )
            return True, "Đã khôi phục thành công lịch trình trước khi chỉnh sửa."
        except Exception as e:
            logger.error("Undo execution failed: %s", e)
            return False, f"Lỗi hoàn tác: {str(e)}"

