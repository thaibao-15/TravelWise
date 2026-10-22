"""Authenticated user travel profile endpoints."""

from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from app.api.deps import get_current_user, get_session
from app.models.user import User
from app.schemas.user_profile import (
    UserProfileCreate,
    UserProfileResponse,
    UserProfileUpdate,
)
from app.services.user_profile_service import UserProfileService

router = APIRouter(
    prefix="/api/v1/users/me/profile",
    tags=["User Travel Profile"],
)


@router.get("", response_model=UserProfileResponse)
def get_my_profile(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> UserProfileResponse:
    return UserProfileService.to_response(
        UserProfileService.get_profile(session, current_user.id)
    )


@router.post(
    "", response_model=UserProfileResponse, status_code=status.HTTP_201_CREATED
)
def create_my_profile(
    profile_data: UserProfileCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> UserProfileResponse:
    return UserProfileService.create_profile(
        session=session,
        user_id=current_user.id,
        profile_data=profile_data,
    )


@router.put("", response_model=UserProfileResponse)
def update_my_profile(
    profile_data: UserProfileUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> UserProfileResponse:
    return UserProfileService.update_profile(
        session=session,
        user_id=current_user.id,
        profile_data=profile_data,
    )
