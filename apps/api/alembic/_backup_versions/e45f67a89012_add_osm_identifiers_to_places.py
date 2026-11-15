"""add_osm_identifiers_to_places

Revision ID: e45f67a89012
Revises: 3b81166d5850, c23d45e67f89
Create Date: 2026-10-23 21:55:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e45f67a89012'
down_revision: Union[str, Sequence[str], None] = ('3b81166d5850', 'c23d45e67f89')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema safely and idempotently."""
    bind = op.get_bind()
    insp = sa.inspect(bind)

    existing_cols = [c["name"] for c in insp.get_columns("places")]

    # 1. Add source column
    if "source" not in existing_cols:
        op.add_column("places", sa.Column("source", sa.String(length=50), nullable=True))

    # 2. Add osm_type column
    if "osm_type" not in existing_cols:
        op.add_column("places", sa.Column("osm_type", sa.String(length=20), nullable=True))

    # 3. Add osm_id column
    if "osm_id" not in existing_cols:
        op.add_column("places", sa.Column("osm_id", sa.BigInteger(), nullable=True))

    # 4. Create filtered unique index on (osm_type, osm_id) where osm_id IS NOT NULL
    existing_indexes = [idx["name"] for idx in insp.get_indexes("places")]
    if "uq_places_osm_type_id" not in existing_indexes:
        dialect_name = bind.dialect.name
        if dialect_name == "mssql":
            # SQL Server filtered unique index allows multiple NULL values for manual places
            bind.execute(
                sa.text(
                    "CREATE UNIQUE NONCLUSTERED INDEX uq_places_osm_type_id "
                    "ON places (osm_type, osm_id) "
                    "WHERE osm_id IS NOT NULL;"
                )
            )
        elif dialect_name == "postgresql":
            bind.execute(
                sa.text(
                    "CREATE UNIQUE INDEX uq_places_osm_type_id "
                    "ON places (osm_type, osm_id) "
                    "WHERE osm_id IS NOT NULL;"
                )
            )
        else:
            try:
                op.create_index(
                    "uq_places_osm_type_id",
                    "places",
                    ["osm_type", "osm_id"],
                    unique=True,
                )
            except Exception:
                pass


def downgrade() -> None:
    """Downgrade schema safely."""
    bind = op.get_bind()
    insp = sa.inspect(bind)

    existing_indexes = [idx["name"] for idx in insp.get_indexes("places")]
    if "uq_places_osm_type_id" in existing_indexes:
        op.drop_index("uq_places_osm_type_id", table_name="places")

    existing_cols = [c["name"] for c in insp.get_columns("places")]
    if "osm_id" in existing_cols:
        op.drop_column("places", "osm_id")
    if "osm_type" in existing_cols:
        op.drop_column("places", "osm_type")
    if "source" in existing_cols:
        op.drop_column("places", "source")
