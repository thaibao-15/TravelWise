"""
Conversation domain model — database-agnostic.

Maps to: conversations table
"""

from typing import TYPE_CHECKING, List, Optional

from sqlalchemy import Column, Unicode
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.message import Message
    from app.models.user import User


class Conversation(TimestampMixin, SQLModel, table=True):
    """Conversation session grouping chat messages between a User and AI."""

    __tablename__ = "conversations"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
        # BIGINT IDENTITY → auto-increment on both SQL Server and PostgreSQL
    )

    user_id: Optional[int] = Field(
        default=None,
        foreign_key="users.id",
        ondelete="CASCADE",
    )

    title: Optional[str] = Field(
        default=None,
        sa_column=Column(Unicode(255)),
        # NVARCHAR(255) → Unicode(255) to preserve Vietnamese characters
    )

    # created_at and updated_at are inherited from TimestampMixin.
    # Uses Python-side datetime.now(timezone.utc) — database-agnostic.

    # Relationships
    user: Optional["User"] = Relationship(back_populates="conversations")
    messages: List["Message"] = Relationship(
        back_populates="conversation",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"},
    )
