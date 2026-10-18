"""
Itinerary Persistence and Retrieval Service for TravelWise.

Handles:
1. Strict domain validation of generated itineraries before saving.
2. Safe, atomic database persistence with full transaction rollback on failure.
3. Overwrite protection for CONFIRMED trips.
4. Idempotent saving preventing duplicate days and activities on retry.
5. Optimized retrieval (eager loading avoiding N+1 queries).
6. User-scoped trip listing with pagination and status filtering.
"""

from datetime import date, datetime, time, timedelta
from decimal import Decimal
import logging
import re
from typing import Any, Dict, List, Optional, Set, Tuple

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import selectinload
from sqlmodel import Session, select

from app.db.base import _utcnow
from app.models.category import Category
from app.models.itinerary_activity import ItineraryActivity
from app.models.itinerary_day import ItineraryDay
from app.models.place import Place
from app.models.trip import Trip
from app.models.user import User
from app.schemas.itinerary import (
    ItineraryActivityCreate,
    ItineraryActivityDetail,
    ItineraryActivityUpdate,
    ItineraryDayDetail,
    ItineraryDetailResponse,
    ItineraryGenerationResponse,
    ItineraryPlaceSummary,
    ItineraryStatusEnum,
    TripListResponse,
    TripSummaryItem,
    ValidationResult,
)
from app.schemas.trip_planning import TripPlanningContext

logger = logging.getLogger(__name__)


