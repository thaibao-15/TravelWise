from typing import List
from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.api.deps import get_current_user, get_session
from app.models.user import User
from app.schemas.user import UserResponse

router = APIRouter(
    prefix="/api/v1/users",
    tags=["Users"],
)


@router.get("/", response_model=List[UserResponse])
def get_users(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> List[User]:
    users = session.exec(select(User)).all()
    return list(users)