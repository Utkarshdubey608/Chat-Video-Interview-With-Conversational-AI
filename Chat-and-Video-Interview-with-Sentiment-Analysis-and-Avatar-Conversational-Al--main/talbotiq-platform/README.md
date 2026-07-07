# TalbotIQ Platform — React + TypeScript + Vite + Express

A HireVue-style **AI Interview module** (Chat + Video Avatar tracks) layered on the
existing TalbotIQ Tavus app. Candidates take a timed, one-question-at-a-time
interview; recruiters configure everything and review AI-scored results.

## Quick Start

```bash
cd talbotiq-platform
npm install
cp .env.example .env        # then add your GEMINI_API_KEY (optional)
npm run dev                 # runs the Vite client + the API server together
```

- Client (Vite): **http://localhost:3001**
- API (Express): **http://localhost:8787** (Vite proxies `/api/*` to it)

Without a `GEMINI_API_KEY` the app fully works using a **heuristic fallback** for
adaptive question generation and scoring (clearly flagged in the UI).

### Scripts
| Script | What it does |
|--------|--------------|
| `npm run dev` | Client + server concurrently |
| `npm run dev:client` / `dev:server` | Run either side alone |
| `npm run server` | API server only (`tsx server/index.ts`) |
| `npm run build` | Type-check + production client build |

## Security model (important)

`GEMINI_API_KEY` lives **only on the server** (`server/`, read from `process.env`).
All Gemini calls — résumé-based question generation and answer scoring — happen in
Express routes. The client only ever calls relative `/api/*` endpoints; the key is
never bundled or returned. Verify with `npm run build` then searching `dist/` for
the key value (it must be absent).

Timers are **server-authoritative**: the server records phase start timestamps and
computes remaining time and auto-submission from its own clock. A refresh, a
disconnect, or a tampered client clock cannot extend time or reveal upcoming
questions — `/api/sessions/:id/state` only ever returns the *current* question.

## Architecture

```
talbotiq-platform/
├─ shared/types.ts            # single source of truth, imported by client + server
├─ server/                    # Express + TypeScript API (run via tsx)
│  ├─ index.ts                # app bootstrap + error handler
│  ├─ routes/                 # templates · questionSets · sessions
│  ├─ services/               # timing (authoritative) · gemini · resume · scoring
│  └─ store/                  # in-memory + JSON-file persistence (server/data/)
└─ src/
   ├─ features/interview/     # candidate flow (chat fully built, video scaffolded)
   ├─ features/recruiter/     # templates, question sets, sessions, results
   ├─ lib/api.ts              # typed fetch client → /api
   └─ components/ui/          # shared design system (reused, not replaced)
```

## AI Interview module — pages

| Page | Route | Description |
|------|-------|-------------|
| Sessions | `/sessions` | Create candidate links; list + open scored reports |
| Templates | `/templates`, `/templates/:id` | Editor: track, question source, timing, rubric, branding, integrity + live preview |
| Question Sets | `/question-sets` | CRUD, duplicate, drag-to-reorder |
| Candidate | `/take/:sessionId` | Track select → welcome → (résumé) → system check → timed loop → done |
| Report | `/sessions/:id/report` | Gauge, radar, KPI bars, per-question accordion, integrity, **PDF export** |

### Candidate flow
Track-select → branded welcome → (adaptive only: résumé upload) → system check →
per-question loop (prep → answer → **auto-submit at 0** → next) → completion.
Drafts auto-save; a refresh resumes the same question with the server's remaining
time. Candidates never see scores.

### Recruiter configuration
Templates are reusable: **question source** (adaptive résumé / fixed set), full
**timing** (prep, answer, skip-prep, early-submit, warning threshold, count, cap),
an editable **KPI rubric** (toggle / relabel / weights auto-normalized / custom
KPIs), **branding** (name, accent, logo, welcome), and **integrity** toggles.

### Video Avatar track (scaffold)
Reuses the same timing engine, config, and results pipeline. Camera/mic preview +
`MediaRecorder` capture work; avatar TTS and video upload are marked with
`TODO(video-avatar)` in `src/features/interview/components/CameraRecorder.tsx` and
can plug into the existing Tavus integration (`src/services/tavus.ts`).

## Environment variables
| Var | Scope | Purpose |
|-----|-------|---------|
| `GEMINI_API_KEY` | server only | Gemini question gen + scoring (blank ⇒ heuristic fallback) |
| `GEMINI_MODEL` | server only | Defaults to `gemini-2.5-flash` |
| `PORT` | server only | API port (default 8787) |

## Notes
- The store is in-memory with JSON-file persistence (`server/data/`), not a
  production database. Fine for demos; swap for a real DB before production.
- The original Tavus pages (Setup/Interview/Results/etc.) are unchanged.

## Tech stack
React 18 · TypeScript · Vite 5 · Express 4 · Tailwind · React Router v6 · Zustand ·
TanStack Query · Recharts · Framer Motion · @dnd-kit · @google/genai · jsPDF.
