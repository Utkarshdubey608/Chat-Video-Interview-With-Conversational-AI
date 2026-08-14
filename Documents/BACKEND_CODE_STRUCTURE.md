# Backend Code Structure — Keeping Web Code Separable

**Audience:** whoever implements the port into `backend/`.

**Rule in one line:** web code lives in `app/web/`, may import *out* of it, and
nothing outside may import *in*. Delete the directory and one line in `main.py`,
and the web surface is gone cleanly.

---

## Why this matters

`/api/web/*` is a transitional namespace. At some point the two surfaces merge and
the duplicates (two-way, Gemini generate, Tavus, Deepgram) collapse into one. That
consolidation is only cheap if, at any moment, you can answer three questions by
looking at the tree:

1. Is this code web-only, mobile-only, or shared?
2. What would break if the web surface were deleted?
3. Which files are a straight port of an Express file, and which are new?

Conventions alone won't hold that — there's an enforcement test below.

---

## Three tiers

| Tier | What | Where | Rule |
|---|---|---|---|
| **Shared kernel** | Config, auth, Firestore bootstrap, rate limiting, vendor clients | `app/config.py`, `app/security.py`, `app/firebase.py`, `app/ratelimit.py`, `app/providers/` | Both surfaces import it. Changes here affect mobile — review carefully. |
| **Common surface** | The mobile/desktop API. **Frozen.** | `app/routers/`, `app/schemas.py`, `app/interviews.py`, `app/evaluation.py`, `app/resume.py`, `app/voice.py`, `app/mailer.py`, `app/templating.py`, `app/templates_store.py` | Do not change paths, shapes, field names or auth. |
| **Web surface** | Everything ported from the Express server | `app/web/` | Self-contained. Nothing outside imports from it. |

**Do not relocate existing files** to make the tiers physically obvious. Moving
`config.py` or `security.py` into an `app/core/` package would churn modules the
mobile API depends on for no functional gain. The table above is the classification;
the tree stays as it is.

---

## Folder layout

```
backend/app/
├── config.py              ─┐
├── security.py             │  SHARED KERNEL
├── firebase.py             │  (both surfaces)
├── ratelimit.py            │
├── providers/              │  one module per vendor
│   ├── base.py             │
│   ├── gemini.py           │
│   ├── tavus.py            │
│   ├── daily.py            │
│   ├── deepgram.py         │
│   ├── rekognition.py      │  ← new (web is the only consumer today)
│   └── hume.py             │  ← new (web is the only consumer today)
│                          ─┘
├── main.py                    mounts both surfaces
│
├── routers/               ─┐
├── schemas.py              │  COMMON SURFACE — FROZEN
├── interviews.py           │  the mobile/desktop API
├── evaluation.py           │
├── resume.py               │
├── voice.py                │
├── mailer.py               │
├── templating.py           │
├── templates_store.py      │
│                          ─┘
└── web/                   ─┐
    ├── README.md           │  WEB SURFACE
    ├── __init__.py         │  exposes ONE router
    ├── deps.py             │  web-only dependencies
    ├── schemas.py          │  web-only models
    ├── errors.py           │  the {error} response shim
    ├── routes/             │  ← mirrors server/routes/
    ├── services/           │  ← mirrors server/services/
    ├── store/              │  ← mirrors server/store/
    └── shared/             │  ← port of web's shared/*.ts
                           ─┘
```

`app/web/` mirrors the Express tree **file for file**, so a reviewer can diff
`server/services/conversation.ts` against `app/web/services/conversation.py` side by
side. That keeps the port mechanical and makes "is this ported or new?" obvious.

---

## The layering rule

```
app/web/*        →  may import from  app/config, app/security, app/firebase,
                                     app/ratelimit, app/providers/*, app/web/*
app/routers/*    →  must NOT import from app/web/*
app/<kernel>     →  must NOT import from app/web/*
```

One-way. That single invariant is what makes the web surface deletable, and what
stops web-shaped assumptions leaking into the mobile API.

### Enforce it with a test

Conventions rot. Add this to `backend/tests/test_layering.py`:

```python
"""The web surface must stay deletable.

`app/web/` may import from the shared kernel; nothing outside it may import from
`app/web/`. If this test fails, the web surface has grown a consumer and can no
longer be removed or consolidated independently.
"""
from __future__ import annotations

import ast
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "app"


def _imports(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(a.name for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names.add(node.module)
    return names


def test_nothing_outside_app_web_imports_app_web() -> None:
    offenders: list[str] = []
    for path in APP.rglob("*.py"):
        if "web" in path.relative_to(APP).parts:
            continue  # inside the web surface — allowed
        for name in _imports(path):
            if name == "app.web" or name.startswith("app.web."):
                offenders.append(f"{path.relative_to(APP)} imports {name}")
    assert not offenders, "web surface has leaked into the common surface:\n" + "\n".join(offenders)
```

