"""
Alembic migration environment — database-agnostic.

The database URL is pulled from settings.SQLALCHEMY_DATABASE_URI, which reads from
the DATABASE_URL environment variable (or falls back to SQLSERVER_* vars).

To run migrations against a different database, set DATABASE_URL in .env.
"""

import sys
import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool
from sqlmodel import SQLModel

# Ensure the app package is on sys.path when running alembic from the project root.
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.config import settings

# Import ALL models here so their metadata is registered with SQLModel.metadata
# before autogenerate runs. Add new models here as they are created.
from app.models.category import Category  # noqa: F401
from app.models.hotel_detail import HotelDetail  # noqa: F401
from app.models.knowledge import Knowledge, KnowledgeChunk  # noqa: F401
from app.models.opening_hours import OpeningHours  # noqa: F401
from app.models.place import Place  # noqa: F401
from app.models.place_image import PlaceImage  # noqa: F401
from app.models.restaurant_detail import RestaurantDetail  # noqa: F401
from app.models.user import User  # noqa: F401

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Override the sqlalchemy.url from alembic.ini with the one from settings.
# This ensures DATABASE_URL / SQLSERVER_* env vars are always respected.
config.set_main_option("sqlalchemy.url", settings.SQLALCHEMY_DATABASE_URI)

target_metadata = SQLModel.metadata


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode (no live DB connection required)."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode (live DB connection)."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()

