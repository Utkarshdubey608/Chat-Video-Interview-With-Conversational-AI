"""The AI proxy: the app's vendor calls, re-homed onto credentials held here.

Every route is a thin adapter — validate, delegate to a provider, return. There
is no try/except: providers raise `ProviderNotConfigured` / `UpstreamError` and
`app.main` turns those into responses.

All routes require a verified Firebase user. That is the only thing standing
between these endpoints and anyone on the internet spending the org's quota, so
`require_firebase_user` is applied to the whole router rather than per-route,
where a new endpoint could forget it.
"""

from __future__ import annotations

from fastapi import APIRouter, Body, Depends, HTTPException, Request, status

from app.config import Settings
from app.providers.deepgram import DEFAULT_LANGUAGE, DEFAULT_MODEL, DeepgramClient
from app.providers.gemini import GeminiClient
from app.providers.tavus import TavusClient
from app.ratelimit import RateLimitGenerate, RateLimitMedia
from app.security import require_firebase_user

router = APIRouter(
    prefix="/api",
    tags=["ai"],
    dependencies=[Depends(require_firebase_user)],
)

# Audio is bounded so a single request cannot exhaust memory. An hour of 16 kHz
# mono PCM is roughly 115 MB; interviews are shorter and usually compressed, so
# 64 MB is generous.
MAX_AUDIO_BYTES = 64 * 1024 * 1024

# A generateContent body carries a transcript and sometimes a base64 PDF.
MAX_GEMINI_BODY_BYTES = 12 * 1024 * 1024


def _settings(request: Request) -> Settings:
    return request.app.state.settings


# ── Tavus ─────────────────────────────────────────────────────────────────────
@router.get("/tavus/replicas", summary="Custom + stock replicas, merged")
async def tavus_replicas(request: Request) -> dict:
    return {"data": await TavusClient(_settings(request)).list_replicas()}


@router.get("/tavus/personas", summary="Available personas")
async def tavus_personas(request: Request) -> dict:
    return {"data": await TavusClient(_settings(request)).list_personas()}


@router.post(
    "/tavus/conversations",
    summary="Start an avatar conversation",
    dependencies=[RateLimitMedia],
)
async def tavus_create_conversation(request: Request, payload: dict = Body(...)) -> dict:
    # The response carries the Daily room URL the device joins directly — the
    # only part of the video interview this service never sees.
    return await TavusClient(_settings(request)).create_conversation(payload)


@router.get("/tavus/conversations/{conversation_id}", summary="Conversation status")
async def tavus_get_conversation(request: Request, conversation_id: str) -> dict:
    return await TavusClient(_settings(request)).get_conversation(conversation_id)


@router.get(
    "/tavus/conversations/{conversation_id}/verbose",
    summary="Conversation with its server-side transcript",
)
async def tavus_get_conversation_verbose(request: Request, conversation_id: str) -> dict:
    return await TavusClient(_settings(request)).get_conversation(
        conversation_id, verbose=True
    )


@router.post("/tavus/conversations/{conversation_id}/end", summary="End the live call")
async def tavus_end_conversation(request: Request, conversation_id: str) -> dict:
    return await TavusClient(_settings(request)).end_conversation(conversation_id)


@router.post(
    "/tavus/conversations/{conversation_id}/interactions",
    summary="Overwrite the live conversation context",
)
async def tavus_send_interaction(
    request: Request,
    conversation_id: str,
    payload: dict = Body(...),
) -> dict:
    text = str(payload.get("text") or "").strip()
    if not text:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "`text` is required.")
    return await TavusClient(_settings(request)).send_interaction(conversation_id, text)


# ── Gemini (REST) ─────────────────────────────────────────────────────────────
@router.post(
    "/gemini/generate",
    summary="One generateContent call",
    dependencies=[RateLimitGenerate],
)
async def gemini_generate(
    request: Request,
    body: dict = Body(...),
    model: str | None = None,
) -> dict:
    """Scoring, question generation, résumé extraction, adaptive turns, the guide.

    One route rather than one per purpose: every caller hits the same upstream
    endpoint and differs only in its prompt, so splitting them would add routes
    without adding meaning.

    `?model=` is an ALLOWLIST, not free choice — recruiters may pick between
    flash and pro, but a client cannot redirect spend onto an arbitrary model.
    Anything unrecognised silently falls back to the default.
    """
    if not isinstance(body.get("contents"), list) or not body["contents"]:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "`contents` must be a non-empty list, as required by generateContent.",
        )

    if len(await request.body()) > MAX_GEMINI_BODY_BYTES:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            "Request body is too large.",
        )

    return await GeminiClient(_settings(request)).generate_content(body, model=model)


# ── Deepgram ──────────────────────────────────────────────────────────────────
@router.post(
    "/deepgram/transcribe",
    summary="Transcribe recorded audio",
    dependencies=[RateLimitMedia],
)
async def deepgram_transcribe(
    request: Request,
    model: str = DEFAULT_MODEL,
    language: str = DEFAULT_LANGUAGE,
) -> dict:
    """Audio arrives as the raw request body, matching Deepgram's own API."""
    audio = await request.body()
    if not audio:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "Request body must contain audio."
        )
    if len(audio) > MAX_AUDIO_BYTES:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Audio file is too large."
        )

    return await DeepgramClient(_settings(request)).transcribe(
        audio,
        content_type=request.headers.get("content-type") or "audio/wav",
        model=model,
        language=language,
    )
