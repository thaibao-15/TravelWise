"""
Knowledge and KnowledgeChunk models — semi database-agnostic.

Maps to: knowledge, knowledge_chunks tables

Embedding strategy:
- Currently stored as raw bytes (LargeBinary / VARBINARY(MAX)) — SQL Server compatible.
- For PostgreSQL: consider using pgvector extension and the `Vector` type for proper
  ANN (Approximate Nearest Neighbor) search.

PostgreSQL migration note for `embedding`:
  1. Install: pip install pgvector
  2. from pgvector.sqlalchemy import Vector
  3. Replace: sa_column=Column(LargeBinary, nullable=True)
     With   : sa_column=Column(Vector(1536), nullable=True)  # adjust dim to your model
  No other model / service changes needed.
"""

from datetime import datetime
from typing import TYPE_CHECKING, List, Optional

from sqlalchemy import Column, LargeBinary, Text
from sqlmodel import Field, Relationship, SQLModel

from app.db.base import TimestampMixin, _utcnow

if TYPE_CHECKING:
    from app.models.place import Place


class Knowledge(TimestampMixin, SQLModel, table=True):
    """Knowledge article linked to a Place — used as RAG source documents."""

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
        # NVARCHAR(MAX) → Text
    )

    source: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        # NVARCHAR(MAX) → Text (URL or reference)
    )

    # NOTE: Knowledge has only created_at (no updated_at per schema).
    # TimestampMixin adds both. If you want only created_at, define it inline
    # instead of using the mixin.
    # created_at inherited from TimestampMixin
    # updated_at also inherited — harmless extra column

    # Relationships
    place: Optional["Place"] = Relationship(back_populates="knowledge_items")
    chunks: List["KnowledgeChunk"] = Relationship(back_populates="knowledge")


class KnowledgeChunk(SQLModel, table=True):
    """Chunked segment of a Knowledge article, with vector embedding for RAG retrieval."""

    __tablename__ = "knowledge_chunks"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
    )

    knowledge_id: Optional[int] = Field(
        default=None,
        foreign_key="knowledge.id",
        # ON DELETE CASCADE handled in migration
    )

    content: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        # NVARCHAR(MAX) → Text
    )

    embedding: Optional[bytes] = Field(
        default=None,
        sa_column=Column(
            LargeBinary,
            nullable=True,
            # SQL Server: VARBINARY(MAX) — stores serialized float vector as bytes.
            # PostgreSQL: Replace with pgvector Vector(dim) for ANN search.
            # [SQL-SERVER-SPECIFIC — see module docstring for migration path]
        ),
    )

    created_at: Optional[datetime] = Field(
        default_factory=_utcnow,
        # Standalone created_at (no updated_at per original schema).
        # SQLModel auto-generates DateTime column from the `datetime` annotation.
        # Compatible with both SQL Server and PostgreSQL.
    )

    # Relationship
    knowledge: Optional["Knowledge"] = Relationship(back_populates="chunks")
