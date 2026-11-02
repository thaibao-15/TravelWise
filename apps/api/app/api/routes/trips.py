"""
Trips and Trip Planning Context API routes.
"""

from datetime import datetime
import json
import logging
import re
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session, select

from app.api.deps import get_current_user_optional, get_session
from app.db.base import _utcnow
from app.models.trip import Trip
from app.models.trip_preference import TripPreference
from app.models.user import User
from app.schemas.itinerary import (
    EditStatusEnum,
    ItineraryActivityCreate,
    ItineraryActivityDetail,
    ItineraryActivityUpdate,
    ItineraryDetailResponse,
    ItineraryDetectIntentRequest,
    ItineraryDetectIntentResponse,
    ItineraryEditRequest,
    ItineraryEditResponse,
    ItineraryGenerationRequest,
    ItineraryGenerationResponse,
    ItineraryStatusEnum,
    TripCreateRequest,
    TripListResponse,
    TripSummaryItem,
    TripUpdateRequest,
    SavePreviewTripRequest,
)
from app.schemas.place_search import PlaceSearchRequest, PlaceSearchResponse
from app.schemas.trip_planning import TripPlanningContext
from app.services.itinerary_generation_service import ItineraryGenerationService
from app.services.itinerary_persistence_service import ItineraryPersistenceService
from app.services.place_search_service import PlaceSearchService
from app.services.trip_planning_service import TripPlanningContextExtractionService

logger = logging.getLogger(__name__)

router = APIRouter(
    tags=["Trips / Planning Context"],
)


# -----------------------------------------------------------------------------
# 1. Trip Planning Context
# -----------------------------------------------------------------------------
@router.get(
    "/api/v1/trips/conversations/{conversation_id}/planning-context",
    response_model=TripPlanningContext,
    status_code=status.HTTP_200_OK,
    summary="Get TripPlanningContext by conversation ID",
    description="Lấy thông tin ngữ cảnh lập kế hoạch du lịch (TripPlanningContext) hiện hành của cuộc trò chuyện.",
)
@router.get(
    "/api/trips/conversations/{conversation_id}/planning-context",
    response_model=TripPlanningContext,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def get_trip_planning_context(
    conversation_id: int,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> TripPlanningContext:
    """Retrieve the current TripPlanningContext for a conversation.

    Verifies user ownership of the conversation.
    """
    ctx = TripPlanningContextExtractionService.get_planning_context_by_conversation(
        session=session,
        conversation_id=conversation_id,
        current_user=current_user,
        check_ownership=True,
    )
    if not ctx:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Chưa có thông tin lập kế hoạch cho cuộc trò chuyện {conversation_id}.",
        )
    return ctx


# -----------------------------------------------------------------------------
# 2. Place Search for Trip
# -----------------------------------------------------------------------------
@router.post(
    "/api/v1/trips/{trip_id}/places/search",
    response_model=PlaceSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Search and rank places for trip itinerary",
    description="Tìm kiếm và xếp hạng các địa điểm thực tế từ SQL Server dựa trên TripPlanningContext của chuyến đi.",
)
@router.post(
    "/api/trips/{trip_id}/places/search",
    response_model=PlaceSearchResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def search_places_for_trip(
    trip_id: int,
    request_data: Optional[PlaceSearchRequest] = None,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> PlaceSearchResponse:
    """Search and score real places from SQL Server for itinerary generation."""
    trip = session.get(Trip, trip_id)
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
        )

    if trip.user_id is not None:
        if not current_user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Vui lòng đăng nhập để truy cập chuyến đi này.",
            )
        if trip.user_id != current_user.id and current_user.role != "ADMIN":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền truy cập chuyến đi này.",
            )

    context: Optional[TripPlanningContext] = None
    if request_data and request_data.context:
        context = request_data.context
    else:
        pref = session.exec(select(TripPreference).where(TripPreference.trip_id == trip.id)).first()
        if pref and pref.raw_context_snapshot:
            try:
                data = json.loads(pref.raw_context_snapshot)
                context = TripPlanningContext.model_validate(data)
            except Exception as e:
                logger.warning("Failed to parse raw_context_snapshot for trip %s: %s", trip.id, e)

        if not context and trip.conversation_id:
            context = TripPlanningContextExtractionService.get_planning_context_by_conversation(
                session=session,
                conversation_id=trip.conversation_id,
                current_user=current_user,
                check_ownership=False,
            )

        if not context and trip.destination_city:
            context = TripPlanningContext()
            context.trip.trip_id = trip.id
            context.trip.destination.city = trip.destination_city
            context.trip.destination.country = trip.destination_country

    if not context:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Chuyến đi {trip_id} chưa có thông tin lập kế hoạch (TripPlanningContext).",
        )

    skip = request_data.skip if request_data else 0
    limit = request_data.limit if request_data else 20

    return PlaceSearchService.search_places_for_itinerary(
        session=session,
        context=context,
        skip=skip,
        limit=limit,
    )


