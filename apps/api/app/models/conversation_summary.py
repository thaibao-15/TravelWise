"""
Conversation summary domain model.

Maps to: conversation_summaries table
"""

from datetime import datetime
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Column, DateTime, UnicodeText
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import _utcnow

if TYPE_CHECKING:
    from app.models.conversation import Conversation
    from app.models.message import Message


class ConversationSummary(SQLModel, table=True):
    """The latest persisted summary for a conversation."""

    __tablename__ = "conversation_summaries"

    id: Optional[int] = Field(default=None, primary_key=True)

    conversation_id: int = Field(
        foreign_key="conversations.id",
        nullable=False,
        ondelete="CASCADE",
        unique=True,
    )

    summary: str = Field(
        sa_column=Column(UnicodeText, nullable=False),
    )

    last_summarized_message_id: Optional[int] = Field(
        default=None,
        foreign_key="messages.id",
        ondelete="NO ACTION",
    )

    updated_at: datetime = Field(default_factory=_utcnow, sa_type=DateTime)

    conversation: Optional["Conversation"] = Relationship(
        back_populates="summary",
    )
    last_summarized_message: Optional["Message"] = Relationship()
