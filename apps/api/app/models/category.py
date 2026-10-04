"""
Category model — database-agnostic.

Maps to: categories table
"""

from typing import TYPE_CHECKING, List, Optional

from sqlalchemy import Column, Text
from sqlmodel import Field, Relationship, SQLModel

if TYPE_CHECKING:
    from app.models.place import Place


class Category(SQLModel, table=True):
    __tablename__ = "categories"

    id: Optional[int] = Field(
        default=None,
        primary_key=True,
        # BIGINT IDENTITY → SQLAlchemy: IDENTITY(1,1) on SQL Server,
        # SERIAL/BIGSERIAL on PostgreSQL — both handled automatically.
    )

    name: Optional[str] = Field(
        default=None,
        max_length=100,
        # NVARCHAR(100) → String(100) via SQLModel max_length
    )

    description: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        # NVARCHAR(MAX) → Text (compatible with both SQL Server and PostgreSQL)
    )

    # Relationships
    places: List["Place"] = Relationship(back_populates="category")
