from typing import List
from fastapi import APIRouter, Depends, status
from sqlmodel import Session, select

from app.api.deps import get_current_user, get_session
from app.models.user import User
from app.schemas.user import UpdateUserRequest, UserResponse
from app.services.user_service import UserService

router = APIRouter(
    prefix="/api/v1/users",
    tags=["Users"],
)


@router.get("/", response_model=List[UserResponse])
def get_users(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> List[User]:
    """Lấy danh sách tất cả users. Yêu cầu đăng nhập."""
    users = session.exec(select(User)).all()
    return list(users)


@router.get("/{user_id}", response_model=UserResponse)
def get_user(
    user_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> User:
    """Lấy thông tin một user theo ID. Yêu cầu đăng nhập."""
    return UserService.get_user_by_id(session, user_id)


@router.patch("/{user_id}", response_model=UserResponse)
def update_user(
    user_id: int,
    update_data: UpdateUserRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> User:
    """Cập nhật thông tin user (partial update).
    - User chỉ được cập nhật thông tin của chính mình.
    - ADMIN có thể cập nhật bất kỳ user nào.
    """
    return UserService.update_user(session, user_id, update_data, current_user)


@router.delete(
    "/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_user(
    user_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> None:
    """Xóa user theo ID.
    - User chỉ được xóa tài khoản của chính mình.
    - ADMIN có thể xóa bất kỳ user nào.
    """
    UserService.delete_user(session, user_id, current_user)