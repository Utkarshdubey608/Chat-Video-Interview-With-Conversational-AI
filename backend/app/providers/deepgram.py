"""Deepgram — pre-recorded transcription only.

The app has no live-captions path: `buildWsUrl()` exists in the Dart service but
is never called. The single real caller is the results page, transcribing the
locally-recorded `.wav` after a native interview when Tavus/Gemini Live did not
already supply a transcript.

So there is no socket to authenticate here and no need for Deepgram's
`/v1/auth/grant` temporary tokens — one proxied POST covers all real usage.
"""

from __future__ import annotations

from app.providers.base import ProviderClient

# Matches the Dart service's defaults so transcripts stay comparable.
DEFAULT_MODEL = "nova-3"
DEFAULT_LANGUAGE = "en-US"


class DeepgramClient(ProviderClient):
    name = "Deepgram"
    env_var = "DEEPGRAM_API_KEY"
    base_url = "https://api.deepgram.com/v1"

    @property
    def api_key(self) -> str:
        return self.settings.deepgram_api_key

    def auth_headers(self) -> dict[str, str]:
        return {"Authorization": f"Token {self.api_key.strip()}"}

    async def transcribe(
        self,
        audio: bytes,
        *,
        content_type: str,
        model: str = DEFAULT_MODEL,
        language: str = DEFAULT_LANGUAGE,
    ) -> dict:
        """Transcribe raw audio bytes.

        Deepgram's pre-recorded endpoint takes the audio as the request *body*
        with a Content-Type header — not multipart. `punctuate` and
        `smart_format` are always on, matching the app's existing calls, because
        the transcript feeds scoring and per-question slicing.
        """
        return await self.request(
            "POST",
            "/listen",
            params={
                "model": model,
                "language": language,
                "punctuate": "true",
                "smart_format": "true",
            },
            content=audio,
            headers={"Content-Type": content_type},
        )
