"""Hume AI — voice prosody, and why this client is allowed to fail.

Hume has **discontinued** the batch Expression-Measurement API this uses ("The
Expression Measurement API has been discontinued"), so a plain proxy can never
succeed on a current account. It is still here for two reasons: an account that
predates the change may still have access, and if Hume restores the product the
path starts working again with no code change.

Callers therefore treat a submit failure as normal and fall back to analysing the
audio with Gemini — see `app.web.services.voice_analysis`. That is why
`submit_job` returns `None` instead of raising: a missing key or a rejected job is
an expected branch here, not an error.

Polling and prediction fetches DO raise, because by then a job id exists and a
failure genuinely is one.
"""

from __future__ import annotations

import logging

from app.providers.base import ProviderClient

logger = logging.getLogger("providers.hume")


class HumeClient(ProviderClient):
    name = "Hume"
    env_var = "HUME_API_KEY"
    base_url = "https://api.hume.ai/v0/batch"

    @property
    def api_key(self) -> str:
        return self.settings.hume_api_key

    def auth_headers(self) -> dict[str, str]:
        return {"X-Hume-Api-Key": self.api_key.strip()}

    async def submit_job(
        self, audio: bytes, *, filename: str, content_type: str
    ) -> str | None:
        """Submit a prosody job. Returns its id, or None if Hume would not take it.

        Never raises: every failure mode here — no key, discontinued product,
        network trouble — has the same answer, which is to let the caller fall back
        to the Gemini path. Swallowing the error is the point, so the reason is
        logged.
        """
        if not self.is_configured:
            return None

        try:
            payload = await self.request(
                "POST",
                "/jobs",
                files={"file": (filename, audio, content_type)},
                # Hume takes the job config as a form field named `json`, not as a
                # JSON request body — the body is multipart because of the audio.
                data={"json": '{"models": {"prosody": {}}}'},
            )
        except Exception as exc:  # noqa: BLE001 - an expected branch, see docstring
            logger.warning(
                "Hume submit failed (%s) — caller should fall back to Gemini",
                type(exc).__name__,
            )
            return None

        job_id = payload.get("job_id") or payload.get("id") if isinstance(payload, dict) else None
        if not job_id:
            logger.warning("Hume submit returned no job id — falling back to Gemini")
            return None
        return str(job_id)

    async def get_job(self, job_id: str) -> bytes:
        """A job's status, as raw JSON bytes.

        Raw rather than parsed: the caller passes this straight back to the client,
        which has its own well-tested parser for Hume's shape. Re-serialising a
        parsed copy would risk changing it.
        """
        return await self.request(
            "GET", f"/jobs/{job_id}", expect_json=False
        )

    async def get_predictions(self, job_id: str) -> bytes:
        """A completed job's predictions, as raw JSON bytes.

        These payloads are large (per-segment emotion scores for a whole
        interview), so they are deliberately not parsed on the way through.
        """
        return await self.request(
            "GET", f"/jobs/{job_id}/predictions", expect_json=False
        )
