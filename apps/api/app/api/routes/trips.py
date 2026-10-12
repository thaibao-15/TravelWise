"""
Trips and Trip Planning Context API routes.
"""

from datetime import datetime
import json
import logging
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
    ItineraryDetailResponse,
    ItineraryEditRequest,
    ItineraryEditResponse,
    ItineraryGenerationRequest,
    ItineraryGenerationResponse,
    TripCreateRequest,
    TripListResponse,
    TripSummaryItem,
    TripUpdateRequest,
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
            check_ownership=False,
        )

    if not context:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cần cung cấp context hoặc conversation_id để tạo lịch trình.",
        )

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
                check_ownership=False,
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

    save_to_db = request_data.save_to_db if request_data is not None else True
    user_prompt = request_data.user_prompt if request_data is not None else None

    return ItineraryGenerationService.generate_itinerary(
        session=session,
        context=context,
        trip_id=trip.id,
        save_to_db=save_to_db,
        user_prompt=user_prompt,
    )


@router.post(
    "/api/v1/trips/{trip_id}/itinerary/edit",
    response_model=ItineraryEditResponse,
    status_code=status.HTTP_200_OK,
    summary="Edit trip itinerary with conversational change prompt",
    description="Chỉnh sửa lịch trình theo câu lệnh ngôn ngữ tự nhiên (ví dụ: đổi giờ, thêm biển, đổi đặc sản).",
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

    # 1. Retrieve context
    pref = session.exec(select(TripPreference).where(TripPreference.trip_id == trip.id)).first()
    context: Optional[TripPlanningContext] = None
    if pref and pref.raw_context_snapshot:
        try:
            data = json.loads(pref.raw_context_snapshot)
            context = TripPlanningContext.model_validate(data)
        except Exception:
            pass

    if not context and trip.conversation_id:
        context = TripPlanningContextExtractionService.get_planning_context_by_conversation(
            session=session,
            conversation_id=trip.conversation_id,
            current_user=current_user,
            check_ownership=False,
        )

    if not context:
        context = TripPlanningContext()
        context.trip.trip_id = trip.id
        context.trip.destination.city = trip.destination_city or "Đà Nẵng"
        context.trip.destination.country = trip.destination_country or "Việt Nam"

    # 2. Re-generate with user prompt
    gen_res = ItineraryGenerationService.generate_itinerary(
        session=session,
        context=context,
        trip_id=trip.id,
        save_to_db=True,
        user_prompt=request_data.change_prompt,
    )

    # 3. Retrieve fresh details
    details = ItineraryPersistenceService.get_itinerary_by_trip_id(
        session=session,
        trip_id=trip.id,
        current_user=current_user,
        check_ownership=False,
    )

    edit_summary = getattr(gen_res, "summary", None) or f"Đã tối ưu và cập nhật lại lịch trình cho chuyến đi của bạn! 🗺️✨"
    return ItineraryEditResponse(
        status=EditStatusEnum.EDITED.value,
        trip_id=trip.id,
        conversation_id=trip.conversation_id,
        message=edit_summary,
        applied_changes=[request_data.change_prompt],
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
