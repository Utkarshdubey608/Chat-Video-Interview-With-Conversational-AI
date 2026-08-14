# Web surface

Routes ported from the Express server at `web_version/talbotiq-platform/server/`,
mounted under `/api/web/*`.

## Rules

1. This package may import from the shared kernel (`app.config`, `app.security`,
   `app.firebase`, `app.ratelimit`, `app.providers.*`) and from itself.
   **Nothing else.**
2. Nothing outside this package may import from it. Enforced by
   `tests/test_layering.py`.
3. Never import from `app.routers.*` — that is the mobile/desktop API. Share
   through the kernel, never sideways.
4. Paths, request/response shapes and field names match the Express originals
   exactly. The web frontend must not need a second migration.
5. Storage is the `web_*` Firestore collections only.

## Why it is separate

`/api/web/*` is transitional. `/api/templates` already means two different things
— email templates on the common surface (called by the Flutter app), interview
templates here — and the prefix lets both coexist untouched.

When the two surfaces merge, the duplicates (two-way, Gemini generate, Tavus,
Deepgram) collapse and these routes move out. Keeping the boundary sharp is what
makes that a refactor instead of a rewrite.

## Layout

```
web/
├── __init__.py      install(app) — the ONLY thing main.py calls
├── errors.py        {error} + {detail} response shim
├── deps.py          auth, ownership guards, rate-limit buckets
├── routes/          mirrors server/routes/
├── services/        mirrors server/services/
├── store/           mirrors server/store/ — Firestore-backed
└── shared/          port of web's shared/*.ts
```

`routes/` and `services/` mirror the Express tree **file for file**, so a reviewer
can diff `server/services/conversation.ts` against `web/services/conversation.py`
side by side.

## Two deliberate gaps

**Role gating is not implemented.** The Express server guarded most routers with
`requireRecruiter`; that is deferred. Every route still enforces **ownership**
(`recruiterId == uid`, `candidateEmailLower == email`), so there is no
cross-tenant access — but a signed-in candidate can reach recruiter endpoints for
their own data. Search `ROLE-GATING` for the places that would need a guard.

**Runtime API keys.** `web_settings` still holds recruiter-entered Gemini/Tavus
keys, mirroring the Express behaviour. The mobile model is env-only keys and is
the eventual target.

## Consolidation exit criteria

A route group can leave this package once:
- an equivalent exists on the common surface,
- the web frontend has been repointed at it,
- its `web_*` collection has been merged or migrated.

Move one group at a time; the layering test protects the rest.
