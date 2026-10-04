"""
Message domain model — database-agnostic.

Maps to: messages table
"""

from datetime import datetime
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Column, DateTime, UnicodeText
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import _utcnow

if TYPE_CHECKING:
    from app.models.conversation import Conversation


class Message(SQLModel, table=True):
    """Chat message in a conversation.

    Intentionally does NOT inherit TimestampMixin because the schema only has
    created_at (not updated_at). created_at is set once on creation.
    """

    __tablename__ = "messages"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
        # BIGINT IDENTITY → auto-increment on both SQL Server and PostgreSQL
    )

    conversation_id: Optional[int] = Field(
        default=None,
        foreign_key="conversations.id",
        ondelete="CASCADE",
    )

    sender: str = Field(
        default="USER",
        max_length=10,
        # NVARCHAR(10) — USER / AI
    )

    content: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
        # NVARCHAR(MAX) → UnicodeText to preserve Vietnamese characters
    )

    audio_url: Optional[str] = Field(
        default=None,
        sa_column=Column(UnicodeText),
        # NVARCHAR(MAX) → UnicodeText
    )

    created_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime,
        # Python-side default — compatible with both SQL Server and PostgreSQL.
        # No GETDATE() server_default used.
    )

    # Relationship
    conversation: Optional["Conversation"] = Relationship(back_populates="messages")