# -----------------------------------------------------------------------------
# 3. Trip CRUD
# -----------------------------------------------------------------------------
@router.post(
    "/api/v1/trips",
    response_model=TripSummaryItem,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new trip",
    description="Tạo chuyến đi mới từ giao diện Web, có thể đính kèm TripPlanningContext hoặc ngày tháng.",
)
@router.post(
    "/api/trips",
    response_model=TripSummaryItem,
    status_code=status.HTTP_201_CREATED,
    include_in_schema=False,
)
def create_trip(
    data: TripCreateRequest,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> TripSummaryItem:
    """Create a new Trip entity in database."""
    user_id = current_user.id if current_user else None

    s_date = None
    if data.start_date:
        try:
            s_date = datetime.strptime(data.start_date, "%Y-%m-%d").date()
        except ValueError:
            pass

    e_date = None
    if data.end_date:
        try:
            e_date = datetime.strptime(data.end_date, "%Y-%m-%d").date()
        except ValueError:
            pass

    trip = Trip(
        user_id=user_id,
        conversation_id=data.conversation_id,
        name=data.name or f"Chuyến đi {data.destination_city}",
        destination_city=data.destination_city,
        destination_country=data.destination_country or "Việt Nam",
        status="DRAFT",
        start_date=s_date,
        end_date=e_date,
    )
    session.add(trip)
    session.commit()
    session.refresh(trip)

    # Save context snapshot if provided
    if data.context:
        try:
            ctx_dict = data.context if isinstance(data.context, dict) else data.context.model_dump()
            pref = TripPreference(
                trip_id=trip.id,
                raw_context_snapshot=json.dumps(ctx_dict, ensure_ascii=False),
            )
            session.add(pref)
            session.commit()
        except Exception as e:
            logger.warning("Could not persist initial context snapshot: %s", e)

    days_count = data.duration_days or 3
    if s_date and e_date:
        days_count = max(1, (e_date - s_date).days + 1)

    return TripSummaryItem(
        id=trip.id,
        name=trip.name,
        destination_city=trip.destination_city,
        destination_country=trip.destination_country,
        status=trip.status,
        start_date=trip.start_date.isoformat() if trip.start_date else None,
        end_date=trip.end_date.isoformat() if trip.end_date else None,
        days_count=days_count,
        created_at=trip.created_at.isoformat() if trip.created_at else None,
        updated_at=trip.updated_at.isoformat() if trip.updated_at else None,
    )


@router.get(
    "/api/v1/trips",
    response_model=TripListResponse,
    status_code=status.HTTP_200_OK,
    summary="List trips for current user",
    description="Lấy danh sách các chuyến đi thuộc quyền quản lý của người dùng hiện tại (hỗ trợ phân trang và lọc theo trạng thái).",
)
@router.get(
    "/api/trips",
    response_model=TripListResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def list_trips(
    skip: int = Query(0, ge=0, description="Số lượng bản ghi bỏ qua"),
    limit: int = Query(20, ge=1, le=100, description="Số lượng bản ghi tối đa"),
    status: Optional[str] = Query(None, description="Lọc theo trạng thái chuyến đi (DRAFT, GENERATED, CONFIRMED, v.v.)"),
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> TripListResponse:
    """List trips belonging to current authenticated user."""
    return ItineraryPersistenceService.list_trips(
        session=session,
        current_user=current_user,
        skip=skip,
        limit=limit,
        status_filter=status,
    )


@router.get(
    "/api/v1/trips/{trip_id}",
    response_model=TripSummaryItem,
    status_code=status.HTTP_200_OK,
    summary="Get single trip summary",
    description="Lấy thông tin tổng quan của một chuyến đi theo ID.",
)
def get_trip(
    trip_id: int,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> TripSummaryItem:
    """Get single trip overview."""
    trip = session.get(Trip, trip_id)
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
        )

    if trip.user_id is not None:
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

    days_count = len(trip.itinerary_days) if trip.itinerary_days else 3
    if trip.start_date and trip.end_date:
        days_count = max(1, (trip.end_date - trip.start_date).days + 1)

    return TripSummaryItem(
        id=trip.id,
        name=trip.name,
        destination_city=trip.destination_city,
        destination_country=trip.destination_country,
        status=trip.status,
        start_date=trip.start_date.isoformat() if trip.start_date else None,
        end_date=trip.end_date.isoformat() if trip.end_date else None,
        days_count=days_count,
        created_at=trip.created_at.isoformat() if trip.created_at else None,
        updated_at=trip.updated_at.isoformat() if trip.updated_at else None,
    )


@router.patch(
    "/api/v1/trips/{trip_id}",
    response_model=TripSummaryItem,
    status_code=status.HTTP_200_OK,
    summary="Update trip metadata",
    description="Cập nhật tên, trạng thái (CONFIRMED, DRAFT) hoặc ngày tháng chuyến đi.",
)
def update_trip(
    trip_id: int,
    data: TripUpdateRequest,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> TripSummaryItem:
    """Update trip fields."""
    trip = session.get(Trip, trip_id)
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
        )

    if trip.user_id is not None:
        if not current_user:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
        if trip.user_id != current_user.id and current_user.role != "ADMIN":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN)

    if data.name is not None:
        trip.name = data.name
    if data.status is not None:
        trip.status = data.status.upper()
    if data.destination_city is not None:
        trip.destination_city = data.destination_city
    if data.destination_country is not None:
        trip.destination_country = data.destination_country
    if data.start_date is not None:
        try:
            trip.start_date = datetime.strptime(data.start_date, "%Y-%m-%d").date()
        except ValueError:
            pass
    if data.end_date is not None:
        try:
            trip.end_date = datetime.strptime(data.end_date, "%Y-%m-%d").date()
        except ValueError:
            pass

    trip.updated_at = _utcnow()
    session.add(trip)
    session.commit()
    session.refresh(trip)

    days_count = len(trip.itinerary_days) if trip.itinerary_days else 3
    return TripSummaryItem(
        id=trip.id,
        name=trip.name,
        destination_city=trip.destination_city,
        destination_country=trip.destination_country,
        status=trip.status,
        start_date=trip.start_date.isoformat() if trip.start_date else None,
        end_date=trip.end_date.isoformat() if trip.end_date else None,
        days_count=days_count,
        created_at=trip.created_at.isoformat() if trip.created_at else None,
        updated_at=trip.updated_at.isoformat() if trip.updated_at else None,
    )


@router.delete(
    "/api/v1/trips/{trip_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a trip",
    description="Xóa hoàn toàn chuyến đi cùng toàn bộ lịch trình các ngày và hoạt động (cascade).",
)
def delete_trip(
    trip_id: int,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """Delete trip and its cascade entities."""
    trip = session.get(Trip, trip_id)
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
        )

    if trip.user_id is not None:
        if not current_user:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
        if trip.user_id != current_user.id and current_user.role != "ADMIN":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN)

    session.delete(trip)
    session.commit()
    return None


# -----------------------------------------------------------------------------
# 4. Itinerary Generation & Editing
# -----------------------------------------------------------------------------
@router.post(
    "/api/v1/trips/generate",
    response_model=ItineraryGenerationResponse,
    status_code=status.HTTP_200_OK,
    summary="Direct generate itinerary from context or conversation",
    description="Tạo lịch trình du lịch ngay từ TripPlanningContext mà không cần tạo Trip trước.",
)
@router.post(
    "/api/trips/generate",
    response_model=ItineraryGenerationResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def generate_itinerary_direct(
    request_data: ItineraryGenerationRequest,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> ItineraryGenerationResponse:
    """Generate itinerary directly without pre-existing trip ID."""
    context: Optional[TripPlanningContext] = None
    if request_data.context:
        if isinstance(request_data.context, dict):
            context = TripPlanningContext.model_validate(request_data.context)
        elif isinstance(request_data.context, TripPlanningContext):
            context = request_data.context

    if not context and request_data.conversation_id:
        context = TripPlanningContextExtractionService.get_planning_context_by_conversation(
            session=session,
            conversation_id=request_data.conversation_id,
            current_user=current_user,
            check_ownership=True if current_user else False,
        )

    if not context:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cần cung cấp context hoặc conversation_id để tạo lịch trình.",
        )

    if request_data and request_data.current_location:
        context.current_location = request_data.current_location

    # Automatically create Trip in SQL Server if save_to_db is True
    target_trip_id = context.trip.trip_id
    if not target_trip_id and request_data.save_to_db:
        dest_city = context.trip.destination.city or "Việt Nam"
        trip = Trip(
            user_id=current_user.id if current_user else None,
            conversation_id=request_data.conversation_id,
            name=f"Lịch trình khám phá {dest_city}",
            destination_city=dest_city,
            destination_country=context.trip.destination.country or "Việt Nam",
            status="DRAFT",
        )
        session.add(trip)
        session.commit()
        session.refresh(trip)
        target_trip_id = trip.id
        context.trip.trip_id = trip.id

    return ItineraryGenerationService.generate_itinerary(
        session=session,
        context=context,
        trip_id=target_trip_id,
        save_to_db=request_data.save_to_db,
        user_prompt=request_data.user_prompt,
    )


@router.post(
    "/api/v1/trips/save-preview",
    response_model=ItineraryDetailResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Save a reviewed itinerary preview to SQL Server",
    description="Lưu chính xác bản xem trước lịch trình đã duyệt vào cơ sở dữ liệu SQL Server, liên kết với người dùng và cuộc trò chuyện.",
)
@router.post(
    "/api/trips/save-preview",
    response_model=ItineraryDetailResponse,
    status_code=status.HTTP_201_CREATED,
    include_in_schema=False,
)
def save_trip_preview(
    data: SavePreviewTripRequest,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> ItineraryDetailResponse:
    """Atomically and idempotently save a reviewed itinerary preview to SQL Server."""
    target_trip: Optional[Trip] = None

    # 0. Idempotency check: if matching idempotency_key was already saved by this user
    if data.idempotency_key and current_user:
        pref = session.exec(
            select(TripPreference)
            .join(Trip, Trip.id == TripPreference.trip_id)
            .where(
                Trip.user_id == current_user.id,
                TripPreference.raw_context_snapshot.contains(data.idempotency_key),
            )
        ).first()
        if pref and pref.trip_id:
            existing_trip = session.get(Trip, pref.trip_id)
            if existing_trip and existing_trip.status == "CONFIRMED":
                return ItineraryPersistenceService.get_itinerary_by_trip_id(
                    session=session,
                    trip_id=existing_trip.id,
                    current_user=current_user,
                    check_ownership=True,
                )

    # 1. Resolve existing trip if trip_id provided
    if data.trip_id:
        target_trip = session.get(Trip, data.trip_id)
        if target_trip and target_trip.user_id is not None and current_user:
            if target_trip.user_id != current_user.id and current_user.role != "ADMIN":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Bạn không có quyền chỉnh sửa chuyến đi này.",
                )
        # Idempotency check: if already confirmed and has activities, return existing
        if target_trip and target_trip.status == "CONFIRMED" and target_trip.itinerary_days:
            return ItineraryPersistenceService.get_itinerary_by_trip_id(
                session=session,
                trip_id=target_trip.id,
                current_user=current_user,
                check_ownership=True if current_user else False,
            )

    # 2. Check draft trip by conversation_id if available
    if not target_trip and data.conversation_id:
        draft_stmt = (
            select(Trip)
            .where(Trip.conversation_id == data.conversation_id, Trip.status == "DRAFT")
            .order_by(Trip.updated_at.desc() if Trip.updated_at is not None else Trip.created_at.desc())
        )
        target_trip = session.exec(draft_stmt).first()

    # 3. If no trip entity exists yet, create one
    if not target_trip:
        dest_city = data.destination_city or (data.preview.title or "Việt Nam")
        trip_name = data.name or data.preview.title or f"Chuyến đi {dest_city}"

        start_date_obj = None
        end_date_obj = None
        if data.preview.days and data.preview.days[0].date:
            try:
                start_date_obj = datetime.strptime(data.preview.days[0].date, "%Y-%m-%d").date()
                if data.preview.days[-1].date:
                    end_date_obj = datetime.strptime(data.preview.days[-1].date, "%Y-%m-%d").date()
            except ValueError:
                pass

        now = _utcnow()
        target_trip = Trip(
            user_id=current_user.id if current_user else None,
            conversation_id=data.conversation_id,
            name=trip_name,
            destination_city=dest_city,
            destination_country=data.destination_country or "Việt Nam",
            status="DRAFT",
            start_date=start_date_obj,
            end_date=end_date_obj,
            created_at=now,
            updated_at=now,
        )
        session.add(target_trip)
        session.commit()
        session.refresh(target_trip)
    else:
        # Link user if previously anonymous and user is now authenticated
        if current_user and target_trip.user_id is None:
            target_trip.user_id = current_user.id
            session.add(target_trip)
            session.commit()

    # 4. Save exact reviewed itinerary into SQL Server
    ItineraryPersistenceService.save_itinerary(
        session=session,
        trip_id=target_trip.id,
        itinerary=data.preview,
        current_user=current_user,
        allow_overwrite_confirmed=True,
        check_ownership=True if current_user else False,
    )

    # 5. Mark trip as CONFIRMED
    target_trip.status = "CONFIRMED"
    target_trip.updated_at = _utcnow()
    session.add(target_trip)
    session.commit()
    session.refresh(target_trip)

    # 6. Save idempotency key snapshot if provided
    if data.idempotency_key:
        pref = session.exec(
            select(TripPreference).where(TripPreference.trip_id == target_trip.id)
        ).first()
        if not pref:
            pref = TripPreference(trip_id=target_trip.id)
        snapshot = {}
        if pref.raw_context_snapshot:
            try:
                snapshot = json.loads(pref.raw_context_snapshot)
            except Exception:
                snapshot = {}
        snapshot["idempotency_key"] = data.idempotency_key
        pref.raw_context_snapshot = json.dumps(snapshot, ensure_ascii=False)
        session.add(pref)
        session.commit()

    return ItineraryPersistenceService.get_itinerary_by_trip_id(
        session=session,
        trip_id=target_trip.id,
        current_user=current_user,
        check_ownership=True if current_user else False,
    )


@router.post(
    "/api/v1/trips/{trip_id}/itinerary/generate",
    response_model=ItineraryGenerationResponse,
    status_code=status.HTTP_200_OK,
    summary="Generate multi-day travel itinerary using AI",
    description="Tạo hoặc tái tạo lịch trình du lịch nhiều ngày chi tiết dựa trên TripPlanningContext và các địa điểm thực tế.",
)
@router.post(
    "/api/trips/{trip_id}/itinerary/generate",
    response_model=ItineraryGenerationResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def generate_itinerary_for_trip(
    trip_id: int,
    request_data: Optional[ItineraryGenerationRequest] = None,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> ItineraryGenerationResponse:
    """Generate, validate and persist an AI-crafted multi-day travel itinerary."""
    trip = session.get(Trip, trip_id)
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
        )

    if trip.user_id is not None:
        if not current_user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Vui lòng đăng nhập để truy cập chuyến đi này.",
            )
        if trip.user_id != current_user.id and current_user.role != "ADMIN":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền truy cập chuyến đi này.",
            )

    context: Optional[TripPlanningContext] = None
    if request_data and request_data.context:
        if isinstance(request_data.context, dict):
            context = TripPlanningContext.model_validate(request_data.context)
        elif isinstance(request_data.context, TripPlanningContext):
            context = request_data.context

    if not context:
        pref = session.exec(select(TripPreference).where(TripPreference.trip_id == trip.id)).first()
        if pref and pref.raw_context_snapshot:
            try:
                data = json.loads(pref.raw_context_snapshot)
                context = TripPlanningContext.model_validate(data)
            except Exception as e:
                logger.warning("Failed to parse raw_context_snapshot for trip %s: %s", trip.id, e)

        if not context and trip.conversation_id:
            context = TripPlanningContextExtractionService.get_planning_context_by_conversation(
                session=session,
                conversation_id=trip.conversation_id,
                current_user=current_user,
                check_ownership=True if current_user else False,
            )

        if not context and trip.destination_city:
            context = TripPlanningContext()
            context.trip.trip_id = trip.id
            context.trip.destination.city = trip.destination_city
            context.trip.destination.country = trip.destination_country
            if trip.start_date:
                context.trip.dates.start_date = trip.start_date.isoformat()
            if trip.end_date:
                context.trip.dates.end_date = trip.end_date.isoformat()
            if trip.start_date and trip.end_date:
                context.trip.dates.duration_days = (trip.end_date - trip.start_date).days + 1

    if not context:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Chuyến đi {trip_id} chưa có thông tin lập kế hoạch (TripPlanningContext).",
        )

    # Hydrate missing destination / duration from Trip entity so generation does not fail unnecessarily
    if not context.trip.trip_id:
        context.trip.trip_id = trip.id
    if not context.trip.destination.city and trip.destination_city:
        context.trip.destination.city = trip.destination_city
    if not context.trip.destination.country and trip.destination_country:
        context.trip.destination.country = trip.destination_country
    if not context.trip.dates.start_date and trip.start_date:
        context.trip.dates.start_date = trip.start_date.isoformat()
    if not context.trip.dates.end_date and trip.end_date:
        context.trip.dates.end_date = trip.end_date.isoformat()
    if (not context.trip.dates.duration_days or context.trip.dates.duration_days <= 0):
        if trip.start_date and trip.end_date:
            context.trip.dates.duration_days = max(1, (trip.end_date - trip.start_date).days + 1)
        elif trip.itinerary_days:
            context.trip.dates.duration_days = len(trip.itinerary_days)

    if request_data and request_data.current_location:
        context.current_location = request_data.current_location

    save_to_db = request_data.save_to_db if request_data is not None else True
    allow_overwrite = request_data.allow_overwrite_confirmed if request_data is not None else False
    user_prompt = request_data.user_prompt if request_data is not None else None

    try:
        return ItineraryGenerationService.generate_itinerary(
            session=session,
            context=context,
            trip_id=trip.id,
            save_to_db=save_to_db,
            user_prompt=user_prompt,
            allow_overwrite_confirmed=allow_overwrite,
        )
    except HTTPException:
        raise
    except Exception as gen_err:
        logger.exception("Unhandled error in generate_itinerary_for_trip(%s): %s", trip_id, gen_err)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Không thể tạo lịch trình cho chuyến đi {trip_id}: {gen_err}",
        ) from gen_err