class ItineraryPersistenceService:
    """Service managing validation, persistence, and retrieval of trip itineraries."""

    # -------------------------------------------------------------------------
    # 1. Validation Layer
    # -------------------------------------------------------------------------
    @classmethod
    def validate_itinerary(
        cls,
        session: Session,
        itinerary: ItineraryGenerationResponse,
        context: Optional[TripPlanningContext] = None,
        candidate_place_ids: Optional[Set[int]] = None,
    ) -> ValidationResult:
        """Validates itinerary structural integrity, real places existence, times and costs.

        Returns:
            ValidationResult with is_valid, list of errors, warnings and unresolved requirements.
        """
        errors: List[str] = []
        warnings: List[str] = []
        unresolved: List[str] = []

        # 1.1 Structural validation
        if itinerary.status == ItineraryStatusEnum.FAILED.value:
            errors.append("Lịch trình đang ở trạng thái thất bại (FAILED).")
            return ValidationResult(is_valid=False, errors=errors, warnings=itinerary.warnings)

        duration = itinerary.duration_days
        if duration is None or duration <= 0:
            errors.append("Thời lượng chuyến đi (duration_days) không hợp lệ (phải > 0).")

        if itinerary.status == ItineraryStatusEnum.GENERATED.value:
            if not itinerary.days:
                errors.append("Lịch trình có trạng thái GENERATED nhưng không có ngày nào (days trống).")
            elif duration is not None and len(itinerary.days) != duration:
                warnings.append(
                    f"Số ngày tạo được ({len(itinerary.days)}) không khớp với thời lượng yêu cầu ({duration})."
                )

        # Validate day numbers continuity (1..N)
        day_numbers = [d.day_number for d in itinerary.days]
        if day_numbers:
            expected_days = list(range(1, len(day_numbers) + 1))
            if day_numbers != expected_days:
                warnings.append(
                    f"Thứ tự day_number không liên tục từ 1..N: {day_numbers}. Hệ thống sẽ chuẩn hóa."
                )

        # 1.2 Batch place verification in SQL Server
        all_place_ids: Set[int] = set()
        for day in itinerary.days:
            for act in day.activities:
                if act.place_id is not None:
                    try:
                        all_place_ids.add(int(act.place_id))
                    except (ValueError, TypeError):
                        errors.append(f"place_id '{act.place_id}' không phải là số nguyên hợp lệ.")

        db_place_map: Dict[int, Place] = {}
        if all_place_ids:
            stmt = (
                select(Place)
                .where(Place.id.in_(all_place_ids), Place.is_deleted == False)  # noqa: E712
            )
            found_places = session.exec(stmt).all()
            db_place_map = {p.id: p for p in found_places}

        # Excluded places check
        excluded_norms: Set[str] = set()
        if context and context.place_requirements.excluded:
            excluded_norms = {
                cls._normalize_text(item.name)
                for item in context.place_requirements.excluded
                if item.name
            }

        # Validate activities in each day
        for d_idx, day in enumerate(itinerary.days):
            prev_end_min: Optional[int] = None
            for a_idx, act in enumerate(day.activities):
                # Verify place_id
                if act.place_id is not None:
                    if act.place_id not in db_place_map:
                        warnings.append(
                            f"Địa điểm ID={act.place_id} trong hoạt động '{act.title}' không tồn tại hoặc đã bị xóa trong cơ sở dữ liệu."
                        )
                        act.place_id = None
                    elif candidate_place_ids and act.place_id not in candidate_place_ids:
                        warnings.append(
                            f"Địa điểm ID={act.place_id} không nằm trong danh sách được phép cho lần lập lịch trình này."
                        )
                        act.place_id = None

                # Excluded place check
                act_title_norm = cls._normalize_text(act.title)
                is_excluded = any(ex in act_title_norm for ex in excluded_norms if len(ex) >= 3)
                if act.place_id and act.place_id in db_place_map:
                    p_name_norm = cls._normalize_text(db_place_map[act.place_id].name)
                    if any(ex in p_name_norm for ex in excluded_norms if len(ex) >= 3):
                        is_excluded = True

                if is_excluded:
                    warnings.append(
                        f"Hoạt động '{act.title}' liên quan đến địa điểm bị loại trừ; tự động gỡ bỏ địa điểm."
                    )
                    act.place_id = None

                # Non-negative durations and costs
                if act.duration_minutes is not None and act.duration_minutes < 0:
                    warnings.append(f"Thời lượng hoạt động '{act.title}' là số âm ({act.duration_minutes}); chuyển về null.")
                    act.duration_minutes = None

                if act.estimated_cost is not None and act.estimated_cost < 0:
                    warnings.append(f"Chi phí hoạt động '{act.title}' là số âm ({act.estimated_cost}); chuyển về null.")
                    act.estimated_cost = None

                if act.travel_duration_minutes is not None and act.travel_duration_minutes < 0:
                    act.travel_duration_minutes = None

                if act.travel_distance_km is not None and act.travel_distance_km < 0:
                    act.travel_distance_km = None

                # Times validation
                start_min = cls._time_to_minutes(act.start_time)
                end_min = cls._time_to_minutes(act.end_time)

                if start_min is not None and end_min is not None:
                    if start_min > end_min:
                        warnings.append(
                            f"Giờ bắt đầu ({act.start_time}) muộn hơn giờ kết thúc ({act.end_time}) tại '{act.title}'."
                        )
                    if prev_end_min is not None and start_min < prev_end_min:
                        warnings.append(
                            f"Hoạt động '{act.title}' ({act.start_time}) bị trùng giờ với hoạt động trước ({cls._minutes_to_time(prev_end_min)})."
                        )
                    prev_end_min = max(end_min, prev_end_min or end_min)

        is_valid = len(errors) == 0
        return ValidationResult(
            is_valid=is_valid,
            errors=errors,
            warnings=list(dict.fromkeys(warnings)),
            unresolved_requirements=list(dict.fromkeys(unresolved)),
        )

    # -------------------------------------------------------------------------
    # 2. Persistence Layer
    # -------------------------------------------------------------------------
    @classmethod
    def save_itinerary(
        cls,
        session: Session,
        trip_id: int,
        itinerary: ItineraryGenerationResponse,
        current_user: Optional[User] = None,
        allow_overwrite_confirmed: bool = False,
        check_ownership: bool = True,
        context: Optional[TripPlanningContext] = None,
    ) -> ItineraryDetailResponse:
        """Atomically persists a validated itinerary into SQL Server.

        Steps:
        1. Verify trip existence and user authorization.
        2. Prevent silent overwriting of CONFIRMED trips.
        3. Validate itinerary rules before touching database.
        4. In a transaction:
           - Remove previous itinerary days for this trip (cascade deletes activities).
           - Insert all new days and activities in exact sequential order.
           - Update trip status to 'GENERATED' and update updated_at.
           - Commit transaction (rollback cleanly on any exception).
        5. Return full detailed response with generated IDs.
        """
        # 1. Fetch trip
        trip = session.get(Trip, trip_id)
        if not trip:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
            )

        # 2. Authorization check
        if check_ownership and trip.user_id is not None:
            if not current_user:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Vui lòng đăng nhập để thực hiện thao tác này.",
                )
            if trip.user_id != current_user.id and current_user.role != "ADMIN":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Bạn không có quyền chỉnh sửa chuyến đi này.",
                )

        # 3. Status check: protect confirmed trips
        if trip.status == "CONFIRMED" and not allow_overwrite_confirmed:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Lịch trình của chuyến đi này đã được xác nhận (CONFIRMED). Không thể ghi đè nếu không có sự đồng ý của người dùng.",
            )

        # 4. Validate
        val_res = cls.validate_itinerary(session=session, itinerary=itinerary, context=context)
        if not val_res.is_valid:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail={"message": "Dữ liệu lịch trình không hợp lệ.", "errors": val_res.errors},
            )

        # 5. Atomic persistence inside a transaction
        try:
            # Delete previous itinerary_days for this trip (cascades to activities)
            old_days = session.exec(
                select(ItineraryDay).where(ItineraryDay.trip_id == trip.id)
            ).all()
            for od in old_days:
                session.delete(od)

            trip.itinerary_days = []
            session.flush()

            # Insert new days & activities
            for d_idx, day_item in enumerate(itinerary.days, start=1):
                day_date_obj: Optional[date] = None
                if day_item.date:
                    try:
                        day_date_obj = datetime.strptime(day_item.date, "%Y-%m-%d").date()
                    except ValueError:
                        pass

                db_day = ItineraryDay(
                    trip_id=trip.id,
                    day_number=d_idx,  # Guarantee continuous 1..N
                    date=day_date_obj,
                    title=day_item.title or f"Ngày {d_idx}",
                    description=day_item.description,
                )
                session.add(db_day)
                session.flush()

                for a_idx, act_item in enumerate(day_item.activities, start=1):
                    start_t: Optional[time] = None
                    if act_item.start_time:
                        try:
                            start_t = datetime.strptime(act_item.start_time, "%H:%M").time()
                        except ValueError:
                            pass

                    end_t: Optional[time] = None
                    if act_item.end_time:
                        try:
                            end_t = datetime.strptime(act_item.end_time, "%H:%M").time()
                        except ValueError:
                            pass

                    cost_dec: Optional[Decimal] = None
                    if act_item.estimated_cost is not None:
                        cost_dec = Decimal(str(act_item.estimated_cost))

                    dist_dec: Optional[Decimal] = None
                    if act_item.travel_distance_km is not None:
                        dist_dec = Decimal(str(act_item.travel_distance_km))

                    db_act = ItineraryActivity(
                        itinerary_day_id=db_day.id,
                        place_id=act_item.place_id,
                        activity_type=act_item.activity_type or "VISIT",
                        title=act_item.title,
                        description=act_item.description,
                        start_time=start_t,
                        end_time=end_t,
                        duration_minutes=act_item.duration_minutes,
                        estimated_cost=cost_dec,
                        travel_duration_minutes=act_item.travel_duration_minutes,
                        travel_distance_km=dist_dec,
                        order_index=a_idx,  # Guarantee continuous 1..K
                        note=act_item.note,
                    )
                    session.add(db_act)

            # Update trip title & status
            if itinerary.title and (not trip.name or trip.name.startswith("Chuyến đi")):
                trip.name = itinerary.title

            trip.status = "GENERATED"
            trip.updated_at = _utcnow()
            session.add(trip)

            session.commit()
            logger.info("Successfully persisted itinerary for trip_id=%s with %s days.", trip.id, len(itinerary.days))
        except Exception as e:
            session.rollback()
            logger.error("Failed to persist itinerary for trip_id=%s, rolled back: %s", trip.id, e)
            raise

        # Return full detailed response
        return cls.get_itinerary_by_trip_id(
            session=session,
            trip_id=trip.id,
            current_user=current_user,
            check_ownership=False,
        )

    # -------------------------------------------------------------------------
    # 3. Retrieval Layer
    # -------------------------------------------------------------------------
    @classmethod
    def get_itinerary_by_trip_id(
        cls,
        session: Session,
        trip_id: int,
        current_user: Optional[User] = None,
        check_ownership: bool = True,
    ) -> ItineraryDetailResponse:
        """Retrieves complete trip itinerary with days and activities in exact sequential order.

        Eager loads days -> activities -> place -> category in a single optimized query,
        preventing N+1 database roundtrips.
        """
        # 1. Fetch trip with eager loaded relationships
        stmt = (
            select(Trip)
            .where(Trip.id == trip_id)
            .options(
                selectinload(Trip.itinerary_days)
                .selectinload(ItineraryDay.activities)
                .selectinload(ItineraryActivity.place)
                .selectinload(Place.category)
            )
        )
        trip = session.exec(stmt).first()

        if not trip:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
            )

        # 2. Authorization check
        if check_ownership and trip.user_id is not None:
            if not current_user:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Vui lòng đăng nhập để xem chuyến đi này.",
                )
            if trip.user_id != current_user.id and current_user.role != "ADMIN":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Bạn không có quyền truy cập chuyến đi này.",
                )

        # 3. Format days & activities sorted by sequence
        sorted_days = sorted(trip.itinerary_days, key=lambda d: d.day_number)
        days_detail: List[ItineraryDayDetail] = []
        total_acts = 0
        total_cost = 0.0
        has_cost_data = False

        for db_day in sorted_days:
            sorted_acts = sorted(db_day.activities, key=lambda a: a.order_index)
            acts_detail: List[ItineraryActivityDetail] = []

            for db_act in sorted_acts:
                total_acts += 1
                place_summary: Optional[ItineraryPlaceSummary] = None
                if db_act.place and not getattr(db_act.place, "is_deleted", False):
                    cat_name = db_act.place.category.name if db_act.place.category else None
                    place_summary = ItineraryPlaceSummary(
                        place_id=db_act.place.id,
                        name=db_act.place.name,
                        category=cat_name,
                        address=db_act.place.address,
                        description=db_act.place.description,
                        latitude=db_act.place.latitude,
                        longitude=db_act.place.longitude,
                    )

                cost_float: Optional[float] = None
                if db_act.estimated_cost is not None:
                    cost_float = float(db_act.estimated_cost)
                    total_cost += cost_float
                    has_cost_data = True

                dist_float: Optional[float] = None
                if db_act.travel_distance_km is not None:
                    dist_float = float(db_act.travel_distance_km)

                start_str = db_act.start_time.strftime("%H:%M") if db_act.start_time else None
                end_str = db_act.end_time.strftime("%H:%M") if db_act.end_time else None

                acts_detail.append(
                    ItineraryActivityDetail(
                        id=db_act.id,
                        itinerary_day_id=db_day.id,
                        order_index=db_act.order_index,
                        activity_type=db_act.activity_type or "VISIT",
                        place_id=db_act.place_id,
                        place=place_summary,
                        title=db_act.title,
                        description=db_act.description,
                        start_time=start_str,
                        end_time=end_str,
                        duration_minutes=db_act.duration_minutes,
                        estimated_cost=cost_float,
                        travel_duration_minutes=db_act.travel_duration_minutes,
                        travel_distance_km=dist_float,
                        note=db_act.note,
                    )
                )

            days_detail.append(
                ItineraryDayDetail(
                    id=db_day.id,
                    trip_id=trip.id,
                    day_number=db_day.day_number,
                    date=db_day.date.isoformat() if db_day.date else None,
                    title=db_day.title,
                    description=db_day.description,
                    activities=acts_detail,
                )
            )

        duration_days = len(days_detail)
        if duration_days == 0 and trip.start_date and trip.end_date:
            duration_days = (trip.end_date - trip.start_date).days + 1

        return ItineraryDetailResponse(
            trip_id=trip.id,
            name=trip.name,
            destination=trip.destination_city,
            destination_city=trip.destination_city,
            destination_country=trip.destination_country,
            status=trip.status,
            start_date=trip.start_date.isoformat() if trip.start_date else None,
            end_date=trip.end_date.isoformat() if trip.end_date else None,
            duration_days=duration_days,
            total_activities=total_acts,
            estimated_total_cost=total_cost if has_cost_data else None,
            currency="VND",
            days=days_detail,
            created_at=trip.created_at.isoformat() if trip.created_at else None,
            updated_at=trip.updated_at.isoformat() if trip.updated_at else None,
        )

    # -------------------------------------------------------------------------
    # 4. Trip Listing Layer
    # -------------------------------------------------------------------------
    @classmethod
    def list_trips(
        cls,
        session: Session,
        current_user: Optional[User],
        skip: int = 0,
        limit: int = 20,
        status_filter: Optional[str] = None,
    ) -> TripListResponse:
        """Lists user's trips with pagination, preventing cross-user data leakage."""
        if not current_user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Vui lòng đăng nhập để xem danh sách chuyến đi.",
            )

        # Base query filter
        filter_clauses = []
        if current_user.role != "ADMIN":
            filter_clauses.append(Trip.user_id == current_user.id)

        if status_filter:
            filter_clauses.append(Trip.status == status_filter.upper())

        # Count total
        count_stmt = select(func.count(Trip.id))
        if filter_clauses:
            count_stmt = count_stmt.where(*filter_clauses)
        total = session.exec(count_stmt).one()

        # Query items with eager loaded itinerary_days to compute days_count efficiently
        items_stmt = (
            select(Trip)
            .options(selectinload(Trip.itinerary_days))
            .order_by(Trip.updated_at.desc(), Trip.created_at.desc())
            .offset(skip)
            .limit(limit)
        )
        if filter_clauses:
            items_stmt = items_stmt.where(*filter_clauses)

        trips = session.exec(items_stmt).all()

        items: List[TripSummaryItem] = []
        for t in trips:
            days_count = len(t.itinerary_days)
            if days_count == 0 and t.start_date and t.end_date:
                days_count = (t.end_date - t.start_date).days + 1

            items.append(
                TripSummaryItem(
                    id=t.id,
                    name=t.name,
                    destination_city=t.destination_city,
                    destination_country=t.destination_country,
                    status=t.status,
                    start_date=t.start_date.isoformat() if t.start_date else None,
                    end_date=t.end_date.isoformat() if t.end_date else None,
                    days_count=days_count,
                    created_at=t.created_at.isoformat() if t.created_at else None,
                    updated_at=t.updated_at.isoformat() if t.updated_at else None,
                )
            )

        return TripListResponse(
            total=total,
            skip=skip,
            limit=limit,
            items=items,
        )

    # -------------------------------------------------------------------------
    # 5. Activity CRUD
    # -------------------------------------------------------------------------
    @classmethod
    def create_activity(
        cls,
        session: Session,
        trip_id: int,
        day_id: int,
        data: ItineraryActivityCreate,
        current_user: Optional[User] = None,
        check_ownership: bool = True,
    ) -> ItineraryActivityDetail:
        """Create a new activity within an itinerary day."""
        trip, day = cls._get_trip_and_day(
            session=session,
            trip_id=trip_id,
            day_id=day_id,
            current_user=current_user,
            check_ownership=check_ownership,
            require_write=True,
        )

        if data.place_id is not None:
            cls._ensure_place_exists(session, data.place_id)

        order_index = data.order_index
        if order_index is None:
            max_order = session.exec(
                select(func.max(ItineraryActivity.order_index)).where(
                    ItineraryActivity.itinerary_day_id == day.id
                )
            ).one()
            order_index = int(max_order or 0) + 1
        else:
            cls._ensure_order_index_available(
                session=session,
                day_id=day.id,
                order_index=order_index,
            )

        start_t = cls._parse_time(data.start_time)
        end_t = cls._parse_time(data.end_time)

        activity = ItineraryActivity(
            itinerary_day_id=day.id,
            place_id=data.place_id,
            activity_type=data.activity_type or "VISIT",
            title=data.title.strip(),
            description=data.description,
            start_time=start_t,
            end_time=end_t,
            duration_minutes=data.duration_minutes,
            estimated_cost=cls._to_decimal(data.estimated_cost),
            travel_duration_minutes=data.travel_duration_minutes,
            travel_distance_km=cls._to_decimal(data.travel_distance_km),
            order_index=order_index,
            note=data.note,
        )
        session.add(activity)

        trip.updated_at = _utcnow()
        session.add(trip)

        try:
            session.commit()
        except Exception:
            session.rollback()
            raise

        session.refresh(activity)
        return cls._activity_to_detail(session, activity)

    @classmethod
    def update_activity(
        cls,
        session: Session,
        trip_id: int,
        activity_id: int,
        data: ItineraryActivityUpdate,
        current_user: Optional[User] = None,
        check_ownership: bool = True,
    ) -> ItineraryActivityDetail:
        """Partially update an existing itinerary activity."""
        trip, activity = cls._get_trip_and_activity(
            session=session,
            trip_id=trip_id,
            activity_id=activity_id,
            current_user=current_user,
            check_ownership=check_ownership,
            require_write=True,
        )

        update_dict = data.model_dump(exclude_unset=True)
        if not update_dict:
            return cls._activity_to_detail(session, activity)

        if "place_id" in update_dict and update_dict["place_id"] is not None:
            cls._ensure_place_exists(session, update_dict["place_id"])

        if "order_index" in update_dict and update_dict["order_index"] is not None:
            if update_dict["order_index"] != activity.order_index:
                cls._ensure_order_index_available(
                    session=session,
                    day_id=activity.itinerary_day_id,
                    order_index=update_dict["order_index"],
                    exclude_activity_id=activity.id,
                )

        if "title" in update_dict and update_dict["title"] is not None:
            update_dict["title"] = str(update_dict["title"]).strip()

        if "start_time" in update_dict:
            update_dict["start_time"] = cls._parse_time(update_dict["start_time"])
        if "end_time" in update_dict:
            update_dict["end_time"] = cls._parse_time(update_dict["end_time"])
        if "estimated_cost" in update_dict:
            update_dict["estimated_cost"] = cls._to_decimal(update_dict["estimated_cost"])
        if "travel_distance_km" in update_dict:
            update_dict["travel_distance_km"] = cls._to_decimal(
                update_dict["travel_distance_km"]
            )

        for field, value in update_dict.items():
            setattr(activity, field, value)

        trip.updated_at = _utcnow()
        session.add(activity)
        session.add(trip)

        try:
            session.commit()
        except Exception:
            session.rollback()
            raise

        session.refresh(activity)
        return cls._activity_to_detail(session, activity)

    # -------------------------------------------------------------------------
    # Helper methods
    # -------------------------------------------------------------------------
    @classmethod
    def _assert_trip_access(
        cls,
        trip: Trip,
        current_user: Optional[User],
        *,
        check_ownership: bool,
        require_write: bool,
    ) -> None:
        if not check_ownership or trip.user_id is None:
            return
        if not current_user:
            action = "chỉnh sửa" if require_write else "xem"
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Vui lòng đăng nhập để {action} chuyến đi này.",
            )
        if trip.user_id != current_user.id and current_user.role != "ADMIN":
            action = "chỉnh sửa" if require_write else "truy cập"
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Bạn không có quyền {action} chuyến đi này.",
            )

    @classmethod
    def _get_trip_and_day(
        cls,
        session: Session,
        trip_id: int,
        day_id: int,
        current_user: Optional[User],
        check_ownership: bool,
        require_write: bool,
    ) -> Tuple[Trip, ItineraryDay]:
        trip = session.get(Trip, trip_id)
        if not trip:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
            )
        cls._assert_trip_access(
            trip,
            current_user,
            check_ownership=check_ownership,
            require_write=require_write,
        )

        day = session.get(ItineraryDay, day_id)
        if not day or day.trip_id != trip.id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy ngày lịch trình ID {day_id} trong chuyến đi {trip_id}.",
            )
        return trip, day

    @classmethod
    def _get_trip_and_activity(
        cls,
        session: Session,
        trip_id: int,
        activity_id: int,
        current_user: Optional[User],
        check_ownership: bool,
        require_write: bool,
    ) -> Tuple[Trip, ItineraryActivity]:
        trip = session.get(Trip, trip_id)
        if not trip:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
            )
        cls._assert_trip_access(
            trip,
            current_user,
            check_ownership=check_ownership,
            require_write=require_write,
        )

        activity = session.get(ItineraryActivity, activity_id)
        if not activity:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy hoạt động với ID {activity_id}.",
            )

        day = session.get(ItineraryDay, activity.itinerary_day_id)
        if not day or day.trip_id != trip.id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Hoạt động ID {activity_id} không thuộc chuyến đi {trip_id}.",
            )
        return trip, activity

    @classmethod
    def _ensure_place_exists(cls, session: Session, place_id: int) -> Place:
        place = session.get(Place, place_id)
        if not place or getattr(place, "is_deleted", False):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy địa điểm với ID {place_id}.",
            )
        return place

    @classmethod
    def _ensure_order_index_available(
        cls,
        session: Session,
        day_id: int,
        order_index: int,
        exclude_activity_id: Optional[int] = None,
    ) -> None:
        stmt = select(ItineraryActivity).where(
            ItineraryActivity.itinerary_day_id == day_id,
            ItineraryActivity.order_index == order_index,
        )
        if exclude_activity_id is not None:
            stmt = stmt.where(ItineraryActivity.id != exclude_activity_id)
        conflict = session.exec(stmt).first()
        if conflict:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"order_index={order_index} đã được dùng bởi hoạt động "
                    f"ID {conflict.id} trong ngày này."
                ),
            )

    @classmethod
    def _parse_time(cls, time_str: Optional[str]) -> Optional[time]:
        if not time_str:
            return None
        try:
            return datetime.strptime(time_str, "%H:%M").time()
        except ValueError:
            return None

    @classmethod
    def _to_decimal(cls, value: Optional[float]) -> Optional[Decimal]:
        if value is None:
            return None
        return Decimal(str(value))

    @classmethod
    def _activity_to_detail(
        cls,
        session: Session,
        activity: ItineraryActivity,
    ) -> ItineraryActivityDetail:
        place_summary: Optional[ItineraryPlaceSummary] = None
        place = activity.place
        if place is None and activity.place_id is not None:
            stmt = (
                select(Place)
                .where(Place.id == activity.place_id)
                .options(selectinload(Place.category))
            )
            place = session.exec(stmt).first()

        if place and not getattr(place, "is_deleted", False):
            cat_name = place.category.name if place.category else None
            place_summary = ItineraryPlaceSummary(
                place_id=place.id,
                name=place.name,
                category=cat_name,
                address=place.address,
                description=place.description,
                latitude=place.latitude,
                longitude=place.longitude,
            )

        return ItineraryActivityDetail(
            id=activity.id,
            itinerary_day_id=activity.itinerary_day_id,
            order_index=activity.order_index,
            activity_type=activity.activity_type or "VISIT",
            place_id=activity.place_id,
            place=place_summary,
            title=activity.title,
            description=activity.description,
            start_time=activity.start_time.strftime("%H:%M") if activity.start_time else None,
            end_time=activity.end_time.strftime("%H:%M") if activity.end_time else None,
            duration_minutes=activity.duration_minutes,
            estimated_cost=(
                float(activity.estimated_cost) if activity.estimated_cost is not None else None
            ),
            travel_duration_minutes=activity.travel_duration_minutes,
            travel_distance_km=(
                float(activity.travel_distance_km)
                if activity.travel_distance_km is not None
                else None
            ),
            note=activity.note,
        )

    @classmethod
    def _time_to_minutes(cls, time_str: Optional[str]) -> Optional[int]:
        if not time_str:
            return None
        m = re.match(r"^(\d{1,2}):(\d{2})$", str(time_str).strip())
        if m:
            hh, mm = int(m.group(1)), int(m.group(2))
            return hh * 60 + mm
        return None

    @classmethod
    def _minutes_to_time(cls, minutes: int) -> str:
        minutes = minutes % (24 * 60)
        hh = minutes // 60
        mm = minutes % 60
        return f"{hh:02d}:{mm:02d}"

    @classmethod
    def _normalize_text(cls, text: Optional[str]) -> str:
        if not text:
            return ""
        import unicodedata
        clean = text.replace("đ", "d").replace("Đ", "D").strip().lower()
        nfkd = unicodedata.normalize("NFD", clean)
        return "".join([c for c in nfkd if not unicodedata.combining(c)])
