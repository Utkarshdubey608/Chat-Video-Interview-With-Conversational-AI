"""Clients for the third-party APIs the mobile app used to call directly.

One module per vendor, each a thin `ProviderClient` subclass that knows only how
to authenticate itself and which endpoints it exposes. Routers depend on these;
these never depend on routers.

The credentials live exclusively in `Settings` (i.e. `backend/.env`) — the app
never receives them. The one exception is Gemini Live, where the app connects
straight to Google using a short-lived token minted here; see `gemini.py`.
"""

from __future__ import annotations

from app.config import Settings
from app.providers.base import ProviderClient, ProviderNotConfigured, UpstreamError

__all__ = [
    "ProviderClient",
    "ProviderNotConfigured",
    "UpstreamError",
    "readiness",
]


def readiness(settings: Settings) -> dict[str, bool]:
    """Which providers have a key configured — surfaced by /health.

    This replaces the app's old per-key "Test Connection" buttons: availability is
    reported by the server, never derived from a key the client holds.
    """
    from app import mailer

    return {
        "gemini": bool(settings.gemini_api_key.strip()),
        "tavus": bool(settings.tavus_api_key.strip()),
        "deepgram": bool(settings.deepgram_api_key.strip()),
        "daily": bool(settings.daily_api_key.strip()),
        # Not a provider key, but the app's Service Status screen asks the same
        # question of it: can this feature actually be used right now?
        "email": mailer.config_hint(settings) is None,
    }
