"""Firebase Storage for the web surface's binary objects.

**Nothing on this surface is written to local disk.** Two things need to live somewhere
a browser can fetch them — invite-email logos and the replica-preview cache — and both
belong in the bucket rather than on a server filesystem:

* A container's disk is ephemeral, so a cache on it is lost on every deploy.
* With more than one worker, each would keep its own copy, and each would miss what the
  others had already fetched.
* An email client cannot load an image from our filesystem at all.

Objects are returned as **tokenised download URLs**. That is the same mechanism the
Firebase client SDKs use: the object stays private to the bucket's rules, and the token
in the URL is what grants read access to whoever holds the link. It works from a mail
client and a `<video>` tag, neither of which can send an Authorization header.

The Admin SDK write bypasses Storage rules, which is the point — the recruiter is
authenticated by the route, and the bucket needs no public rule.
"""

from __future__ import annotations

import asyncio
import logging
from urllib.parse import quote

from app.config import Settings
from app.firebase import ensure_app

logger = logging.getLogger("web.storage")

# A year, immutable: every path this module writes is content-addressed or carries a
# generated id, so an object's bytes never change once written.
IMMUTABLE_CACHE = "public, max-age=31536000, immutable"

_TOKEN_KEY = "firebaseStorageDownloadTokens"


def _bucket(settings: Settings):
    """The configured bucket, or the project's default."""
    from firebase_admin import storage

    ensure_app(settings)
    name = settings.firebase_storage_bucket.strip() or None
    return storage.bucket(name)


def _download_url(bucket_name: str, path: str, token: str) -> str:
    return (
        f"https://firebasestorage.googleapis.com/v0/b/{bucket_name}/o/"
        f"{quote(path, safe='')}?alt=media&token={token}"
    )


async def find(settings: Settings, path: str) -> str | None:
    """The download URL for an object already in the bucket, or None.

    Returns None rather than raising when the bucket is unreachable: every caller has a
    working fallback (re-upload, or send the browser to the origin), and a storage
    hiccup should degrade rather than fail the request.
    """

    def _read() -> str | None:
        blob = _bucket(settings).get_blob(path)
        if blob is None:
            return None
        token = (blob.metadata or {}).get(_TOKEN_KEY)
        if not token:
            # Written before tokens were stamped, or by something else. Treat it as
            # absent so the caller re-uploads with one rather than returning a URL that
            # will 403.
            return None
        return _download_url(blob.bucket.name, path, token)

    try:
        return await asyncio.to_thread(_read)
    except Exception as exc:  # noqa: BLE001 - callers all have a fallback
        logger.warning("could not look up %s: %s", path, type(exc).__name__)
        return None


async def upload(
    settings: Settings,
    path: str,
    data: bytes,
    *,
    content_type: str,
    token: str,
    cache_control: str = IMMUTABLE_CACHE,
) -> str:
    """Store an object and return its download URL. Raises on failure.

    `token` is supplied by the caller so the URL is predictable at the call site and this
    stays deterministic under test.
    """

    def _write() -> str:
        bucket = _bucket(settings)
        blob = bucket.blob(path)
        blob.metadata = {_TOKEN_KEY: token}
        blob.cache_control = cache_control
        # Non-resumable: these are single-digit-megabyte objects, and a resumable session
        # costs an extra round trip for no benefit at this size.
        blob.upload_from_string(data, content_type=content_type)
        return _download_url(bucket.name, path, token)

    return await asyncio.to_thread(_write)
