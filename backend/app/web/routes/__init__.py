"""Route modules, mirroring `web_version/talbotiq-platform/server/routes/`.

One module per Express router, same name, so the two trees diff side by side.
Each module exposes a `router` that `app.web.__init__` mounts under `/api/web`.

Ported:

    health.py            ← index.ts's /api/health
    auth.py              ← auth.ts            (1 route)
    leads.py             ← leads.ts           (1 route, PUBLIC)
    voices.py            ← voices.ts          (catalog only — see below)
    avatar.py            ← avatar.ts          (7 routes)
    face_cache.py        ← faceCache.ts       (1 route, GET/HEAD)
    help.py              ← help.ts            (chat, agent, tts-token)

## Gemini Live: tokens, not relays

Two Express routes opened a Gemini Live session ON THE SERVER and streamed audio
back through it. Neither is ported that way. The browser now mints a token with
the whole session locked into it and connects to Google directly — the same
mechanism the Flutter app already uses:

    POST /voices/:id/sample  ->  POST /api/rt/gemini-preview-token  (shared, unchanged)
    POST /help/tts           ->  POST /api/web/help/tts-token

The preview reuses the common surface's route outright: its setup builder already
caps the text, locks the voice and pins the read-once instruction, and the web
catalog's ids are the same Google voice names mobile sends. That is the first
duplicate the consolidation removes rather than adds.

Both need new browser code to open the socket and collect the audio — see
Documents/WEB_FRONTEND_MIGRATION_TASKS.md.

Still to port — see Documents/COMMON_BACKEND_PHASE_PLAN.md for the order:

    Phase 5              templates.py  question_sets.py  settings.py
                         invite_email_templates.py
    Phase 6              invites.py  brevo_webhook.py  pipelines.py
    Phase 7              sessions.py  analytics.py
    Phase 8              the WebSocket relays (voice, and the two Deepgram ones)

A route that is mounted here but not finished must FAIL LOUDLY (503 with a
message), never return a plausible-looking empty result. During cutover the
deployment routes each prefix to whichever server actually implements it, so a
silent stub would look like working software with missing data.
"""