Add a mirror test asserting `app/web/**` never imports `app.routers.*` — web must
not reach into the mobile API's handlers either. Sharing happens through the kernel,
never sideways.

### One mount point

`app/web/__init__.py` exposes exactly one router:

```python
from fastapi import APIRouter
from app.web.routes import (analytics, auth, avatar, ...)

router = APIRouter(prefix="/api/web")
for module in (analytics, auth, avatar, ...):
    router.include_router(module.router)
```

`main.py` then gains **one line**:

```python
app.include_router(web.router)
```

Removing the web surface is: delete `app/web/`, delete that line, delete the
`web_*` Firestore collections.

---

## Express → FastAPI file map

Port one file at a time; keep the names.

### Routes — `server/routes/` → `app/web/routes/`

| Express | Python | Routes |
|---|---|---|
| `analytics.ts` | `analytics.py` | 1 |
| `auth.ts` | `auth.py` | 1 |
| `avatar.ts` | `avatar.py` | 7 |
| `brevoWebhook.ts` | `brevo_webhook.py` | 1 *(public)* |
| `faceCache.ts` | `face_cache.py` | 1 |
| `help.ts` | `help.py` | 3 |
| `inviteEmailTemplates.ts` | `invite_email_templates.py` | 6 |
| `invites.ts` | `invites.py` | 6 |
| `leads.ts` | `leads.py` | 1 *(public)* |
| `pipelines.ts` | `pipelines.py` | 10 |
| `questionSets.ts` | `question_sets.py` | 7 |
| `sessions.ts` | `sessions.py` | 30 |
| `settings.ts` | `settings.py` | 8 |
| `templates.ts` | `templates.py` | 5 |
| `voices.ts` | `voices.py` | 2 |

### Services — `server/services/` → `app/web/services/`

