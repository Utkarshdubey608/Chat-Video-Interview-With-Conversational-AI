"""Live transcription relays — ports `server/services/deepgramRelay.ts`.

Two sockets, one relay. The browser streams its MediaRecorder chunks here, we forward
them to Deepgram with the API key attached server-side, and Deepgram's JSON results go
straight back. **The key never reaches the client.**

**Why this is a relay and not a token.** Everywhere else on this surface the browser gets
a short-lived credential and connects to the vendor directly — that is how the Gemini
Live tracks work. Deepgram cannot: this project's key is not permitted to mint temporary
tokens (`/v1/auth/grant` answers "Insufficient permissions"), so the only way to keep the
key server-side is to sit in the middle. That is a vendor constraint, not a design
preference.

Two entry points because the two callers are different people. `/avatar/deepgram` is the
recruiter's own screening tool; `/interview/deepgram` is the candidate's video interview.
They share every byte of behaviour and differ only in who may open them.

**Frame types are preserved exactly.** Deepgram sends its results as TEXT frames. Relaying
them as binary — which is what happens if you treat every message as bytes — turns the
JSON into an ArrayBuffer the browser's `JSON.parse` chokes on, and the symptom is a
transcript that silently never commits. The Express version hit exactly this.
"""

from __future__ import annotations

import asyncio
import logging
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, Query, WebSocket, WebSocketDisconnect

from app.config import Settings
from app.security import require_firebase_user
from app.web.deps import settings_of

logger = logging.getLogger("web.ws.deepgram")

router = APIRouter(tags=["web:realtime"])

DEEPGRAM_URL = "wss://api.deepgram.com/v1/listen"

# Matches the Express parameters exactly. `interim_results` is what makes captions appear
# as the candidate speaks rather than after each utterance; `filler_words` is deliberate —
# the speech metrics count fillers, so Deepgram must not helpfully remove them.
DEEPGRAM_PARAMS = {
    "model": "nova-3",
    "language": "en-US",
    "punctuate": "true",
    "smart_format": "true",
    "interim_results": "true",
    "utterance_end_ms": "1000",
    "vad_events": "true",
    "filler_words": "true",
}

# WebSocket close codes.
_INTERNAL_ERROR = 1011
_POLICY_VIOLATION = 1008

# Bounds a single frame. MediaRecorder chunks are tens of kilobytes; anything far larger
# is a client fault and should not be forwarded to a metered vendor.
MAX_FRAME_BYTES = 1024 * 1024


def upstream_url() -> str:
    return f"{DEEPGRAM_URL}?{urlencode(DEEPGRAM_PARAMS)}"


async def ws_user(
    websocket: WebSocket,
    token: str = Query(default=""),
    access_token: str = Query(default=""),
):
    """Verify the caller before the socket is accepted. None when unauthenticated.

    The token rides in the query string because a browser cannot set an `Authorization`
    header on a WebSocket handshake. That is a platform limitation, not a shortcut — and
    it is why this runs BEFORE `accept()`, so an unauthenticated caller never holds an
    open connection.

    A real dependency rather than a plain call, so a test can override it the same way it
    overrides the HTTP one. `web_user_from_query` had to call `require_firebase_user`
    directly and needs its own override for exactly this reason.

    Returns None instead of raising: in a WebSocket context the route decides the close
    code, and a clean 1008 is more useful to a client than a dropped handshake.
    """
    supplied = (token or access_token or "").strip()
    if not supplied:
        return None
    try:
        return await require_firebase_user(websocket, f"Bearer {supplied}")
    except Exception as exc:  # noqa: BLE001 - every failure here is an auth failure
        logger.info("deepgram relay rejected a token: %s", type(exc).__name__)
        return None


async def relay(websocket: WebSocket, settings: Settings) -> None:
    """Pump audio up and results back until either side closes."""
    import websockets

    key = settings.deepgram_api_key.strip()
    if not key:
        await websocket.close(code=_INTERNAL_ERROR, reason="Deepgram not configured")
        return

    await websocket.accept()

    try:
        upstream = await websockets.connect(
            upstream_url(),
            additional_headers={"Authorization": f"Token {key}"},
            # Deepgram's frames are small; the default limits are fine, but an explicit
            # ping keeps the connection alive through a proxy during a long silence.
            ping_interval=20,
            ping_timeout=20,
        )
    except Exception as exc:  # noqa: BLE001 - the caller gets a clean close, not a hang
        logger.error("could not reach Deepgram: %s", exc)
        await websocket.close(code=_INTERNAL_ERROR, reason="Transcription unavailable")
        return

    async with upstream:
        # Both directions run concurrently and the first to finish ends the other. A
        # sequential pump would deadlock: neither side speaks on a schedule.
        to_deepgram = asyncio.create_task(_client_to_upstream(websocket, upstream))
        to_client = asyncio.create_task(_upstream_to_client(websocket, upstream))

        done, pending = await asyncio.wait(
            {to_deepgram, to_client}, return_when=asyncio.FIRST_COMPLETED
        )
        for task in pending:
            task.cancel()
        for task in done:
            exc = task.exception()
            if exc and not isinstance(exc, WebSocketDisconnect):
                logger.info("deepgram relay ended: %s", type(exc).__name__)

    try:
        await websocket.close()
    except RuntimeError:
        # Already closed by the disconnect that ended the pump.
        pass


async def _client_to_upstream(websocket: WebSocket, upstream) -> None:
    """Browser → Deepgram. Audio arrives as binary; control messages as text."""
    while True:
        message = await websocket.receive()

        if message["type"] == "websocket.disconnect":
            # Tell Deepgram the stream is over so it flushes its final result rather
            # than dropping the tail of what the candidate said.
            await upstream.close()
            return

        data = message.get("bytes")
        if data is not None:
            if len(data) > MAX_FRAME_BYTES:
                logger.info("dropped an oversized audio frame (%d bytes)", len(data))
                continue
            await upstream.send(data)
            continue

        text = message.get("text")
        if text is not None:
            # The client sends `{"type":"CloseStream"}` to finalise. Forwarded as TEXT,
            # because Deepgram parses control messages as JSON.
            await upstream.send(text)


async def _upstream_to_client(websocket: WebSocket, upstream) -> None:
    """Deepgram → browser, preserving the frame type.

    `websockets` yields `str` for text frames and `bytes` for binary, so the distinction
    survives if — and only if — each is sent back through the matching method.
    """
    async for message in upstream:
        if isinstance(message, str):
            await websocket.send_text(message)
        else:
            await websocket.send_bytes(message)


@router.websocket("/avatar/deepgram")
async def avatar_deepgram(websocket: WebSocket, user=Depends(ws_user)) -> None:
    """The recruiter's AI-screening transcription.

    ROLE-GATING: recruiter-only in Express. Deferred with the rest — any authenticated
    caller is accepted, and the cost is bounded by the same Deepgram key either way.
    """
    if user is None:
        await websocket.close(code=_POLICY_VIOLATION, reason="Authentication required")
        return

    await relay(websocket, settings_of(websocket))


@router.websocket("/interview/deepgram")
async def interview_deepgram(websocket: WebSocket, user=Depends(ws_user)) -> None:
    """The candidate's video-interview transcription.

    Open to any authenticated caller by design — this one is used BY candidates, so a
    recruiter-only guard would lock out its actual users.
    """
    if user is None:
        await websocket.close(code=_POLICY_VIOLATION, reason="Authentication required")
        return

    await relay(websocket, settings_of(websocket))
