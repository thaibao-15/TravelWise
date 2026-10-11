"""add_itinerary_days_and_activities

Revision ID: 6e8f1234abcd
Revises: 4d7e744dbbd0
Create Date: 2026-10-11 17:40:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "6e8f1234abcd"
down_revision: Union[str, Sequence[str], None] = "4d7e744dbbd0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema safely and idempotently for itinerary_days and itinerary_activities."""
    bind = op.get_bind()
    insp = sa.inspect(bind)
    table_names = insp.get_table_names()

    # 1. Create itinerary_days table if not exists
    if "itinerary_days" not in table_names:
        op.create_table(
            "itinerary_days",
            sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
            sa.Column("trip_id", sa.BigInteger(), sa.ForeignKey("trips.id", ondelete="CASCADE"), nullable=False),
            sa.Column("day_number", sa.Integer(), nullable=False),
            sa.Column("date", sa.Date(), nullable=True),
            sa.Column("title", sa.Unicode(255), nullable=True),
            sa.Column("description", sa.UnicodeText(), nullable=True),
            sa.UniqueConstraint("trip_id", "day_number", name="uq_itinerary_days_trip_day"),
        )
        try:
            op.create_index("idx_itinerary_days_trip", "itinerary_days", ["trip_id"])
        except Exception:
            pass

    # 2. Create itinerary_activities table if not exists
    if "itinerary_activities" not in table_names:
        op.create_table(
            "itinerary_activities",
            sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
            sa.Column("itinerary_day_id", sa.BigInteger(), sa.ForeignKey("itinerary_days.id", ondelete="CASCADE"), nullable=False),
            sa.Column("place_id", sa.BigInteger(), sa.ForeignKey("places.id"), nullable=True),
            sa.Column("activity_type", sa.Unicode(30), server_default="VISIT", nullable=False),
            sa.Column("title", sa.Unicode(255), nullable=False),
            sa.Column("description", sa.UnicodeText(), nullable=True),
            sa.Column("start_time", sa.Time(), nullable=True),
            sa.Column("end_time", sa.Time(), nullable=True),
            sa.Column("duration_minutes", sa.Integer(), nullable=True),
            sa.Column("estimated_cost", sa.Numeric(12, 2), nullable=True),
            sa.Column("travel_duration_minutes", sa.Integer(), nullable=True),
            sa.Column("travel_distance_km", sa.Numeric(10, 2), nullable=True),
            sa.Column("order_index", sa.Integer(), nullable=False),
            sa.Column("note", sa.UnicodeText(), nullable=True),
            sa.UniqueConstraint("itinerary_day_id", "order_index", name="uq_itinerary_activities_day_order"),
        )
        try:
            op.create_index("idx_itinerary_activities_day", "itinerary_activities", ["itinerary_day_id", "order_index"])
            op.create_index("idx_itinerary_activities_place", "itinerary_activities", ["place_id"])
        except Exception:
            pass


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    insp = sa.inspect(bind)
    table_names = insp.get_table_names()
    if "itinerary_activities" in table_names:
        op.drop_table("itinerary_activities")
    if "itinerary_days" in table_names:
        op.drop_table("itinerary_days")