@router.post(
    "/api/v1/trips/{trip_id}/itinerary/detect-intent",
    response_model=ItineraryDetectIntentResponse,
    status_code=status.HTTP_200_OK,
    summary="Detect if user message is an itinerary edit request",
    description="Sử dụng LLM và ngữ cảnh lịch trình thực tế để xác định xem câu nói của người dùng có phải yêu cầu chỉnh sửa lịch trình hay không.",
)
@router.post(
    "/api/trips/{trip_id}/itinerary/detect-intent",
    response_model=ItineraryDetectIntentResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def detect_itinerary_edit_intent(
    trip_id: int,
    request_data: ItineraryDetectIntentRequest,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> ItineraryDetectIntentResponse:
    """Classify user intent using LLM and current itinerary context."""
    trip = session.get(Trip, trip_id)
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
        )

    if trip.user_id is not None:
        if not current_user:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
        if trip.user_id != current_user.id and current_user.role != "ADMIN":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN)

    res = ItineraryGenerationService.detect_edit_intent(
        session=session,
        trip_id=trip.id,
        message=request_data.message,
        conversation_id=request_data.conversation_id or trip.conversation_id,
        current_user=current_user,
    )

    return ItineraryDetectIntentResponse(
        is_edit_intent=res["is_edit_intent"],
        confidence=res.get("confidence", "HIGH"),
        change_prompt=res.get("change_prompt"),
        reason=res.get("reason"),
    )