| Express | Python | Note |
|---|---|---|
| `analytics.ts` | `analytics.py` | |
| `autopilotAgent.ts` | `autopilot_agent.py` | |
| `brevo.ts` | `brevo.py` | verified-sender list (REST) |
| `conversation.ts` | `conversation.py` | 701 lines — state machine |
| `dailyServer.ts` | — | **use `providers/daily.py`** |
| `deepgramRelay.ts` | `deepgram_relay.py` | WebSocket relay |
| `email.ts` | — | **use `app/mailer.py`** after its rewrite |
| `firebaseAdmin.ts` | — | **use `app/firebase.py`** |
| `gemini.ts` | `gemini.py` | thin wrapper: key resolution over `providers/gemini.py` |
| `interviewInvite.ts` | `interview_invite.py` | |
| `inviteBridge.ts` | `invite_bridge.py` | |
| `inviteEmailRender.ts` | `invite_email_render.py` | see *Rendering parity* |
| `inviteExtract.ts` | `invite_extract.py` | needs `pypdf`, `python-docx`, `openpyxl` |
| `mimicGuide.ts` | `mimic_guide.py` | |
| `mimicGuidePrompt.ts` | `mimic_guide_prompt.py` | |
| `mimicGuideTts.ts` | `mimic_guide_tts.py` | |
| `rekognition.ts` | — | **use `providers/rekognition.py`** |
| `resume.ts` | `resume_text.py` | local text extraction — **not** `app/resume.py` (that's Gemini-based; both are legitimate) |
| `scoring.ts` | `scoring.py` | KPI rubric weighting |
| `signals.ts` | `signals.py` | pure — port with its tests first |
| `tavusServer.ts` | `tavus_candidate.py` | wraps `providers/tavus.py` |
| `timing.ts` | `timing.py` | pure — port with its tests first |
| `transcription.ts` | — | **use `providers/deepgram.py`** |
| `users.ts` | — | reads Firestore `users/{uid}` directly |
| `videoTranscript.ts` | `video_transcript.py` | pure — port with its tests first |
| `voice.ts` | `voice_relay.py` | WebSocket relay, 638 lines |
| `voiceFlow.ts` | `voice_flow.py` | pure — port with its tests first |

### Store, middleware, util

| Express | Python |
|---|---|
| `store/db.ts` | `web/store/db.py` — Firestore-backed, same in-memory read API |
| `store/defaults.ts` | `web/store/defaults.py` |
| `store/seed.ts` | `web/store/seed.py` |
| `middleware/auth.ts` | `web/deps.py` — plus the `?token=` upgrade variant |
| `util/ah.ts` | — FastAPI exception handlers |
| `util/cors.ts` | — `CORSMiddleware` |

### Web's `shared/` — the one thing to watch

`web_version/talbotiq-platform/shared/*.ts` is imported by **both** the Express
server and the React frontend, and not only for types:

| Module | Server consumers |
|---|---|
| `shared/inviteEmail.ts` | `inviteEmailRender.ts`, `interviewInvite.ts`, `invites.ts`, `pipelines.ts`, `inviteEmailTemplates.ts` |
| `shared/speech.ts` | `voice.ts`, `tavusServer.ts` |
| `shared/autopilot.ts` | `autopilotAgent.ts` *(types only)* |

Port these to `app/web/shared/invite_email.py` and `app/web/shared/speech.py`.

**Rendering parity is a real risk.** `inviteEmailRender.ts`'s docstring states the
point of the shared renderer is that *"the sent email is byte-identical to the client
preview."* After the port, the frontend runs the TypeScript renderer and the server
runs a Python one, and **nothing enforces that they agree** — the preview and the
sent mail can drift silently.

Mitigation: a shared fixture set. Put input/expected-output pairs in a JSON file that
both the TS test suite and the Python test suite read and assert against. Cheap, and
it is the only thing that keeps the two honest. Do the same for `speech.ts` if the
frontend uses it.

---

## Share or duplicate?

The judgment that keeps the tree honest:

| Kind of code | Decision |
|---|---|
| **Vendor clients** (Gemini, Tavus, Daily, Deepgram, Rekognition, Hume) | **Share** — `app/providers/`, one module per vendor, regardless of who consumes it. Web wraps them where it needs extra behaviour (e.g. key resolution from `web_settings`). |
| **Auth, config, Firestore bootstrap, rate limiting** | **Share** — kernel. |
| **Mail transport** | **Share** — `app/mailer.py`, rewritten as a generic SMTP sender. Web needs a per-send `From`, `replyTo` and custom headers; mobile needs none of it but is unharmed. No web copy. |
| **Routes** | **Separate** — always. Even where the logic is identical (two-way, Gemini generate), the paths and shapes differ, and collapsing them is the consolidation work, not this work. |
| **Domain logic and state machines** | **Separate** — `timing`, `conversation`, `scoring`, `signals` are web's interview model. Mobile has its own in `app/evaluation.py` and `app/voice.py`. |
| **Storage** | **Separate** — `web_*` collections, `app/web/store/`. |
| **Pydantic models** | **Separate** — `app/web/schemas.py`. Never add a web-only field to `app/schemas.py`. |

**Do not** collapse a duplicate just because it looks redundant. Two-way exists at
`/api/interviews/{id}/twoway/*` (mobile, keyed on interviews) and
`/api/web/sessions/{id}/twoway/*` (web, keyed on sessions). They share
`providers/daily.py` and nothing else. Merging them is a deliberate later step with
a frontend change attached.

---

## Conventions

- **Firestore collections:** every web collection is `web_`-prefixed, so ownership is
  visible in the console and in any query.
- **Field names:** ported routes keep the web frontend's camelCase exactly. Web
  models are camelCase; do not "fix" the common surface's snake_case to match.
- **Rate limiting:** web routes that call a vendor take the shared limiter
  dependencies. Cheap session routes (state polls, drafts, timing ticks, integrity
  events) take none — they hit Firestore, not a vendor.
- **Error shape:** `app/web/errors.py` emits both `error` and `detail`. Web reads
  `error` (`api.ts:59`); the common surface keeps `detail`.
- **Tests:** `backend/tests/web/` mirrors `app/web/`. Port each Express test file
  alongside its module — the pure modules (`timing`, `voice_flow`, `signals`,
  `video_transcript`) already have suites and are the correctness core.

---

## `app/web/README.md`

Commit this inside the package so the rules travel with the code:

```markdown
# Web surface

Routes ported from the Express server at
`web_version/talbotiq-platform/server/`, mounted under `/api/web/*`.

## Rules

1. This package may import from the shared kernel (`app.config`,
   `app.security`, `app.firebase`, `app.ratelimit`, `app.providers.*`)
   and from itself. NOTHING ELSE.
2. Nothing outside this package may import from it. Enforced by
   `tests/test_layering.py`.
3. Never import from `app.routers.*` — that is the mobile/desktop API.
   Share through the kernel, never sideways.
4. Paths, request/response shapes and field names match the Express
   originals exactly. The web frontend must not need a second migration.
5. Storage is the `web_*` Firestore collections only.

## Why it is separate

`/api/web/*` is transitional. When the two surfaces merge, the duplicates
(two-way, Gemini generate, Tavus, Deepgram) collapse and these routes move
out. Keeping the boundary sharp is what makes that a refactor instead of a
rewrite.

## Consolidation exit criteria

The package can start dissolving once, for each route group:
  - an equivalent exists on the common surface,
  - the web frontend has been repointed at it,
  - its `web_*` collection has been merged or migrated.
Move one group at a time; the layering test protects the rest.
```

---

## Summary

| Mechanism | Purpose |
|---|---|
| `app/web/` package | one place, physically obvious |
| Mirrors the Express tree file-for-file | port is diffable and reviewable |
| One-way import rule + `test_layering.py` | boundary can't rot silently |
| One router, one line in `main.py` | deletable in two edits |
| `web_*` Firestore prefix | data ownership visible |
| Vendor clients shared, routes/logic/storage separated | no pointless duplication, no entanglement |
| Shared render fixtures | TS preview and Python sender can't drift |
