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
    from app.providers import rekognition

    return {
        "gemini": bool(settings.gemini_api_key.strip()),
        "tavus": bool(settings.tavus_api_key.strip()),
        "deepgram": bool(settings.deepgram_api_key.strip()),
        "daily": bool(settings.daily_api_key.strip()),
        # Web-surface providers. Added rather than renamed: the Flutter app maps
        # every entry of this dict to a bool generically
        # (`backend_client.dart:providerReadiness`), so new keys are safe while a
        # rename or removal would silently disable a feature on mobile.
        "hume": bool(settings.hume_api_key.strip()),
        "rekognition": rekognition.is_configured(settings),
        # Not a provider key, but the app's Service Status screen asks the same
        # question of it: can this feature actually be used right now?
        "email": mailer.config_hint(settings) is None,
    }