@router.post(
    "/api/v1/trips/{trip_id}/itinerary/edit",
    response_model=ItineraryEditResponse,
    status_code=status.HTTP_200_OK,
    summary="Edit trip itinerary with conversational change prompt",
    description="Chỉnh sửa lịch trình theo câu lệnh ngôn ngữ tự nhiên (ví dụ: đổi giờ, thêm biển, đổi đặc sản). Tự động phân loại ý định qua LLM.",
)
@router.post(
    "/api/trips/{trip_id}/itinerary/edit",
    response_model=ItineraryEditResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def edit_itinerary_for_trip(
    trip_id: int,
    request_data: ItineraryEditRequest,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> ItineraryEditResponse:
    """Conversational edit of an existing itinerary."""
    trip = session.get(Trip, trip_id)
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
        )

    if trip.user_id is not None:
        if not current_user:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
        if trip.user_id != current_user.id and current_user.role != "ADMIN":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN)

    was_confirmed = (trip.status == "CONFIRMED")

    # 0. Lấy chi tiết lịch trình hiện tại trước để phục vụ nhận diện ngữ cảnh và bảo toàn dữ liệu
    current_details: Optional[ItineraryDetailResponse] = None
    try:
        current_details = ItineraryPersistenceService.get_itinerary_by_trip_id(
            session=session,
            trip_id=trip.id,
            current_user=current_user,
            check_ownership=True if current_user else False,
        )
    except Exception as cur_err:
        logger.warning("Could not fetch current itinerary before edit for trip %s: %s", trip.id, cur_err)

    # 1. Tự động xác định bằng LLM và RAG xem prompt có phải yêu cầu chỉnh sửa hay không
    intent_check = ItineraryGenerationService.detect_edit_intent(
        session=session,
        trip_id=trip.id,
        message=request_data.change_prompt,
        conversation_id=trip.conversation_id,
        current_user=current_user,
    )

    # 2. Retrieve & hydrate planning context
    pref = session.exec(select(TripPreference).where(TripPreference.trip_id == trip.id)).first()
    context: Optional[TripPlanningContext] = None
    if pref and pref.raw_context_snapshot:
        try:
            data = json.loads(pref.raw_context_snapshot)
            if isinstance(data, dict) and isinstance(data.get("trip"), dict):
                context = TripPlanningContext.model_validate(data)
        except Exception:
            pass

    if not context and trip.conversation_id:
        try:
            context = TripPlanningContextExtractionService.get_planning_context_by_conversation(
                session=session,
                conversation_id=trip.conversation_id,
                current_user=current_user,
                check_ownership=True if current_user else False,
            )
        except Exception as ctx_err:
            logger.warning("Could not load conversation planning context for trip %s: %s", trip.id, ctx_err)

    if not context:
        context = TripPlanningContext()

    # Đảm bảo đầy đủ thông tin bắt buộc (destination, duration_days, dates) từ Trip & lịch trình hiện tại
    context.trip.trip_id = trip.id
    if not context.trip.destination.city:
        context.trip.destination.city = (
            trip.destination_city
            or (current_details.destination_city if current_details else None)
            or "Đà Nẵng"
        )
    if not context.trip.destination.country:
        context.trip.destination.country = (
            trip.destination_country
            or (current_details.destination_country if current_details else None)
            or "Việt Nam"
        )
    if not context.trip.dates.start_date and trip.start_date:
        context.trip.dates.start_date = trip.start_date.isoformat()
    if not context.trip.dates.end_date and trip.end_date:
        context.trip.dates.end_date = trip.end_date.isoformat()

    # Kiểm tra nếu người dùng yêu cầu đổi tổng số ngày (VD: "rút gọn còn 2 ngày", "kéo dài thành 4 ngày")
    prompt_lower = (request_data.change_prompt or "").lower()
    explicit_days_match = re.search(
        r"(?:rút\s*gọn\s*(?:còn|xuống|thành)?|kéo\s*dài\s*(?:lên|thành)?|đổi\s*(?:lịch\s*trình\s*)?(?:thành|sang)|chuyển\s*(?:thành|sang)|tăng\s*lên|giảm\s*(?:còn|xuống))\s*(\d+)\s*ngày",
        prompt_lower,
    )
    if explicit_days_match:
        try:
            new_days = int(explicit_days_match.group(1))
            if 1 <= new_days <= 14:
                context.trip.dates.duration_days = new_days
                context.trip.dates.end_date = None
        except ValueError:
            pass

    if not context.trip.dates.duration_days or context.trip.dates.duration_days <= 0:
        if current_details and current_details.days:
            context.trip.dates.duration_days = len(current_details.days)
        elif trip.start_date and trip.end_date:
            context.trip.dates.duration_days = max(1, (trip.end_date - trip.start_date).days + 1)
        else:
            context.trip.dates.duration_days = 3

    # Xử lý trường hợp HOÀN TÁC / QUAY LẠI LỊCH CŨ (is_undo = true)
    if intent_check.get("is_undo"):
        backup_data = None
        if pref and pref.special_requirements:
            try:
                stored = json.loads(pref.special_requirements)
                if isinstance(stored, dict) and "backup_itinerary" in stored:
                    backup_data = stored["backup_itinerary"]
            except Exception:
                pass

        if backup_data:
            try:
                backup_itin = ItineraryGenerationResponse.model_validate(backup_data)
                ItineraryPersistenceService.save_itinerary(
                    session=session,
                    trip_id=trip.id,
                    itinerary=backup_itin,
                    current_user=current_user,
                    allow_overwrite_confirmed=request_data.allow_overwrite,
                    check_ownership=True if current_user else False,
                    context=context,
                )
                if was_confirmed:
                    trip_ref = session.get(Trip, trip.id)
                    if trip_ref:
                        trip_ref.status = "CONFIRMED"
                        trip_ref.updated_at = _utcnow()
                        session.add(trip_ref)
                        session.commit()
                restored_details = ItineraryPersistenceService.get_itinerary_by_trip_id(
                    session=session,
                    trip_id=trip.id,
                    current_user=current_user,
                    check_ownership=True if current_user else False,
                )
                return ItineraryEditResponse(
                    status=EditStatusEnum.EDITED.value,
                    trip_id=trip.id,
                    conversation_id=trip.conversation_id,
                    message="Dạ được chứ! Mình đã khôi phục lại lịch trình trước khi chỉnh sửa cho bạn rồi nhé. Mọi kế hoạch đã trở về nguyên vẹn như ban đầu rồi nè!",
                    applied_changes=["Hoàn tác về phiên bản trước"],
                    itinerary=restored_details,
                    warnings=[],
                )
            except Exception as undo_err:
                logger.warning("Undo itinerary restore failed: %s", undo_err)

    # Nếu LLM xác định KHÔNG PHẢI là yêu cầu chỉnh sửa (ví dụ hỏi FAQ, thời tiết, giá vé...)
    if not intent_check.get("is_edit_intent"):
        rag_msg = intent_check.get("reason") or "Lịch trình hiện tại vẫn được giữ nguyên."
        try:
            from app.rag.chain import get_rag_chain

            chain = get_rag_chain()
            rag_res = chain.invoke(
                question=request_data.change_prompt,
                mode="chat",
            )
            if rag_res and rag_res.get("answer"):
                rag_msg = rag_res["answer"]
        except Exception as rag_err:
            logger.warning("RAG answer fallback in edit endpoint: %s", rag_err)

        return ItineraryEditResponse(
            status=EditStatusEnum.ANSWERED.value,
            trip_id=trip.id,
            conversation_id=trip.conversation_id,
            message=rag_msg,
            applied_changes=[],
            itinerary=current_details,
            warnings=[],
        )

    effective_prompt = intent_check.get("change_prompt") or request_data.change_prompt
    if request_data.target_day and f"ngày {request_data.target_day}" not in effective_prompt.lower():
        effective_prompt = f"[Áp dụng cho Ngày {request_data.target_day}] {effective_prompt}"

    # Lưu snapshot backup trước khi chỉnh sửa (tự tạo TripPreference nếu chưa có)
    if current_details and current_details.days:
        try:
            if not pref:
                pref = TripPreference(trip_id=trip.id)
            existing_special = {}
            if pref.special_requirements:
                try:
                    parsed_sp = json.loads(pref.special_requirements)
                    if isinstance(parsed_sp, dict):
                        existing_special = parsed_sp
                except Exception:
                    existing_special = {}
            existing_special["backup_itinerary"] = current_details.model_dump(mode="json")
            pref.special_requirements = json.dumps(existing_special, ensure_ascii=False)
            session.add(pref)
            session.commit()
        except Exception as snap_err:
            session.rollback()
            logger.warning("Could not snapshot backup itinerary: %s", snap_err)

    # 3. Re-generate with validated user prompt, existing itinerary context, and overwrite permission
    gen_res = ItineraryGenerationService.generate_itinerary(
        session=session,
        context=context,
        trip_id=trip.id,
        save_to_db=True,
        user_prompt=effective_prompt,
        existing_itinerary=current_details,
        allow_overwrite_confirmed=request_data.allow_overwrite,
    )

    # 4. Kiểm tra kết quả tạo và lưu DB thực tế (không báo thành công giả nếu thất bại)
    db_persist_failed = any(
        "gặp lỗi khi lưu vào cơ sở dữ liệu" in w for w in (gen_res.warnings or [])
    )
    if (
        gen_res.status != ItineraryStatusEnum.GENERATED.value
        or not gen_res.days
        or db_persist_failed
    ):
        err_reasons = list(gen_res.warnings or []) + list(gen_res.missing_information or [])
        fail_msg = (
            err_reasons[0]
            if err_reasons
            else "Chưa thể cập nhật lịch trình theo yêu cầu này. Bạn vui lòng nói rõ hơn thay đổi mong muốn nhé!"
        )
        return ItineraryEditResponse(
            status=(
                EditStatusEnum.NEED_CLARIFICATION.value
                if gen_res.status == ItineraryStatusEnum.NEED_MORE_INFORMATION.value
                else EditStatusEnum.FAILED.value
            ),
            trip_id=trip.id,
            conversation_id=trip.conversation_id,
            message=fail_msg,
            applied_changes=[],
            itinerary=current_details,
            warnings=gen_res.warnings,
        )

    # Bảo toàn trạng thái CONFIRMED nếu chuyến đi đã được người dùng lưu trước khi sửa
    if was_confirmed:
        try:
            trip_after = session.get(Trip, trip.id)
            if trip_after and trip_after.status != "CONFIRMED":
                trip_after.status = "CONFIRMED"
                trip_after.updated_at = _utcnow()
                session.add(trip_after)
                session.commit()
        except Exception as status_err:
            logger.warning("Could not restore CONFIRMED status after edit: %s", status_err)

    # 5. Retrieve fresh persisted details from SQL Server
    details = ItineraryPersistenceService.get_itinerary_by_trip_id(
        session=session,
        trip_id=trip.id,
        current_user=current_user,
        check_ownership=True if current_user else False,
    )

    edit_summary = getattr(gen_res, "summary", None) or "Đã tối ưu và cập nhật lại lịch trình cho chuyến đi của bạn!"
    return ItineraryEditResponse(
        status=EditStatusEnum.EDITED.value,
        trip_id=trip.id,
        conversation_id=trip.conversation_id,
        message=edit_summary,
        applied_changes=[effective_prompt],
        itinerary=details,
        warnings=gen_res.warnings,
    )


