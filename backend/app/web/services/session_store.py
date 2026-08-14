"""Loading, saving and settling a session — the shared plumbing of the session routes.

Ports the helpers at the top of `server/routes/sessions.ts` (`load`, `settle`,
`maybeScore`).

`settle` is the one that carries weight. Every read and every write ticks the clock
first, so a candidate who closed their laptop mid-answer comes back to a session that
has already advanced through the boundaries they missed — and a client cannot avoid a
deadline by simply not asking.

Scoring is fire-and-forget on completion, deduplicated by an in-flight set. That set is
process-local, which is a deliberate limitation: with several workers, two could score
the same session concurrently. The write is idempotent (same session id, last writer
wins) so the outcome is a wasted model call rather than a wrong report — noted here so
it is a known cost rather than a surprise.
"""

from __future__ import annotations

import asyncio
import logging

from fastapi import HTTPException, status

from app.config import Settings
from app.security import AuthedUser
from app.web.deps import NotFound, is_assigned_candidate, owns
from app.web.services import invite_bridge, scoring, timing
from app.web.store import get_store

logger = logging.getLogger("web.session_store")

# Sessions being scored right now, so a burst of completion requests does not fire
# several model calls for one interview.
_scoring_in_flight: set[str] = set()


async def load(
    settings: Settings, session_id: str, user: AuthedUser
) -> tuple[dict, dict]:
    """A session the caller may act on, with its template.

    Access is the assigned candidate (matched on their VERIFIED email) or the owning
    recruiter — the owner is included so they can preview their own interview end to
    end. Anyone else gets 404, including another recruiter, so a response never reveals
    that a session they cannot see exists.
    """
    store = get_store(settings)

    session = await store.sessions.get(session_id)
    if not session:
        raise NotFound("Session")

    if not (is_assigned_candidate(session, user) or owns(session, user)):
        raise NotFound("Session")

    template = await store.templates.get(session.get("templateId") or "")
    if not template:
        # A session whose template was deleted cannot run: the questions, timing and
        # rubric all live there.
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, "Template for session not found"
        )

    return session, template


async def settle(settings: Settings, session: dict, template: dict) -> None:
    """Tick the clock, persist any change, and start scoring if it just finished.

    Called on every read and write. That is what makes the timing tamper-proof — a
    client that stops polling to avoid a deadline still finds it applied the moment it
    asks for anything.
    """
    if timing.tick(session, template):
        await get_store(settings).sessions.put(session)

    await maybe_score(settings, session, template)


async def maybe_score(settings: Settings, session: dict, template: dict) -> None:
    """Score a completed session, once.

    Fire-and-forget: the candidate has finished and should not wait on a model call to
    be told so. The report appears when it appears, and the recruiter's list shows the
    session as completed-but-unscored until then.
    """
    if session.get("status") != "completed":
        return

    session_id = session.get("id") or ""
    if not session_id or session_id in _scoring_in_flight:
        return

    store = get_store(settings)
    if await store.reports.get(session_id):
        return

    _scoring_in_flight.add(session_id)
    asyncio.ensure_future(_score(settings, session, template))


async def _score(settings: Settings, session: dict, template: dict) -> None:
    """Produce and store the report. Never raises — nothing is awaiting it."""
    session_id = session["id"]
    try:
        report = await scoring.score_session(settings, session, template)
        await get_store(settings).reports.put(report)
        # Bulk-invite sessions push the score back to their Firestore interview so the
        # recruiter and the Flutter app both see it.
        await invite_bridge.sync_result(settings, session, report)
        logger.info("scored session %s (%s)", session_id, report.get("overallScore"))
    except Exception as exc:  # noqa: BLE001 - a failed report must not crash a task
        logger.error("scoring failed for %s: %s", session_id, exc)
    finally:
        _scoring_in_flight.discard(session_id)


async def save(settings: Settings, session: dict) -> None:
    await get_store(settings).sessions.put(session)
