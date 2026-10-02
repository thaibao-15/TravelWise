from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel
from sqlalchemy import Column, DateTime, text


class User(SQLModel, table=True):
    __tablename__ = "users"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    email: str = Field(
        max_length=255,
        unique=True,
        nullable=False,
    )

    password: Optional[str] = Field(
        default=None,
    )

    full_name: Optional[str] = Field(
        default=None,
        max_length=255,
    )

    avatar_url: Optional[str] = Field(
        default=None,
    )

    role: str = Field(
        default="USER",
        max_length=20,
    )

    is_active: bool = Field(
        default=True,
    )

    created_at: Optional[datetime] = Field(
        default=None,
        sa_column=Column(
            DateTime,
            server_default=text("GETDATE()"),
        ),
    )

    updated_at: Optional[datetime] = Field(
        default=None,
        sa_column=Column(
            DateTime,
            server_default=text("GETDATE()"),
        ),
    )