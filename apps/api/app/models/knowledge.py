"""
Knowledge model — database-agnostic.

Maps to: knowledge table

Per the SQL schema, Knowledge has only `created_at` (no updated_at).
We define created_at as a standalone field (not via TimestampMixin) so we don't
add an unwanted updated_at column.

RAG note: KnowledgeChunk (embedding/vector) is deferred to Phase 2 (RAG pipeline).
"""

from datetime import datetime
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Column, DateTime, Text
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import _utcnow

if TYPE_CHECKING:
    from app.models.place import Place


class Knowledge(SQLModel, table=True):
    """Knowledge article linked to a Place — primary RAG source document.

    Intentionally does NOT inherit TimestampMixin because the schema only has
    created_at (not updated_at). created_at is set once on creation.
    """

    __tablename__ = "knowledge"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    place_id: Optional[int] = Field(
        default=None,
        foreign_key="places.id",
        # ON DELETE CASCADE handled in migration
    )

    title: Optional[str] = Field(
        default=None,
        max_length=255,
        # NVARCHAR(255) → String(255)
    )

    content: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        # NVARCHAR(MAX) → Text (SQL Server: NVARCHAR(MAX), PostgreSQL: TEXT)
    )

    source: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        # NVARCHAR(MAX) → Text (URL or citation reference)
    )

    created_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime,
        # Python-side default — compatible with both SQL Server and PostgreSQL.
        # No GETDATE() server_default used.
    )

    # Relationship
    place: Optional["Place"] = Relationship(back_populates="knowledge_items")

