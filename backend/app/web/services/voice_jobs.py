"""Tracking asynchronous voice-analysis jobs.

The Express version kept these in a process-local `Map`, and its own code
acknowledged the consequence — the poll handler returns `FAILED` with the message
"server restarted?" when an id is not found, because a restart lost every job.

That was survivable on one instance. It is not survivable here: the common backend
must run more than one worker to serve web, mobile and desktop, and a job created
by worker A is invisible to worker B, so a poll would land on the wrong worker and
report a healthy job as failed. Firestore is the fix, and it removes the
restart caveat too.

Job ids keep the Express `gemvoice-` prefix. That prefix is load-bearing: the
routes use it to tell a locally-run Gemini job from a real Hume job id, and route
the poll accordingly.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta, timezone

from app.config import Settings
from app.web.store import get_store

logger = logging.getLogger("web.voice_jobs")

# The marker that says "this job ran here, not at Hume".
LOCAL_PREFIX = "gemvoice-"

IN_PROGRESS = "IN_PROGRESS"
COMPLETED = "COMPLETED"
FAILED = "FAILED"

# How long a finished job stays readable. The client polls for minutes, not hours;
# an hour is generous and bounds the collection without a scheduled cleanup.
TTL = timedelta(hours=1)

# A Firestore document is capped at 1 MiB. Prosody for a long interview is well
# inside that (~240 segments x ~10 emotions is tens of KB, and the generation is
# token-capped besides), but storing predictions inline means the ceiling exists —
# so it is checked, and a job that would exceed it fails with a clear reason
# instead of a raw Firestore error the client cannot interpret.
MAX_PREDICTIONS_BYTES = 900_000


def is_local(job_id: str) -> bool:
    """Did this job run here rather than at Hume?"""
    return job_id.startswith(LOCAL_PREFIX)


def new_id(unique: str) -> str:
    """A local job id. `unique` is supplied by the caller so this stays pure."""
    return f"{LOCAL_PREFIX}{unique}"


async def create(settings: Settings, job_id: str, *, now: datetime) -> None:
    """Record a job as started."""
    await get_store(settings).voice_jobs.put(
        {
            "id": job_id,
            "status": IN_PROGRESS,
            "createdAt": now.isoformat(),
        }
    )


async def complete(
    settings: Settings, job_id: str, *, predictions: list, now: datetime
) -> None:
    """Store a finished job's predictions.

    Predictions are serialised to a JSON string rather than stored as nested
    arrays: Firestore cannot index or store arrays-of-arrays beyond a shallow
    depth, and Hume's envelope is deeply nested. The string round-trips exactly,
    which is what the client needs.
    """
    encoded = json.dumps(predictions, separators=(",", ":"))
    if len(encoded.encode()) > MAX_PREDICTIONS_BYTES:
        await fail(
            settings,
            job_id,
            error="Voice analysis produced more data than can be stored.",
            now=now,
        )
        logger.error("voice job %s exceeded the document limit", job_id)
        return

    await get_store(settings).voice_jobs.put(
        {
            "id": job_id,
            "status": COMPLETED,
            "predictions": encoded,
            "createdAt": now.isoformat(),
        }
    )


async def fail(settings: Settings, job_id: str, *, error: str, now: datetime) -> None:
    """Record a job as failed, with a reason the client can display."""
    await get_store(settings).voice_jobs.put(
        {
            "id": job_id,
            "status": FAILED,
            "error": error[:500],
            "createdAt": now.isoformat(),
        }
    )


async def get(settings: Settings, job_id: str, *, now: datetime) -> dict | None:
    """A job, or None if unknown or expired.

    Expiry is applied on read rather than by a scheduled sweep: a job past its TTL
    is indistinguishable to the client from one that never existed, and both mean
    "stop polling".
    """
    doc = await get_store(settings).voice_jobs.get(job_id)
    if not doc:
        return None

    created = _parse_time(doc.get("createdAt"))
    if created is not None and now - created > TTL:
        return None
    return doc


def predictions_of(job: dict) -> list:
    """A completed job's predictions, decoded. Empty if unreadable.

    Empty rather than raising: the alternative is a 500 on the client's final poll
    after the analysis actually succeeded, which loses the result either way but
    also looks like a server fault.
    """
    raw = job.get("predictions")
    if not raw:
        return []
    try:
        decoded = json.loads(raw)
    except (TypeError, ValueError):
        logger.error("voice job %s has unreadable predictions", job.get("id"))
        return []
    return decoded if isinstance(decoded, list) else []


def _parse_time(value: object) -> datetime | None:
    """An ISO timestamp, or None. Tolerates a naive value by assuming UTC."""
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
