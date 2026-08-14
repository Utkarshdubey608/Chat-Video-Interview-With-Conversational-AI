"""AWS Rekognition — DetectFaces on a single video frame.

The odd one out among the providers: boto3 rather than httpx, because Rekognition
is signed with SigV4 and hand-rolling that would be a liability for no gain. So
this does not subclass `ProviderClient` — it has no `base_url` and no bearer
header — but it raises the same `ProviderNotConfigured` / `UpstreamError` so
routers still need no try/except and `app.main`'s handlers still apply.

boto3 is synchronous, so the call is wrapped in `asyncio.to_thread`. The web
client sends a frame every 8 seconds per candidate; blocking the event loop for
each one would serialise every other request behind it.
"""

from __future__ import annotations

import asyncio
import base64
import logging
from typing import Any

from app.config import Settings
from app.providers.base import ProviderNotConfigured, UpstreamError

logger = logging.getLogger("providers.rekognition")

NAME = "Rekognition"
ENV_VAR = "AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY"

# A frame this small is a blank or failed capture, not a face. Rejecting it here
# saves a billed API call that could only ever answer "no faces".
MIN_IMAGE_BYTES = 5_000

_client: Any | None = None


def is_configured(settings: Settings) -> bool:
    """Both halves of the credential pair, or nothing.

    Checked as a pair because a half-configured deployment fails at call time with
    an opaque botocore error rather than an actionable 503.
    """
    return bool(
        settings.aws_access_key_id.strip() and settings.aws_secret_access_key.strip()
    )


def _rekognition(settings: Settings):
    """The boto3 client, built once.

    Cached because constructing one resolves credentials and endpoints, which is
    wasteful per frame.
    """
    global _client
    if _client is not None:
        return _client

    if not is_configured(settings):
        raise ProviderNotConfigured(NAME, ENV_VAR)

    try:
        import boto3
    except ImportError as exc:  # pragma: no cover - listed in requirements
        raise ProviderNotConfigured(
            NAME, "boto3 (run: pip install -r requirements.txt)"
        ) from exc

    _client = boto3.client(
        "rekognition",
        region_name=settings.aws_region.strip() or "us-east-2",
        aws_access_key_id=settings.aws_access_key_id.strip(),
        aws_secret_access_key=settings.aws_secret_access_key.strip(),
    )
    return _client


def reset() -> None:
    """Drop the cached client. For tests, and after a credential change."""
    global _client
    _client = None


async def detect_faces(settings: Settings, image_base64: str) -> list[dict]:
    """Face attributes for one base64-encoded JPEG frame.

    Returns Rekognition's `FaceDetails` list verbatim — the client has the
    aggregation logic and expects the vendor's exact shape. An empty list means a
    valid frame with no face in it, which is a real answer, not a failure.
    """
    try:
        image_bytes = base64.b64decode(image_base64, validate=True)
    except Exception as exc:  # noqa: BLE001 - malformed input from the browser
        raise UpstreamError(NAME, 400, "Frame is not valid base64.") from exc

    client = _rekognition(settings)

    def _call() -> dict:
        return client.detect_faces(Image={"Bytes": image_bytes}, Attributes=["ALL"])

    try:
        response = await asyncio.to_thread(_call)
    except ProviderNotConfigured:
        raise
    except Exception as exc:  # noqa: BLE001 - normalised for the shared handlers
        # botocore exposes the HTTP status here; without it every AWS problem —
        # throttling, a bad key, an oversized image — would collapse to one code.
        status = 502
        metadata = getattr(exc, "response", {}) or {}
        if isinstance(metadata, dict):
            status = int(
                metadata.get("ResponseMetadata", {}).get("HTTPStatusCode") or 502
            )
        logger.warning("Rekognition DetectFaces failed: %s", type(exc).__name__)
        raise UpstreamError(NAME, status, str(exc)[:200]) from exc

    return list(response.get("FaceDetails") or [])
