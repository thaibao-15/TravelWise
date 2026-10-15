"""add_missing_trip_preferences_columns

Revision ID: 97a4f6864d3d
Revises: 6e8f1234abcd
Create Date: 2026-10-15 14:05:07.493233

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '97a4f6864d3d'
down_revision: Union[str, Sequence[str], None] = '6e8f1234abcd'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
