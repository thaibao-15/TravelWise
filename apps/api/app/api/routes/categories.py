from typing import List

from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from app.api.deps import get_current_user, get_session
from app.models.user import User
from app.schemas.category import CategoryCreate, CategoryResponse
from app.services.category_service import CategoryService

router = APIRouter(
    prefix="/api/v1/categories",
    tags=["Categories"],
)


@router.get("/", response_model=List[CategoryResponse])
def list_categories(
    session: Session = Depends(get_session),
) -> List[CategoryResponse]:
    """Lấy danh sách tất cả categories. Public endpoint."""
    return CategoryService.list_categories(session)


@router.get("/{category_id}", response_model=CategoryResponse)
def get_category(
    category_id: int,
    session: Session = Depends(get_session),
) -> CategoryResponse:
    """Lấy category theo ID. Public endpoint."""
    return CategoryService.get_category_by_id(session, category_id)


@router.post("/", response_model=CategoryResponse, status_code=status.HTTP_201_CREATED)
def create_category(
    data: CategoryCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> CategoryResponse:
    """Tạo category mới. Yêu cầu đăng nhập."""
    return CategoryService.create_category(session, data)