@router.get(
    "/api/v1/trips/{trip_id}/itinerary",
    response_model=ItineraryDetailResponse,
    status_code=status.HTTP_200_OK,
    summary="Get detailed trip itinerary",
    description="Lấy chi tiết toàn bộ lịch trình chuyến đi (các ngày và hoạt động theo đúng thứ tự, thông tin địa điểm chi tiết).",
)
@router.get(
    "/api/trips/{trip_id}/itinerary",
    response_model=ItineraryDetailResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def get_trip_itinerary(
    trip_id: int,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> ItineraryDetailResponse:
    """Retrieve full detailed itinerary for a trip with eager loaded place information."""
    return ItineraryPersistenceService.get_itinerary_by_trip_id(
        session=session,
        trip_id=trip_id,
        current_user=current_user,
        check_ownership=True,
    )


# -----------------------------------------------------------------------------
# Itinerary Activity CRUD
# -----------------------------------------------------------------------------
@router.post(
    "/api/v1/trips/{trip_id}/itinerary/days/{day_id}/activities",
    response_model=ItineraryActivityDetail,
    status_code=status.HTTP_201_CREATED,
    summary="Create itinerary activity",
    description=(
        "Tạo hoạt động mới trong một ngày của lịch trình. "
        "Nếu không gửi order_index, hệ thống tự gán (max + 1)."
    ),
)
@router.post(
    "/api/trips/{trip_id}/itinerary/days/{day_id}/activities",
    response_model=ItineraryActivityDetail,
    status_code=status.HTTP_201_CREATED,
    include_in_schema=False,
)
def create_itinerary_activity(
    trip_id: int,
    day_id: int,
    data: ItineraryActivityCreate,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> ItineraryActivityDetail:
    """Create a new activity inside an itinerary day."""
    return ItineraryPersistenceService.create_activity(
        session=session,
        trip_id=trip_id,
        day_id=day_id,
        data=data,
        current_user=current_user,
        check_ownership=True,
    )


@router.patch(
    "/api/v1/trips/{trip_id}/itinerary/activities/{activity_id}",
    response_model=ItineraryActivityDetail,
    status_code=status.HTTP_200_OK,
    summary="Update itinerary activity",
    description="Cập nhật một phần thông tin hoạt động trong lịch trình (partial update).",
)
@router.patch(
    "/api/trips/{trip_id}/itinerary/activities/{activity_id}",
    response_model=ItineraryActivityDetail,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def update_itinerary_activity(
    trip_id: int,
    activity_id: int,
    data: ItineraryActivityUpdate,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> ItineraryActivityDetail:
    """Partially update an existing itinerary activity."""
    return ItineraryPersistenceService.update_activity(
        session=session,
        trip_id=trip_id,
        activity_id=activity_id,
        data=data,
        current_user=current_user,
        check_ownership=True,
    )
