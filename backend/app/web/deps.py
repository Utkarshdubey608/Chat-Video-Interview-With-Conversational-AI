"""Authentication, authorization and rate-limit buckets for the web surface.

Ports `server/middleware/auth.ts`. Three groups:

*Identity* — `WebUser` resolves a verified Firebase ID token, reusing the shared
`require_firebase_user`. `web_user_from_query` additionally accepts `?token=`,
because a browser cannot set an `Authorization` header on a WebSocket handshake
or on a `<video>` tag's request (ports `contextFromUpgrade`).

*Ownership* — `assert_owner` / `assert_participant`. These are the real access
boundary and are NOT optional; see the note below.

*Cost* — the rate-limit buckets the web routes need, built on the shared
`limit_by_user` factory. They live here rather than in `app.ratelimit` so the
kernel stays unaware of the web surface.
"""

from __future__ import annotations

import logging

from fastapi import Depends, HTTPException, Query, Request, status

from app.config import Settings
from app.ratelimit import Rule, limit_by_user
from app.security import AuthedUser, require_firebase_user

logger = logging.getLogger("web.deps")


# ── identity ──────────────────────────────────────────────────────────────────

WebUser = Depends(require_firebase_user)
"""A verified Firebase user. Use as `user: AuthedUser = WebUser`.

ROLE-GATING: deliberately no role check. The Express server wrapped most routers
in `requireRecruiter`; that is deferred (see this package's README). Ownership
checks below are what stop cross-tenant access, and they are mandatory.
"""


async def web_user_from_query(
    request: Request,
    token: str | None = Query(default=None),
    access_token: str | None = Query(default=None),
) -> AuthedUser:
    """A verified user, accepting the token in the query string as a fallback.

    Only for the two callers that genuinely cannot send a header: the WebSocket
    upgrades and the replica-preview cache (a `<video>` src). Everything else
    uses `WebUser` — a token in a URL lands in access logs, browser history and
    `Referer`, so this is a concession to the platform, not a convenience.
    """
    authorization = request.headers.get("authorization")
    if authorization:
        return await require_firebase_user(request, authorization)

    supplied = (token or access_token or "").strip()
    if not supplied:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return await require_firebase_user(request, f"Bearer {supplied}")


WebUserFromQuery = Depends(web_user_from_query)


# ── ownership ─────────────────────────────────────────────────────────────────
#
# Ports `ownsSession` / `isAssignedCandidate` / `assertOwner` /
# `assertSessionParticipant` from server/middleware/auth.ts.
#
# These are NOT the same thing as role gating, and dropping role gating must not
# drop these. Without them any signed-in user could read any recruiter's sessions,
# candidates and reports. Note that `app.interviews.require_recruiter` on the
# common surface is also an OWNERSHIP check despite its name.
#
# Cross-tenant access is reported as 404, never 403, so a response never reveals
# that a record the caller cannot see exists.


class NotFound(HTTPException):
    """404 used for both 'missing' and 'not yours' — see above."""

    def __init__(self, what: str = "Session") -> None:
        super().__init__(status.HTTP_404_NOT_FOUND, f"{what} not found")


def owns(doc: dict | None, user: AuthedUser) -> bool:
    """Does this user own the record?

    The blank check matters: documents written before ownership was stamped have
    an empty `recruiterId`, and `"" == ""` would hand every one of them to any
    caller whose uid failed to resolve.
    """
    if not doc:
        return False
    recruiter_id = str(doc.get("recruiterId") or "")
    return bool(recruiter_id) and bool(user.uid) and recruiter_id == user.uid


def is_assigned_candidate(session: dict | None, user: AuthedUser) -> bool:
    """Is this the candidate the session is assigned to?

    Assignment is by email, matched case-insensitively, because the app never
    stores a candidate uid — the invite is created before they have an account.
    The email comes from the verified ID token, not from the request.
    """
    if not session:
        return False
    candidate = session.get("candidate")
    assigned = ""
    if isinstance(candidate, dict):
        assigned = str(candidate.get("email") or "").strip().lower()
    if not assigned:
        assigned = str(session.get("candidateEmailLower") or "").strip().lower()
    caller = (user.email or "").strip().lower()
    return bool(assigned) and bool(caller) and assigned == caller


def assert_owner(doc: dict | None, user: AuthedUser, *, what: str = "Session") -> dict:
    """Return the record if this user owns it, else 404."""
    if not owns(doc, user):
        raise NotFound(what)
    assert doc is not None  # narrowed by owns()
    return doc


def assert_participant(
    session: dict | None, user: AuthedUser, *, what: str = "Session"
) -> dict:
    """Return the session if the caller may act on it, else 404.

    The assigned candidate, or the owning recruiter — the owner is included so a
    recruiter can preview their own interview end to end.
    """
    if is_assigned_candidate(session, user) or owns(session, user):
        assert session is not None
        return session
    raise NotFound(what)


# ── rate limiting ─────────────────────────────────────────────────────────────
#
# Built on the shared factory so the counting, logging and Retry-After behaviour
# are identical to the common surface. Separate buckets so a burst of one kind of
# call cannot block another: a recruiter regenerating scorecards must not stop a
# candidate starting their interview.
#
# The cheap session-engine routes — state polls, draft saves, timing ticks,
# integrity events, track selection — take NO bucket. They touch Firestore, not a
# paid vendor, and putting them in a vendor bucket would throttle real interviews.

RateLimitFace = Depends(
    limit_by_user(
        "web-face",
        lambda s: Rule(s.rate_limit_face, s.rate_limit_window_seconds),
    )
)
"""Facial-analysis frames. The browser captures one every 8 seconds
(`src/services/rekognitionService.ts`), so ~7.5/min per candidate — the ceiling
is well clear of normal use and exists to stop a hot loop."""

RateLimitChat = Depends(
    limit_by_user(
        "web-chat",
        lambda s: Rule(s.rate_limit_chat, s.rate_limit_window_seconds),
    )
)
"""Mimic Guide chat and its text-to-speech. A person typing cannot approach the
ceiling; a retry loop can."""

RateLimitLiveTokenWeb = Depends(
    limit_by_user(
        "web-live-token",
        lambda s: Rule(s.rate_limit_live_token, s.rate_limit_window_seconds),
    )
)
"""Minting a Gemini Live token hands the browser a real credential.

Shares the `rate_limit_live_token` ceiling with the common surface but counts in its
own bucket, so a recruiter auditioning voices in the browser cannot exhaust the
budget a candidate needs to launch an interview on their phone."""

RateLimitGenerateWeb = Depends(
    limit_by_user(
        "web-generate",
        lambda s: Rule(s.rate_limit_generate, s.rate_limit_window_seconds),
    )
)
"""Model calls that bill per request: question generation from a résumé, scoring,
and the sentiment read.

Shares the `rate_limit_generate` ceiling with the common surface but counts in its
own bucket, so a recruiter regenerating question sets cannot consume the budget a
finished interview needs to be scored."""

RateLimitMediaWeb = Depends(
    limit_by_user(
        "web-media",
        lambda s: Rule(s.rate_limit_media, s.rate_limit_window_seconds),
    )
)
"""Audio and upload routes: voice previews, résumé uploads, avatar conversation
starts.

Shares the `rate_limit_media` ceiling with the common surface but counts in its
OWN bucket, so a recruiter previewing voices in the browser cannot consume the
budget a candidate needs to start an interview on their phone."""


def settings_of(request: Request) -> Settings:
    """Settings off app.state — the same accessor the common routers use."""
    return request.app.state.settings
