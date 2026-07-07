"""Alembic environment configuration.

This repo owns only DDL migrations; no SQLAlchemy models are defined here.
target_metadata is None — autogenerate is not used.
"""

import asyncio
import os
from logging.config import fileConfig
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse

from alembic import context
from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import create_async_engine

# Load .env from the project root (one level above alembic/).
# Must run before the first call to _database_url().
load_dotenv(Path(__file__).parent.parent / ".env")

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# No ORM models: migrations are written as raw SQL in each version file.
target_metadata = None


def _database_url() -> str:
    """Return DATABASE_URL from the environment, normalized for asyncpg.

    Strips query parameters that asyncpg does not accept as connect() kwargs
    (e.g. channel_binding, which Neon may include in its connection strings).
    """
    url = os.environ.get("DATABASE_URL")
    if not url:
        raise RuntimeError(
            "DATABASE_URL environment variable is not set. "
            "Copy .env.example to .env and set the value."
        )
    # asyncpg does not accept channel_binding as a connect() kwarg; remove it.
    parsed = urlparse(url)
    qs = {k: v[0] for k, v in parse_qs(parsed.query, keep_blank_values=True).items()
          if k != "channel_binding"}
    return urlunparse(parsed._replace(query=urlencode(qs)))


def run_migrations_offline() -> None:
    """Run migrations in offline (SQL-generation) mode."""
    context.configure(
        url=_database_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: object) -> None:
    """Run migrations against an open connection."""
    context.configure(  # type: ignore[arg-type]
        connection=connection,
        target_metadata=target_metadata,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    """Run migrations in online mode."""
    connectable = create_async_engine(_database_url())
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
