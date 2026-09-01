"""The only module that opens a database connection.

The account this uses holds SELECT on four reference tables and nothing else
(see server/MIGRATIONS.md). Keeping connection construction here means the
read-only boundary has exactly one place to audit.
"""
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine

from app.config import Settings


def create_engine_from(settings: Settings) -> Engine:
    url = "mysql+pymysql://{user}:{password}@{host}:{port}/{name}?charset=utf8mb4".format(
        user=settings.db_user,
        password=settings.db_password,
        host=settings.db_host,
        port=settings.db_port,
        name=settings.db_name,
    )
    # pool_pre_ping because MySQL drops idle connections and the first request
    # after a quiet period must not fail on a stale one.
    return create_engine(url, pool_pre_ping=True, pool_recycle=3600, future=True)
