"""add_trip_planning_context

Revision ID: 4d7e744dbbd0
Revises: 
Create Date: 2026-10-11 15:59:11.479728

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '4d7e744dbbd0'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema safely and idempotently."""
    bind = op.get_bind()
    insp = sa.inspect(bind)
    
    # 1. Update trips table
    trip_cols = [c["name"] for c in insp.get_columns("trips")]
    if "conversation_id" not in trip_cols:
        op.add_column("trips", sa.Column("conversation_id", sa.BigInteger(), nullable=True))
        try:
            op.create_foreign_key(
                "fk_trips_conversation",
                "trips",
                "conversations",
                ["conversation_id"],
                ["id"],
                ondelete="NO ACTION"
            )
        except Exception:
            pass
        try:
            op.create_index("idx_trips_conversation", "trips", ["conversation_id"])
        except Exception:
            pass

    if "destination_city" not in trip_cols:
        op.add_column("trips", sa.Column("destination_city", sa.Unicode(255), nullable=True))

    if "destination_country" not in trip_cols:
        op.add_column("trips", sa.Column("destination_country", sa.Unicode(100), nullable=True))

    if "status" not in trip_cols:
        op.add_column("trips", sa.Column("status", sa.Unicode(50), server_default="DRAFT", nullable=False))

    if "updated_at" not in trip_cols:
        op.add_column("trips", sa.Column("updated_at", sa.DateTime(), nullable=True))

    # 2. Create trip_preferences table if not exists
    table_names = insp.get_table_names()
    if "trip_preferences" not in table_names:
        op.create_table(
            "trip_preferences",
            sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
            sa.Column("trip_id", sa.BigInteger(), sa.ForeignKey("trips.id", ondelete="CASCADE"), nullable=False, unique=True),
            sa.Column("travelers", sa.Integer(), nullable=True),
            sa.Column("adults", sa.Integer(), nullable=True),
            sa.Column("children", sa.Integer(), nullable=True),
            sa.Column("group_type", sa.Unicode(50), nullable=True),
            sa.Column("budget", sa.Numeric(12, 2), nullable=True),
            sa.Column("budget_currency", sa.Unicode(10), server_default="VND", nullable=True),
            sa.Column("budget_scope", sa.Unicode(50), nullable=True),
            sa.Column("duration_days", sa.Integer(), nullable=True),
            sa.Column("nights", sa.Integer(), nullable=True),
            sa.Column("transport", sa.Unicode(100), nullable=True),
            sa.Column("travel_style", sa.Unicode(100), nullable=True),
            sa.Column("interests", sa.UnicodeText(), nullable=True),
            sa.Column("special_requirements", sa.UnicodeText(), nullable=True),
            sa.Column("place_requirements", sa.UnicodeText(), nullable=True),
            sa.Column("schedule_constraints", sa.UnicodeText(), nullable=True),
            sa.Column("raw_context_snapshot", sa.UnicodeText(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.Column("updated_at", sa.DateTime(), nullable=True),
        )

    # 3. Create ai_context table if not exists
    if "ai_context" not in table_names:
        op.create_table(
            "ai_context",
            sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
            sa.Column("conversation_id", sa.BigInteger(), sa.ForeignKey("conversations.id", ondelete="CASCADE"), nullable=True),
            sa.Column("summary", sa.UnicodeText(), nullable=True),
            sa.Column("updated_at", sa.DateTime(), nullable=True),
        )


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    insp = sa.inspect(bind)
    table_names = insp.get_table_names()
    if "trip_preferences" in table_names:
        op.drop_table("trip_preferences")
