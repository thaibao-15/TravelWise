"""
User domain model — database-agnostic.

Uses TimestampMixin from app.db.base for created_at / updated_at, which relies on
Python-side datetime defaults instead of SQL Server-specific GETDATE().
"""

from typing import TYPE_CHECKING, List, Optional

from sqlmodel import Field, Relationship, SQLModel

from app.db.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.conversation import Conversation


class User(TimestampMixin, SQLModel, table=True):
    __tablename__ = "users"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
        # BIGINT/INTEGER auto-increment: SQLAlchemy uses IDENTITY on SQL Server
        # and SERIAL/BIGSERIAL on PostgreSQL automatically when primary_key=True.
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
    # created_at and updated_at are inherited from TimestampMixin.
    # They use Python-side datetime.now(timezone.utc) — compatible with both
    # SQL Server and PostgreSQL.

    # Relationships
    conversations: List["Conversation"] = Relationship(
        back_populates="user",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"},
    )