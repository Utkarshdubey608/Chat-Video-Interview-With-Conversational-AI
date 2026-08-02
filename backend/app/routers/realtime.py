"""`POST /api/rt/gemini-token` — a short-lived token for one Live voice session.

This is the only route that hands the client a credential, and it is deliberately
narrow: the caller names an interview, nothing else. Model, voice, and the
interviewer's system instruction are resolved from the interview document and
locked into the token, so the device cannot influence the session it is about to
open — see `app.providers.gemini` for why that lock holds.

Flow: verify the caller → load the interview → check assignment → check the
launch window → assemble the setup → mint.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app import interviews, voice
from app.config import Settings
from app.firebase import FirestoreUnavailable
from app.interviews import (
    InterviewAccessDenied,
    InterviewNotFound,
    InterviewNotLaunchable,
)
from app.providers.gemini import GeminiClient, rfc3339
from app.ratelimit import RateLimitLiveToken
from app.schemas import LiveTokenRequest, LiveTokenResponse
from app.security import AuthedUser, require_firebase_user

router = APIRouter(prefix="/api/rt", tags=["realtime"])


def _settings(request: Request) -> Settings:
    return request.app.state.settings


@router.post(
    "/gemini-token",
    response_model=LiveTokenResponse,
    response_model_by_alias=True,
    summary="Mint a locked Gemini Live token for an assigned interview",
    dependencies=[RateLimitLiveToken],
)
async def gemini_token(
    payload: LiveTokenRequest,
    request: Request,
    user: AuthedUser = Depends(require_firebase_user),
) -> LiveTokenResponse:
    settings = _settings(request)

    try:
        interview = interviews.fetch(settings, payload.interview_id)
    except InterviewNotFound as exc:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(exc)) from exc
    except FirestoreUnavailable as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(exc)) from exc

    try:
        # Assignment first, then eligibility: someone with no claim on this
        # interview should not learn whether it has expired.
        interviews.require_candidate(interview, uid=user.uid, email=user.email)
        interview.ensure_launchable()
    except InterviewAccessDenied as exc:
        raise HTTPException(status.HTTP_403_FORBIDDEN, str(exc)) from exc
    except InterviewNotLaunchable as exc:
        raise HTTPException(status.HTTP_409_CONFLICT, str(exc)) from exc

    setup = voice.build_live_setup(interview, model=settings.live_model_name)

    # The session may run for the interview's own length plus a grace period, so
    # a candidate is never cut off mid-answer by the token rather than by the
    # interview's own duration cap.
    session_minutes = (
        max(interview.duration_minutes, 1) + settings.gemini_token_expiry_buffer_minutes
    )

    token = await GeminiClient(settings).mint_live_token(
        setup, session_minutes=session_minutes
    )
    return LiveTokenResponse(
        token=token.token,
        ws_url=token.ws_url,
        model=token.model,
        expires_at=rfc3339(token.expires_at),
        connect_by=rfc3339(token.connect_by),
    )
