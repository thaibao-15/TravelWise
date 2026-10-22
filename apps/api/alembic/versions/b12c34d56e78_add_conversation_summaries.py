"""add conversation summaries

Revision ID: b12c34d56e78
Revises: 97a4f6864d3d
Create Date: 2026-10-18 10:56:54.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "b12c34d56e78"
down_revision: str | Sequence[str] | None = "97a4f6864d3d"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the conversation summaries table if it does not exist."""
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_names = inspector.get_table_names()

    if "conversation_summaries" not in table_names:
        op.create_table(
            "conversation_summaries",
            sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
            sa.Column(
                "conversation_id",
                sa.BigInteger(),
                sa.ForeignKey("conversations.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("summary", sa.UnicodeText(), nullable=False),
            sa.Column(
                "last_summarized_message_id",
                sa.BigInteger(),
                sa.ForeignKey("messages.id", ondelete="NO ACTION"),
                nullable=True,
            ),
            sa.Column(
                "updated_at", sa.DateTime(), server_default=sa.func.sysdatetime()
            ),
            sa.UniqueConstraint(
                "conversation_id",
                name="UQ_conversation_summaries_conversation",
            ),
        )


def downgrade() -> None:
    """Drop the conversation summaries table."""
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_names = inspector.get_table_names()

    if "conversation_summaries" in table_names:
        op.drop_table("conversation_summaries")
