"""The only module that opens a database connection.

The account this uses holds SELECT on four reference tables and nothing else
(see server/MIGRATIONS.md). Keeping connection construction here means the
read-only boundary has exactly one place to audit.
"""
from sqlalchemy import create_engine
from sqlalchemy.engine import URL, Engine

from app.config import Settings


def create_engine_from(settings: Settings) -> Engine:
    # URL.create escapes credentials. Building this string by hand breaks the
    # moment a password contains @ : / # or % -- it works today only because the
    # current password happens to be alphanumeric.
    url = URL.create(
        "mysql+pymysql",
        username=settings.db_user,
        password=settings.db_password,
        host=settings.db_host,
        port=settings.db_port,
        database=settings.db_name,
        query={"charset": "utf8mb4"},
    )
    # pool_pre_ping because MySQL drops idle connections and the first request
    # after a quiet period must not fail on a stale one.
    return create_engine(url, pool_pre_ping=True, pool_recycle=3600, future=True)
