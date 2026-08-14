"""Voice catalog — ports `server/routes/voices.ts`.

`GET /api/web/voices` is the browsable catalog behind the recruiter's voice and
persona pickers. Static data, so it answers with no credentials configured.

**The preview route is deliberately absent.** Express served
`POST /voices/:id/sample`, which opened a Gemini Live session on the server and
returned the concatenated PCM. The common surface already has the right shape for
this and the browser should use it directly:

    POST /api/rt/gemini-preview-token   { voiceName, sampleText }
      → { token, wsUrl, model, expiresAt, connectBy }

`app.voice.build_preview_setup` locks the voice, the read-once-and-stop
instruction, and the model into the token, caps the sample text at 200 characters,
and bounds the session to `GEMINI_PREVIEW_SESSION_MINUTES`. The web catalog's ids
ARE Google's `prebuiltVoiceConfig.voiceName` values — the same ones mobile sends —
so it is a drop-in, already exercised by the Flutter voice picker.

Duplicating it under `/api/web` would mean a second copy of that setup builder,
kept in sync by hand, for no behavioural difference. This is the first duplicate
the consolidation actually removes rather than adds.

Frontend change: call `/api/rt/gemini-preview-token`, open `wsUrl` with the token,
collect the audio parts of the single turn, and play them. See
`WEB_FRONTEND_MIGRATION_TASKS.md`.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter

from app.security import AuthedUser
from app.web.deps import WebUser
from app.web.schemas import VoiceCatalog
from app.web.store import defaults

logger = logging.getLogger("web.voices")

router = APIRouter(prefix="/voices", tags=["web:voices"])


@router.get("", response_model=VoiceCatalog, summary="Voices and persona presets")
async def catalog(user: AuthedUser = WebUser) -> VoiceCatalog:
    # Authenticated but credential-free: the catalog is a fixed list, so it stays
    # available even when no Gemini key is configured. The picker can render; only
    # the preview needs a key, and that is minted elsewhere.
    return VoiceCatalog.model_validate(
        {"voices": defaults.voice_catalog(), "personas": defaults.PERSONA_PRESETS}
    )
