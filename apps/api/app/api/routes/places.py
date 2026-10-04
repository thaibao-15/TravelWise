from typing import List, Optional

from fastapi import APIRouter, Depends, Query, status
from sqlmodel import Session

from app.api.deps import get_current_user, get_session
from app.models.user import User
from app.schemas.knowledge import KnowledgeCreate, KnowledgeResponse
from app.schemas.place import PlaceCreate, PlaceDetailResponse, PlaceResponse
from app.services.knowledge_service import KnowledgeService
from app.services.place_service import PlaceService

router = APIRouter(
    prefix="/api/v1/places",
    tags=["Places"],
)


@router.get("/", response_model=List[PlaceResponse])
def list_places(
    category_id: Optional[int] = Query(default=None, description="Lọc theo category"),
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=200),
    session: Session = Depends(get_session),
) -> List[PlaceResponse]:
    """Lấy danh sách places. Hỗ trợ filter theo category_id và phân trang. Public."""
    return PlaceService.list_places(session, category_id=category_id, skip=skip, limit=limit)


@router.get("/{place_id}", response_model=PlaceDetailResponse)
def get_place(
    place_id: int,
    session: Session = Depends(get_session),
) -> PlaceDetailResponse:
    """Lấy chi tiết place theo ID (bao gồm restaurant/hotel detail, images). Public."""
    return PlaceService.get_place_by_id(session, place_id)


@router.post("/", response_model=PlaceResponse, status_code=status.HTTP_201_CREATED)
def create_place(
    data: PlaceCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> PlaceResponse:
    """Tạo place mới. Yêu cầu đăng nhập."""
    return PlaceService.create_place(session, data)


@router.get("/{place_id}/knowledge", response_model=List[KnowledgeResponse])
def get_place_knowledge(
    place_id: int,
    session: Session = Depends(get_session),
) -> List[KnowledgeResponse]:
    """Lấy danh sách knowledge articles của một place. Public."""
    return KnowledgeService.get_knowledge_by_place(session, place_id)


@router.post(
    "/{place_id}/knowledge",
    response_model=KnowledgeResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_place_knowledge(
    place_id: int,
    data: KnowledgeCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> KnowledgeResponse:
    """Tạo knowledge article cho một place. Yêu cầu đăng nhập."""
    # Ensure place_id in body matches the URL param
    data.place_id = place_id
    return KnowledgeService.create_knowledge(session, data)
