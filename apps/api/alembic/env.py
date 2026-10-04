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
from sqlalchemy import create_engine, pool
from sqlmodel import SQLModel

# Ensure the app package is on sys.path when running alembic from the project root.
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.config import settings

# Import ALL models here so their metadata is registered with SQLModel.metadata
# before autogenerate runs. Add new models here as they are created.
from app.models.user import User  # noqa: F401
from app.models.category import Category  # noqa: F401
from app.models.place import Place  # noqa: F401
from app.models.restaurant_detail import RestaurantDetail  # noqa: F401
from app.models.hotel_detail import HotelDetail  # noqa: F401
from app.models.place_image import PlaceImage  # noqa: F401
from app.models.opening_hours import OpeningHours  # noqa: F401
from app.models.knowledge import Knowledge  # noqa: F401

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# NOTE: We intentionally do NOT call config.set_main_option("sqlalchemy.url", ...)
# because the mssql+pyodbc URL contains % characters (URL-encoded ODBC params) that
# configparser misinterprets as interpolation syntax (%(...)s).
# Instead, we pass the URL directly to create_engine() / context.configure() below.
DB_URL = settings.SQLALCHEMY_DATABASE_URI

target_metadata = SQLModel.metadata


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode (no live DB connection required)."""
    context.configure(
        url=DB_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode (live DB connection)."""
    connectable = create_engine(DB_URL, poolclass=pool.NullPool)

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
