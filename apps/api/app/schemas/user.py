from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, EmailStr


class UserResponse(BaseModel):
    id: int
    email: EmailStr
    full_name: Optional[str] = None
    avatar_url: Optional[str] = None
    role: str
    is_active: bool
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class UpdateUserRequest(BaseModel):
    """Schema cho PATCH /users/{user_id} — tất cả field đều optional (partial update)."""
    full_name: Optional[str] = None
    avatar_url: Optional[str] = None
    is_active: Optional[bool] = None
