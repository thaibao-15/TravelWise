from fastapi import HTTPException, status
from sqlmodel import Session

from app.db.base import _utcnow
from app.models.user import User
from app.schemas.user import UpdateUserRequest


class UserService:
    @staticmethod
    def get_user_by_id(session: Session, user_id: int) -> User:
        user = session.get(User, user_id)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"User with id {user_id} not found",
            )
        return user

    @staticmethod
    def update_user(
        session: Session,
        user_id: int,
        update_data: UpdateUserRequest,
        current_user: User,
    ) -> User:
        user = UserService.get_user_by_id(session, user_id)

        # Chỉ cho phép user tự cập nhật thông tin của mình,
        # hoặc ADMIN có thể cập nhật bất kỳ user nào
        if current_user.id != user_id and current_user.role != "ADMIN":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not enough permissions to update this user",
            )

        # Chỉ cập nhật các field được gửi lên (partial update)
        update_dict = update_data.model_dump(exclude_unset=True)
        for field, value in update_dict.items():
            setattr(user, field, value)

        user.updated_at = _utcnow()
        session.add(user)
        session.commit()
        session.refresh(user)
        return user

    @staticmethod
    def delete_user(
        session: Session,
        user_id: int,
        current_user: User,
    ) -> None:
        user = UserService.get_user_by_id(session, user_id)

        # Chỉ cho phép user tự xóa tài khoản của mình,
        # hoặc ADMIN có thể xóa bất kỳ user nào
        if current_user.id != user_id and current_user.role != "ADMIN":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not enough permissions to delete this user",
            )

        session.delete(user)
        session.commit()
