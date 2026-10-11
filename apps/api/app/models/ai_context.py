"""
AIContext domain model — database-agnostic.

Maps to: ai_context table
"""

from datetime import datetime
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Column, DateTime, UnicodeText
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import _utcnow

if TYPE_CHECKING:
    from app.models.conversation import Conversation


class AIContext(SQLModel, table=True):
    """Stores AI context or summary for a conversation."""

    __tablename__ = "ai_context"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    conversation_id: Optional[int] = Field(
        default=None,
        foreign_key="conversations.id",
        ondelete="CASCADE",
        index=True,
    )

    summary: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
    )

    updated_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime,
    )

    # Relationships
    conversation: Optional["Conversation"] = Relationship(back_populates="ai_contexts")
