"""Request and response schemas for user travel profiles."""

from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

JSON_ARRAY_FIELDS = (
    "favorite_categories",
    "interests",
    "dietary_preferences",
    "accessibility_needs",
)


class UserProfileBase(BaseModel):
    phone: str | None = Field(default=None, max_length=20)
    date_of_birth: date | None = None
    gender: str | None = Field(default=None, max_length=20)
    nationality: str | None = Field(default=None, max_length=100)
    preferred_language: str = Field(default="vi", max_length=10)
    travel_style: str | None = Field(default=None, max_length=50)
    favorite_categories: list[str] | None = None
    interests: list[str] | None = None
    budget_min: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    budget_max: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    currency: str = Field(default="VND", max_length=10)
    preferred_transport: str | None = Field(default=None, max_length=50)
    accommodation_type: str | None = Field(default=None, max_length=50)
    dietary_preferences: list[str] | None = None
    accessibility_needs: list[str] | None = None
    preferred_travel_pace: str | None = Field(default=None, max_length=30)
    additional_preferences: str | None = None

    @field_validator(*JSON_ARRAY_FIELDS)
    @classmethod
    def validate_json_arrays(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return None
        if any(not isinstance(item, str) or not item.strip() for item in value):
            raise ValueError("Các trường danh sách phải chứa chuỗi không rỗng.")
        return [item.strip() for item in value]

    @field_validator("date_of_birth")
    @classmethod
    def validate_birth_date(cls, value: date | None) -> date | None:
        if value is not None and value > date.today():
            raise ValueError("date_of_birth không được nằm trong tương lai.")
        return value

    @model_validator(mode="after")
    def validate_budget_range(self) -> UserProfileBase:
        if (
            self.budget_min is not None
            and self.budget_max is not None
            and self.budget_min > self.budget_max
        ):
            raise ValueError("budget_min phải nhỏ hơn hoặc bằng budget_max.")
        return self


class UserProfileCreate(UserProfileBase):
    """Payload for creating a profile."""


class UserProfileUpdate(BaseModel):
    """Partial update payload; omitted fields remain unchanged."""

    phone: str | None = Field(default=None, max_length=20)
    date_of_birth: date | None = None
    gender: str | None = Field(default=None, max_length=20)
    nationality: str | None = Field(default=None, max_length=100)
    preferred_language: str | None = Field(default=None, max_length=10)
    travel_style: str | None = Field(default=None, max_length=50)
    favorite_categories: list[str] | None = None
    interests: list[str] | None = None
    budget_min: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    budget_max: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    currency: str | None = Field(default=None, max_length=10)
    preferred_transport: str | None = Field(default=None, max_length=50)
    accommodation_type: str | None = Field(default=None, max_length=50)
    dietary_preferences: list[str] | None = None
    accessibility_needs: list[str] | None = None
    preferred_travel_pace: str | None = Field(default=None, max_length=30)
    additional_preferences: str | None = None

    @field_validator(*JSON_ARRAY_FIELDS)
    @classmethod
    def validate_json_arrays(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return None
        if any(not isinstance(item, str) or not item.strip() for item in value):
            raise ValueError("Các trường danh sách phải chứa chuỗi không rỗng.")
        return [item.strip() for item in value]

    @field_validator("date_of_birth")
    @classmethod
    def validate_birth_date(cls, value: date | None) -> date | None:
        if value is not None and value > date.today():
            raise ValueError("date_of_birth không được nằm trong tương lai.")
        return value


class UserProfileResponse(UserProfileBase):
    id: int
    user_id: int
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
