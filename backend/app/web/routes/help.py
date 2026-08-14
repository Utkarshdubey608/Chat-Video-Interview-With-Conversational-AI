"""Mimic Guide — chat, Autopilot, and speech. Ports `server/routes/help.ts`.

Open to both roles: recruiters and candidates use the same assistant, and the
caller's role only decides which pages the answers link to.

`/chat` and `/agent` **always return 200**, even on a validation or model failure.
That is deliberate: this is a chat window, and an error status turns it into a dead
box the user cannot recover from without a reload. Both degrade to a friendly reply
instead, and the real error is logged. Raw exception text is never returned.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Request

from app.providers.gemini import GeminiClient, rfc3339
from app.security import AuthedUser
from app.web.deps import RateLimitChat, RateLimitLiveTokenWeb, WebUser, settings_of
from app.web.schemas import (
    AgentRequest,
    GuideChatRequest,
    GuideChatResponse,
    LiveTokenGrant,
    TtsRequest,
)
from app.web.services import autopilot_agent, guide_speech, mimic_guide, users
from app.web.store import defaults

logger = logging.getLogger("web.help")

router = APIRouter(prefix="/help", tags=["web:help"])

GENERIC_ERROR = "Something went wrong. Please try again."


@router.post(
    "/chat",
    response_model=GuideChatResponse,
    summary="Ask Mimic Guide",
    dependencies=[RateLimitChat],
)
async def chat(
    body: GuideChatRequest, request: Request, user: AuthedUser = WebUser
) -> GuideChatResponse:
    settings = settings_of(request)
    try:
        role = await users.get_role(settings, user.uid)
        reply = await mimic_guide.run(
            settings,
            [message.model_dump() for message in body.messages],
            role,
        )
        return GuideChatResponse(reply=reply)
    except Exception:  # noqa: BLE001 - the chat must never become a dead box
        logger.exception("mimic guide chat failed")
        return GuideChatResponse(reply=GENERIC_ERROR)


@router.post(
    "/agent",
    summary="Autopilot: decide one next action",
    dependencies=[RateLimitChat],
)
async def agent(
    body: AgentRequest, request: Request, user: AuthedUser = WebUser
) -> dict:
    """Choose ONE action for the caller's current screen, or ask a question.

    Same auth as `/chat` — the actions themselves are gated where they execute,
    client and server side, not here.

    The response is a bare dict rather than a model because its shape is
    conditional: `action` is present only when a registered action was chosen. A
    response model would have to make it optional-and-null, which is a different
    payload than the client expects.
    """
    settings = settings_of(request)
    try:
        return await autopilot_agent.run(settings, body.model_dump())
    except Exception:  # noqa: BLE001 - a failed turn must still return a decision
        logger.exception("autopilot turn failed")
        return {"say": GENERIC_ERROR, "awaitingUser": True}


@router.post(
    "/tts-token",
    response_model=LiveTokenGrant,
    summary="Mint a locked token for speaking one answer aloud",
    dependencies=[RateLimitLiveTokenWeb],
)
async def tts_token(
    body: TtsRequest, request: Request, user: AuthedUser = WebUser
) -> LiveTokenGrant:
    """A credential for reading one assistant reply aloud.

    Replaces the Express `/help/tts`, which opened a Gemini Live session on the
    server and streamed newline-delimited base64 PCM back through it. Here the
    browser connects to Google directly with a token that has the whole session
    locked into it — the same mechanism the mobile app already uses for its voice
    interview and voice picker.

    What the lock buys: the text, the language, the voice and the model are fixed at
    mint time with no `fieldMask`, so a tampered client cannot turn a
    read-this-aloud session into an open-ended chat on the org's quota. The
    instruction is also defensive about its own payload — a guide answer may itself
    be a question, and it must be spoken rather than answered.

    Three things bound the cost: the session cap in settings, the single `uses` on
    the token, and this route's share of the live-token rate limit.
    """
    settings = settings_of(request)

    setup = guide_speech.build_speech_setup(
        text=body.text,
        lang=body.lang,
        # The same voice as the interview tracks, so the assistant sounds like the
        # rest of the product. Validated against the catalog, so a stale default
        # cannot mint a setup Google will reject on connect.
        voice=_speech_voice(),
        model=settings.live_model_name,
    )

    token = await GeminiClient(settings).mint_live_token(
        setup, session_minutes=settings.gemini_speech_session_minutes
    )
    return LiveTokenGrant(
        token=token.token,
        wsUrl=token.ws_url,
        model=token.model,
        expiresAt=rfc3339(token.expires_at),
        connectBy=rfc3339(token.connect_by),
    )


def _speech_voice() -> str:
    """The guide's voice: the product default, checked against the catalog."""
    configured = defaults.default_voice_config()["voiceId"]
    return configured if defaults.find_voice(configured) else "Aoede"
