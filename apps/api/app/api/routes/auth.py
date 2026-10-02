from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from app.api.deps import get_current_user, get_session
from app.models.user import User
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse
from app.schemas.user import UserResponse
from app.services.auth_service import AuthService

router = APIRouter(
    prefix="/api/v1/auth",
    tags=["Auth"],
)


@router.post(
    "/register",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,
)
def register(
    register_data: RegisterRequest,
    session: Session = Depends(get_session),
) -> UserResponse:
    user = AuthService.register_user(session, register_data)
    return user


@router.post(
    "/login",
    response_model=TokenResponse,
    status_code=status.HTTP_200_OK,
)
def login(
    login_data: LoginRequest,
    session: Session = Depends(get_session),
) -> TokenResponse:
    user = AuthService.authenticate_user(session, login_data)
    return AuthService.create_user_token(user)


@router.get(
    "/me",
    response_model=UserResponse,
    status_code=status.HTTP_200_OK,
)
def get_me(
    current_user: User = Depends(get_current_user),
) -> UserResponse:
    return current_user
