"""`GET /api/web/analytics` — the recruiter dashboard. Ports `server/routes/analytics.ts`.

Real aggregates over stored reports. Every filter is optional, and no matches produces
zeros and empty arrays rather than sampled or invented data.

**Scoped to the requesting recruiter.** The Express version widened this for admins; role
gating is deferred, so every caller sees only their own sessions. That is the safer of
the two defaults — a company-wide average that silently included another recruiter's
candidates would be wrong in a way nobody would notice.
"""

from __future__ import annotations

import asyncio
import logging

from fastapi import APIRouter, Query, Request

from app.security import AuthedUser
from app.web.deps import WebUser, settings_of
from app.web.services import analytics
from app.web.store import get_store

logger = logging.getLogger("web.analytics")

router = APIRouter(prefix="/analytics", tags=["web:analytics"])


@router.get("", summary="Aggregate hiring metrics")
async def summary(
    request: Request,
    track: str = Query(default=""),
    templateId: str = Query(default=""),
    role: str = Query(default=""),
    dateFrom: str = Query(default=""),
    dateTo: str = Query(default=""),
    user: AuthedUser = WebUser,
) -> dict:
    store = get_store(settings_of(request))

    # The recruiter's own sessions, plus every template (shared, so a session may use one
    # this recruiter did not author) and the reports for those sessions.
    sessions, templates = await asyncio.gather(
        store.sessions.owned_by(user.uid),
        store.templates.all(),
    )

    # Reports are fetched concurrently rather than in a loop: at roughly 60ms per round
    # trip, a recruiter with 200 sessions would otherwise wait twelve seconds.
    session_ids = [session["id"] for session in sessions if session.get("id")]
    reports = await asyncio.gather(*(store.reports.get(i) for i in session_ids))

    return analytics.compute(
        sessions,
        {template["id"]: template for template in templates if template.get("id")},
        {
            session_id: report
            for session_id, report in zip(session_ids, reports)
            if report
        },
        filters={
            "track": track or None,
            "templateId": templateId or None,
            "role": role or None,
            "dateFrom": dateFrom or None,
            "dateTo": dateTo or None,
        },
        owner_id=user.uid,
    )
