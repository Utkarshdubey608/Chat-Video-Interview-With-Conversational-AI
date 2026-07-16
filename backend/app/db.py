"""Database engine + session plumbing (SQLModel over SQLite by default)."""

from __future__ import annotations

from collections.abc import Iterator

from sqlmodel import Session, SQLModel, create_engine

from app.config import get_settings

_settings = get_settings()

# check_same_thread=False is required for SQLite under a threaded ASGI server
# and the worker pool.
_connect_args = (
    {"check_same_thread": False}
    if _settings.database_url.startswith("sqlite")
    else {}
)

engine = create_engine(_settings.database_url, echo=False, connect_args=_connect_args)


def init_db() -> None:
    """Create tables. Model classes must be imported before this runs."""
    from app import models  # noqa: F401  (registers tables on the metadata)

    SQLModel.metadata.create_all(engine)


def get_session() -> Iterator[Session]:
    """FastAPI dependency: yields a session and closes it after the request."""
    with Session(engine) as session:
        yield session
