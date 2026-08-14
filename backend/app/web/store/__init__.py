"""Firestore-backed storage for the web surface.

Replaces `server/store/db.ts`'s in-memory-plus-JSON-file store. See `db.py` for
the collection list and `collections.py` for the access primitives.
"""

from app.web.store.collections import Collection, SingletonDocument
from app.web.store.db import PREFIX, WebStore, get_store, is_ready

__all__ = [
    "PREFIX",
    "Collection",
    "SingletonDocument",
    "WebStore",
    "get_store",
    "is_ready",
]
