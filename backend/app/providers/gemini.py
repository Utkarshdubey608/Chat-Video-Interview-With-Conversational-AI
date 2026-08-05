"""Google Gemini — ephemeral Live tokens, and (Phase 3) REST generateContent.

Two surfaces, two API versions, both verified against the live service:

* **mint** — ``POST v1beta/auth_tokens``
* **connect** — ``wss://…v1alpha…BidiGenerateContentConstrained?access_token=…``

The wire field names are NOT the ones in Google's SDK documentation. The REST
``AuthToken`` message (per the API discovery document) is::

    name · expireTime · uses · newSessionExpireTime · fieldMask
    · bidiGenerateContentSetup · interactionId

There is no ``liveConnectConstraints`` and no ``lockAdditionalFields``; sending
either returns 400. Locking is expressed through ``bidiGenerateContentSetup``
plus ``fieldMask``:

===================  =======================================================
``fieldMask``        Effect
===================  =======================================================
omitted              effective setup taken **entirely** from the token —
                     the client's setup frame is **ignored**
present              only the masked fields overwrite the client's setup
===================  =======================================================

We always omit it. That full lock is what makes it safe to hand the token to a
candidate's device: a tampered client cannot replace the interviewer's
instructions. Do not add a ``fieldMask`` without re-running
``spikes/gemini_token_lock.py``.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from app.providers.base import ProviderClient, UpstreamError

logger = logging.getLogger("providers.gemini")

# Minting is v1beta; the token-authenticated socket is v1alpha. Not a typo.
_MINT_BASE = "https://generativelanguage.googleapis.com/v1beta"
LIVE_WS_URL = (
    "wss://generativelanguage.googleapis.com/ws/"
    "google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained"
)

# Google caps how far ahead a session may be opened.
_MAX_CONNECT_WINDOW = timedelta(hours=20)

# Applied to every generateContent call when the caller omits them, matching
# GeminiService.safetySettings in the app. An interview transcript discussing,
# say, a security incident should not be blocked as dangerous content.
DEFAULT_SAFETY_SETTINGS = [
    {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_ONLY_HIGH"},
    {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_ONLY_HIGH"},
    {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_ONLY_HIGH"},
    {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_ONLY_HIGH"},
]


def rfc3339(value: datetime) -> str:
    """Google's timestamp format, and what the app parses back."""
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


@dataclass(frozen=True)
class LiveToken:
    """A minted token plus everything the client needs to use it.

    Times stay as `datetime` — turning them into the API's wire shape is the
    router's job, so this module stays pure transport.
    """

    token: str
    ws_url: str
    model: str
    expires_at: datetime
    connect_by: datetime


class GeminiClient(ProviderClient):
    name = "Gemini"
    env_var = "GEMINI_API_KEY"
    base_url = _MINT_BASE

    @property
    def api_key(self) -> str:
        return self.settings.gemini_api_key

    def auth_headers(self) -> dict[str, str]:
        return {"x-goog-api-key": self.api_key.strip()}

    async def mint_live_token(
        self,
        setup: dict,
        *,
        session_minutes: int,
        uses: int = 1,
    ) -> LiveToken:
        """Mint a token locked to `setup`.

        `session_minutes` bounds how long the session may run; the connect window
        comes from settings and bounds how long the client has to *open* it.

        `uses` defaults to 1. Resuming a Live session does not count as a use, so
        one token covers an interview that reconnects mid-way.
        """
        self.require_configured()

        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(minutes=max(session_minutes, 1))
        connect_by = now + min(
            timedelta(seconds=self.settings.gemini_token_connect_window_seconds),
            _MAX_CONNECT_WINDOW,
        )

        payload = {
            "uses": uses,
            "expireTime": rfc3339(expires_at),
            "newSessionExpireTime": rfc3339(connect_by),
            # No fieldMask ⇒ FULL LOCK. See the module docstring.
            "bidiGenerateContentSetup": setup,
        }

        response = await self.request("POST", "/auth_tokens", json=payload)
        token = (response or {}).get("name", "")
        if not token:
            raise UpstreamError(self.name, 502, "auth_tokens returned no token name")

        # Never log the token itself — it is a bearer credential.
        logger.info(
            "minted Live token: model=%s session=%dm connect_window=%ds",
            setup.get("model"),
            session_minutes,
            self.settings.gemini_token_connect_window_seconds,
        )

        return LiveToken(
            token=token,
            ws_url=LIVE_WS_URL,
            model=str(setup.get("model", "")),
            expires_at=expires_at,
            connect_by=connect_by,
        )

    def resolve_model(self, requested: str | None) -> str:
        """The model to call: the caller's choice if allowed, else the default.

        An unknown or disallowed name falls back rather than erroring — a stale
        client should still get a scored interview, just on the default model.
        """
        default = self.settings.gemini_model.strip().removeprefix("models/")
        if not requested:
            return default
        name = requested.strip().removeprefix("models/")
        return name if name in self.settings.allowed_gemini_models else default

    async def generate_content(self, body: dict, *, model: str | None = None) -> dict:
        """One `generateContent` call.

        The caller supplies `contents` and `generationConfig`; the model and the
        API key are chosen here, so a client cannot switch to a pricier model or
        reach a different Google API.

        Why the request body is not built server-side: all eight call sites in
        the app (scoring, regeneration, question generation, résumé extraction,
        adaptive turns, conversation scoring, the guide) send purpose-specific
        prompts. Porting those templates to Python would duplicate a large
        amount of prompt logic across two languages with no security benefit —
        the prompts are not secrets, and the credential is what had to move.
        Contrast `voice.py`, where the instruction IS the security boundary and
        therefore does live server-side.
        """
        payload = dict(body)
        payload.setdefault("safetySettings", DEFAULT_SAFETY_SETTINGS)

        resolved = self.resolve_model(model)

        return await self.request(
            "POST",
            f"/models/{resolved}:generateContent",
            json=payload,
            headers={"Content-Type": "application/json"},
        )
