"""add user profiles

Revision ID: c23d45e67f89
Revises: b12c34d56e78
Create Date: 2026-10-18 11:47:52.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "c23d45e67f89"
down_revision: str | Sequence[str] | None = "b12c34d56e78"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the user_profiles table if it does not exist."""
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "user_profiles" in inspector.get_table_names():
        return

    op.create_table(
        "user_profiles",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column(
            "user_id",
            sa.BigInteger(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("phone", sa.Unicode(20), nullable=True),
        sa.Column("date_of_birth", sa.Date(), nullable=True),
        sa.Column("gender", sa.Unicode(20), nullable=True),
        sa.Column("nationality", sa.Unicode(100), nullable=True),
        sa.Column(
            "preferred_language", sa.Unicode(10), server_default="vi", nullable=False
        ),
        sa.Column("travel_style", sa.Unicode(50), nullable=True),
        sa.Column("favorite_categories", sa.UnicodeText(), nullable=True),
        sa.Column("interests", sa.UnicodeText(), nullable=True),
        sa.Column("budget_min", sa.Numeric(12, 2), nullable=True),
        sa.Column("budget_max", sa.Numeric(12, 2), nullable=True),
        sa.Column("currency", sa.Unicode(10), server_default="VND", nullable=False),
        sa.Column("preferred_transport", sa.Unicode(50), nullable=True),
        sa.Column("accommodation_type", sa.Unicode(50), nullable=True),
        sa.Column("dietary_preferences", sa.UnicodeText(), nullable=True),
        sa.Column("accessibility_needs", sa.UnicodeText(), nullable=True),
        sa.Column("preferred_travel_pace", sa.Unicode(30), nullable=True),
        sa.Column("additional_preferences", sa.UnicodeText(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.sysdatetime()),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.func.sysdatetime()),
    )


def downgrade() -> None:
    """Drop the user_profiles table."""
    bind = op.get_bind()
    if "user_profiles" in sa.inspect(bind).get_table_names():
        op.drop_table("user_profiles")
