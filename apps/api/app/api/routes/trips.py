"""
Trips and Trip Planning Context API routes.
"""

import json
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session, select

from app.api.deps import get_current_user_optional, get_session
from app.models.trip import Trip
from app.models.trip_preference import TripPreference
from app.models.user import User
from app.schemas.itinerary import (
    ItineraryDetailResponse,
    ItineraryGenerationRequest,
    ItineraryGenerationResponse,
    TripListResponse,
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
    """Search and score real places from SQL Server for itinerary generation.

    Flow:
    1. Verify trip existence.
    2. Enforce user authorization / trip ownership.
    3. Retrieve TripPlanningContext (from request payload or stored trip preferences).
    4. Execute PlaceSearchService filtering and ranking.
    """
    # 1. Fetch trip
    trip = session.get(Trip, trip_id)
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
        )

    # 2. Check ownership
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

    # 3. Retrieve context
    context: Optional[TripPlanningContext] = None
    if request_data and request_data.context:
        context = request_data.context
    else:
        # Load from trip_preferences
        pref = session.exec(select(TripPreference).where(TripPreference.trip_id == trip.id)).first()
        if pref and pref.raw_context_snapshot:
            try:
                data = json.loads(pref.raw_context_snapshot)
                context = TripPlanningContext.model_validate(data)
            except Exception as e:
                logger.warning("Failed to parse raw_context_snapshot for trip %s: %s", trip.id, e)

        # Fallback to conversation context
        if not context and trip.conversation_id:
            context = TripPlanningContextExtractionService.get_planning_context_by_conversation(
                session=session,
                conversation_id=trip.conversation_id,
                current_user=current_user,
                check_ownership=False,
            )

        # Fallback to basic reconstruction if destination is present on trip
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


@router.post(
    "/api/v1/trips/{trip_id}/itinerary/generate",
    response_model=ItineraryGenerationResponse,
    status_code=status.HTTP_200_OK,
    summary="Generate multi-day travel itinerary using AI",
    description="Tạo lịch trình du lịch nhiều ngày chi tiết dựa trên TripPlanningContext và các địa điểm thực tế từ cơ sở dữ liệu.",
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
    """Generate, validate and persist an AI-crafted multi-day travel itinerary.

    Flow:
    1. Authenticate user and verify trip access.
    2. Load or reconstruct TripPlanningContext.
    3. Generate itinerary using ItineraryGenerationService with real places.
    4. Validate domain rules and constraints.
    5. Persist to SQL Server (itinerary_days and itinerary_activities).
    6. Return structured response.
    """
    # 1. Fetch trip
    trip = session.get(Trip, trip_id)
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Không tìm thấy chuyến đi với ID {trip_id}.",
        )

    # 2. Check ownership
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

    # 3. Retrieve context
    context: Optional[TripPlanningContext] = None
    if request_data and request_data.context:
        if isinstance(request_data.context, dict):
            context = TripPlanningContext.model_validate(request_data.context)
        elif isinstance(request_data.context, TripPlanningContext):
            context = request_data.context

    if not context:
        # Load from trip_preferences
        pref = session.exec(select(TripPreference).where(TripPreference.trip_id == trip.id)).first()
        if pref and pref.raw_context_snapshot:
            try:
                data = json.loads(pref.raw_context_snapshot)
                context = TripPlanningContext.model_validate(data)
            except Exception as e:
                logger.warning("Failed to parse raw_context_snapshot for trip %s: %s", trip.id, e)

        # Fallback to conversation context
        if not context and trip.conversation_id:
            context = TripPlanningContextExtractionService.get_planning_context_by_conversation(
                session=session,
                conversation_id=trip.conversation_id,
                current_user=current_user,
                check_ownership=False,
            )

        # Fallback to basic reconstruction from trip row
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

    return ItineraryGenerationService.generate_itinerary(
        session=session,
        context=context,
        trip_id=trip.id,
        save_to_db=save_to_db,
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
