"""Replica-preview cache — ports `server/routes/faceCache.ts`.

Tavus replica previews are MP4s on a remote CDN, so every tile in the face picker used
to buffer over the network the moment it scrolled into view. This fetches each preview
once, keeps it in Firebase Storage, and redirects the browser to a URL with immutable
cache headers — so the second look is served from the browser's own cache and the
picker opens instantly.

**Stored in the bucket, never on the server's filesystem.** The Express version wrote
MP4s under `server/data/face-cache/`, which cannot work here: a container's disk is
ephemeral, so the cache would be lost on every deploy, and each worker would keep its
own copy while missing what the others had already fetched.

**Not an open proxy.** HTTPS only, and the upstream host must match a small allowlist —
without it, an authenticated caller could use this endpoint to fetch arbitrary URLs from
inside the network and have the bytes handed back.

A cache miss is not a failure: if the fetch or the upload fails, the browser is
redirected to the original CDN URL and the picker still shows the face.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
from urllib.parse import urlparse

from fastapi import APIRouter, HTTPException, Query, Request, status
from fastapi.responses import RedirectResponse

from app.config import Settings
from app.providers.base import http_client
from app.security import AuthedUser
from app.web.deps import WebUserFromQuery, settings_of
from app.web.services import storage

logger = logging.getLogger("web.face_cache")

# Mounted ahead of /avatar in app.web so this more specific path wins, mirroring the
# Express mount order.
router = APIRouter(prefix="/avatar/face-cache", tags=["web:avatar"])

DEFAULT_HOSTS = (
    "tavus.io",
    "tavusapi.com",
    "tavus.video",
    "cloudfront.net",
    "amazonaws.com",
)

# Some Tavus stock previews exceed 40 MB (observed on cdn.replica.tavus.io), so the cap
# is generous — instant playback is worth the storage. Still bounded, so a mistaken URL
# cannot fill the bucket.
MAX_BYTES = 150 * 1024 * 1024

DOWNLOAD_TIMEOUT_SECONDS = 30.0

# Where cached previews live. Prefixed like every other web-owned collection, so it is
# obvious in the console which surface owns them.
OBJECT_PREFIX = "web_face_cache"

# Fetches in progress, keyed by object path, so N tiles asking for the same video share
# one upstream fetch instead of racing to upload it.
_inflight: dict[str, asyncio.Task] = {}


def allowed_hosts(settings: Settings) -> tuple[str, ...]:
    extra = tuple(
        part.strip().lower()
        for part in (settings.face_cache_hosts or "").replace(",", " ").split()
        if part.strip()
    )
    return DEFAULT_HOSTS + extra


def is_allowed(settings: Settings, hostname: str) -> bool:
    """Exact match or a subdomain of an allowed host.

    The leading dot in the suffix check is what stops `nottavus.io` matching `tavus.io` —
    a bare `endswith("tavus.io")` would accept an attacker's domain.
    """
    host = (hostname or "").lower()
    if not host:
        return False
    return any(
        host == domain or host.endswith(f".{domain}") for domain in allowed_hosts(settings)
    )


def cache_key(url: str) -> str:
    """A stable key for a URL.

    A hash, so no part of the URL reaches the object path: a CDN path could contain `..`
    or a separator and land the object somewhere unintended.
    """
    return hashlib.sha256(url.encode()).hexdigest()


def object_path(url: str) -> str:
    return f"{OBJECT_PREFIX}/{cache_key(url)}.mp4"


def download_token(url: str) -> str:
    """A deterministic token for the cached object's URL.

    Derived from the URL rather than randomly generated so the download URL is
    reproducible without a second round trip to read the object's metadata. Safe here
    because the content is a PUBLIC replica preview from a CDN — the token gates nothing
    that was not already public, and the host allowlist is what stops this endpoint being
    used to cache anything else.
    """
    return hashlib.sha256(f"face-cache:{url}".encode()).hexdigest()[:32]


async def _fetch_and_store(settings: Settings, url: str) -> str:
    """Fetch a preview from the CDN and put it in the bucket. Returns its URL."""
    response = await http_client().get(
        url, follow_redirects=True, timeout=DOWNLOAD_TIMEOUT_SECONDS
    )
    if response.status_code >= 400:
        raise RuntimeError(f"Upstream fetch failed ({response.status_code})")

    declared = int(response.headers.get("content-length") or 0)
    if declared > MAX_BYTES or len(response.content) > MAX_BYTES:
        raise RuntimeError("Preview too large to cache")

    return await storage.upload(
        settings,
        object_path(url),
        response.content,
        content_type=response.headers.get("content-type") or "video/mp4",
        token=download_token(url),
    )


async def ensure_cached(settings: Settings, url: str) -> str:
    """The bucket URL for a preview, fetching it once if it is not there yet."""
    existing = await storage.find(settings, object_path(url))
    if existing:
        return existing

    key = object_path(url)
    running = _inflight.get(key)
    if running is not None:
        return await running

    task = asyncio.ensure_future(_fetch_and_store(settings, url))
    _inflight[key] = task
    try:
        return await task
    finally:
        _inflight.pop(key, None)


@router.api_route("", methods=["GET", "HEAD"], summary="Serve a cached replica preview")
async def serve(
    request: Request,
    url: str = Query(default=""),
    user: AuthedUser = WebUserFromQuery,
):
    """Redirect to the cached preview, fetching it into the bucket on first ask.

    Authenticated via the bearer header OR `?token=`, because a `<video>` element cannot
    set headers. HEAD warms the cache without transferring the body, which is what the
    client's background warmer uses.

    ROLE-GATING: the Express route required the recruiter role. Role gating is deferred,
    so any authenticated caller is accepted — the host allowlist is what keeps this from
    being an open proxy.
    """
    settings = settings_of(request)

    parsed = urlparse(url)
    if not parsed.scheme or not parsed.netloc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid url")
    if parsed.scheme != "https" or not is_allowed(settings, parsed.hostname or ""):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Host not allowed")

    try:
        cached = await ensure_cached(settings, url)
    except Exception as exc:  # noqa: BLE001 - a cache miss is not a failure
        # Send the browser to the CDN instead, so the picker still shows the face — just
        # not from cache. The URL is already allowlisted, so this cannot redirect anywhere
        # new.
        logger.warning("face-cache falling back to CDN for %s — %s", parsed.hostname, exc)
        return RedirectResponse(url, status_code=status.HTTP_302_FOUND)

    # 302, not a proxied stream: the bytes go browser↔Google directly, so this service
    # never carries video, and the immutable cache headers on the object mean the second
    # look never comes back here at all.
    return RedirectResponse(cached, status_code=status.HTTP_302_FOUND)
