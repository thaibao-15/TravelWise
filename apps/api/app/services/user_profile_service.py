"""Business logic for authenticated users' travel profiles."""

import json
from typing import Any

from fastapi import HTTPException, status
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.db.base import _utcnow
from app.models.user_profile import UserProfile
from app.schemas.user_profile import (
    JSON_ARRAY_FIELDS,
    UserProfileBase,
    UserProfileCreate,
    UserProfileResponse,
    UserProfileUpdate,
)


class UserProfileService:
    """Create and update the one profile owned by the authenticated user."""

    @staticmethod
    def get_profile(session: Session, user_id: int) -> UserProfile:
        profile = session.exec(
            select(UserProfile).where(UserProfile.user_id == user_id)
        ).first()
        if profile is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Travel profile not found.",
            )
        return profile

    @staticmethod
    def _serialize_fields(data: dict[str, Any]) -> dict[str, Any]:
        for field in JSON_ARRAY_FIELDS:
            if field in data and data[field] is not None:
                data[field] = json.dumps(data[field], ensure_ascii=False)
        return data

    @staticmethod
    def to_response(profile: UserProfile) -> UserProfileResponse:
        data: dict[str, Any] = {
            field: getattr(profile, field) for field in UserProfileBase.model_fields
        }
        for field in JSON_ARRAY_FIELDS:
            raw_value = getattr(profile, field)
            if raw_value is None:
                data[field] = None
            else:
                try:
                    parsed = json.loads(raw_value)
                except (TypeError, json.JSONDecodeError) as exc:
                    raise HTTPException(
                        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                        detail="Stored profile list data is invalid.",
                    ) from exc
                if not isinstance(parsed, list) or not all(
                    isinstance(item, str) for item in parsed
                ):
                    raise HTTPException(
                        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                        detail="Stored profile list data is invalid.",
                    )
                data[field] = parsed
        data.update(
            id=profile.id,
            user_id=profile.user_id,
            created_at=profile.created_at,
            updated_at=profile.updated_at,
        )
        return UserProfileResponse.model_validate(data)

    @classmethod
    def create_profile(
        cls,
        session: Session,
        user_id: int,
        profile_data: UserProfileCreate,
    ) -> UserProfileResponse:
        existing = session.exec(
            select(UserProfile).where(UserProfile.user_id == user_id)
        ).first()
        if existing is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Travel profile already exists.",
            )

        values = cls._serialize_fields(profile_data.model_dump())
        profile = UserProfile(user_id=user_id, **values)
        session.add(profile)
        try:
            session.commit()
        except IntegrityError as exc:
            session.rollback()
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Travel profile already exists.",
            ) from exc
        session.refresh(profile)
        return cls.to_response(profile)

    @classmethod
    def update_profile(
        cls,
        session: Session,
        user_id: int,
        profile_data: UserProfileUpdate,
    ) -> UserProfileResponse:
        profile = cls.get_profile(session, user_id)
        updates = profile_data.model_dump(exclude_unset=True)
        merged = {
            field: getattr(profile, field) for field in UserProfileBase.model_fields
        }
        for field in JSON_ARRAY_FIELDS:
            if field in merged and merged[field] is not None:
                merged[field] = json.loads(merged[field])
        merged.update(updates)
        # Revalidate the complete effective state so PUT cannot create an invalid
        # budget range when only one endpoint of the range is changed.
        try:
            validated = UserProfileBase.model_validate(merged)
        except ValidationError as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail=exc.errors(),
            ) from exc
        values = cls._serialize_fields(validated.model_dump())
        for field, value in values.items():
            setattr(profile, field, value)
        profile.updated_at = _utcnow()
        session.add(profile)
        try:
            session.commit()
        except IntegrityError as exc:
            session.rollback()
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Could not update travel profile.",
            ) from exc
        session.refresh(profile)
        return cls.to_response(profile)
