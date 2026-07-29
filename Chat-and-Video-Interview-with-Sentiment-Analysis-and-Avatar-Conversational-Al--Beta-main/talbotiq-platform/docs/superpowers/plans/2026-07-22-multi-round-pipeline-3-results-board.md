# Multi-Round Pipeline — Plan 3: Results Progression Board (View) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give recruiters a read-only per-role progression view: an Analytics-style filtered list of pipelines, and a Kanban board (columns = rounds → Selected → Not-advancing) whose candidate cards show each round's live status + AI score. No advancement actions yet — that is Plan 4.

**Architecture:** A new `GET /api/pipelines/:id/board` endpoint joins the pipeline's `PipelineCandidate` records with the local `db.reports` (scores) and `db.sessions` (status) — no Firestore reads. A pure `buildBoard(...)` helper does the join and is unit-tested. The client gains `pipelinesApi.board`, a kind-aware `inviteEmailTemplatesApi`, and a tiny CSV download util (used in Plan 4). A `/pipelines` recruiter route + nav entry lands, with `PipelinesPage` (filters + list) and `PipelineBoardPage` (read-only Kanban).

**Tech Stack:** TypeScript, Node/Express, React 18 + Vite, the repo's `tsx` unit-test convention. `@dnd-kit` is present (drag lands in Plan 4).

## Global Constraints

- **ADDITIVE ONLY.** No changes to `invites.ts`, sessions, auth, or the email module. New routes/pages/helpers only. The single-interview Results/Sessions/Analytics surfaces are untouched.
- **Frozen modules untouched:** auth/role, invite-link/claim, Firestore interop field names. The board reads the LOCAL store (`db.reports` keyed by `sessionId`==interviewId; `db.sessions` keyed by id==interviewId) — never Firestore.
- **Ownership:** `GET /:id/board` is owner-scoped via the existing `loadOwned` (404 cross-owner). `PipelineCandidate.recruiterId` is already server-stamped (Plan 2).
- **Score source of truth:** a round is scored iff `db.reports.get(interviewId)` exists with a numeric `overallScore` and `notEvaluated !== true`. A candidate's current-round interviewId = `perRound[currentRoundIndex].interviewId`.
- **Analytics filter parity:** the Pipelines list filter bar mirrors `AnalyticsPage` controls — `role` (Select of distinct pipeline roles) + `dateFrom`/`dateTo` (`<input type="date">`). Reuse the `Select` primitive and the same control layout.
- **Design system:** brand green `#0d5c3a`; reuse `src/components/ui/*` primitives; new nav entry `{ to: '/pipelines', label: 'Pipelines' }`; new route inside the `RecruiterShell` group.
- **Gates:** `npx tsx <file>.test.ts` per test; `npm run build` (src+shared); `npx tsc -p server/tsconfig.json --noEmit` (server). No browser harness — UI tasks gate on build + diff review + a documented manual walkthrough.

## File structure (this plan)

- `shared/types.ts` — MODIFY: add `PipelineBoard`, `BoardCard`, `BoardColumn` view types.
- `server/routes/pipelines.ts` — MODIFY: add pure `buildBoard(...)` + `GET /:id/board`; export `buildBoard` in `__test`.
- `server/routes/pipelines.test.ts` — MODIFY: add `buildBoard` join assertions.
- `src/lib/api.ts` — MODIFY: add `pipelinesApi.board`; make `inviteEmailTemplatesApi` kind-aware; add `downloadCsv`.
- `src/App.tsx` — MODIFY: add `/pipelines` + `/pipelines/:id` routes.
- `src/components/layout/Nav.tsx` — MODIFY: add the Pipelines nav entry.
- `src/features/recruiter/PipelinesPage.tsx` — CREATE: filters + pipeline list.
- `src/features/recruiter/PipelineBoardPage.tsx` — CREATE: read-only progression Kanban.

---

## Task 1: Board join helper + endpoint (`server/routes/pipelines.ts`)

**Files:**
- Modify: `shared/types.ts` (view types)
- Modify: `server/routes/pipelines.ts`
- Test: `server/routes/pipelines.test.ts` (extend)

**Interfaces:**
- Consumes: `db.pipelines`, `db.pipelineCandidates`, `db.reports`, `db.sessions`; `loadOwned`.
- Produces:
  - `shared/types.ts`: `interface BoardCard { pipelineCandidateId: string; candidateEmail: string; candidateName?: string; currentRoundIndex: number; status: PipelineCandidateStatus; roundStatus: 'invited'|'in_progress'|'completed'|'expired'|'none'; score: number | null; advanceable: boolean }`; `interface BoardColumn { key: string; title: string; roundIndex: number | null; kind: 'round'|'selected'|'not_advancing'; cards: BoardCard[] }`; `interface PipelineBoard { pipeline: Pipeline; columns: BoardColumn[] }`
  - `buildBoard(pipeline: Pipeline, candidates: PipelineCandidate[], reportOf: (id: string) => { overallScore?: number; notEvaluated?: boolean } | undefined, sessionStatusOf: (id: string) => string | undefined): PipelineBoard` (pure)
  - `GET /api/pipelines/:id/board`

- [ ] **Step 1: Add view types to `shared/types.ts`**

```ts
export interface BoardCard {
  pipelineCandidateId: string
  candidateEmail: string
  candidateName?: string
  currentRoundIndex: number
  status: PipelineCandidateStatus
  roundStatus: 'invited' | 'in_progress' | 'completed' | 'expired' | 'none'
  score: number | null
  advanceable: boolean
}
export interface BoardColumn {
  key: string
  title: string
  roundIndex: number | null
  kind: 'round' | 'selected' | 'not_advancing'
  cards: BoardCard[]
}
export interface PipelineBoard {
  pipeline: Pipeline
  columns: BoardColumn[]
}
```

- [ ] **Step 2: Write failing test assertions in `server/routes/pipelines.test.ts`**

Add `buildBoard` to the `__test` destructure at top. Add before the summary block:

```ts
{
  const { buildBoard } = __test
  const now = '2026-07-22T00:00:00.000Z'
  const pipe = { id: 'pl-b', recruiterId: 'alice', role: 'Backend', type: 'multi' as const, rounds: goodRounds, createdAt: now, updatedAt: now }
  // c1: completed + scored in round 0 -> advanceable in round 0 column
  const c1 = { id: 'c1', pipelineId: 'pl-b', recruiterId: 'alice', candidateEmail: 'a@x.com', candidateEmailLower: 'a@x.com', role: 'Backend', currentRoundIndex: 0, status: 'in_round' as const, perRound: [{ roundIndex: 0, interviewId: 'iv-c1', invitedAt: now }], history: [], createdAt: now, updatedAt: now }
  // c2: invited only (no session/report) -> not advanceable
  const c2 = { ...c1, id: 'c2', candidateEmail: 'b@x.com', candidateEmailLower: 'b@x.com', perRound: [{ roundIndex: 0, interviewId: 'iv-c2', invitedAt: now }] }
  // c3: selected (terminal)
  const c3 = { ...c1, id: 'c3', candidateEmail: 'c@x.com', candidateEmailLower: 'c@x.com', status: 'selected' as const, currentRoundIndex: 1, perRound: [{ roundIndex: 0, interviewId: 'iv-c3a', invitedAt: now }, { roundIndex: 1, interviewId: 'iv-c3b', invitedAt: now }] }
  const reports: Record<string, { overallScore?: number; notEvaluated?: boolean }> = { 'iv-c1': { overallScore: 72 } }
  const sessions: Record<string, string> = { 'iv-c1': 'completed', 'iv-c2': 'created' }
  const board = buildBoard(pipe, [c1, c2, c3], (id) => reports[id], (id) => sessions[id])

  assert('columns = rounds + selected + not_advancing', board.columns.length === goodRounds.length + 2)
  const round0 = board.columns.find((c) => c.kind === 'round' && c.roundIndex === 0)!
  const selectedCol = board.columns.find((c) => c.kind === 'selected')!
  assert('c1 in round0 column', round0.cards.some((k) => k.pipelineCandidateId === 'c1'))
  const c1card = round0.cards.find((k) => k.pipelineCandidateId === 'c1')!
  assert('c1 scored 72', c1card.score === 72 && c1card.roundStatus === 'completed')
  assert('c1 advanceable', c1card.advanceable === true)
  const c2card = round0.cards.find((k) => k.pipelineCandidateId === 'c2')!
  assert('c2 not scored -> null score, not advanceable', c2card.score === null && c2card.advanceable === false)
  assert('c3 in selected column, not advanceable', selectedCol.cards.some((k) => k.pipelineCandidateId === 'c3') && selectedCol.cards[0].advanceable === false)
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `npx tsx server/routes/pipelines.test.ts`
Expected: FAIL — `buildBoard` undefined.

- [ ] **Step 4: Implement `buildBoard` + the route in `server/routes/pipelines.ts`**

Add the imports:
```ts
import type { PipelineBoard, BoardColumn, BoardCard, PipelineCandidate } from '../../shared/types'
```

Add the pure helper (place with the other helpers):
```ts
/** Join candidates with their current round's report/session into a board (pure). */
export function buildBoard(
  pipeline: Pipeline,
  candidates: PipelineCandidate[],
  reportOf: (id: string) => { overallScore?: number; notEvaluated?: boolean } | undefined,
  sessionStatusOf: (id: string) => string | undefined,
): PipelineBoard {
  const roundCols: BoardColumn[] = pipeline.rounds.map((r) => ({
    key: `round-${r.index}`, title: r.name, roundIndex: r.index, kind: 'round' as const, cards: [],
  }))
  const selectedCol: BoardColumn = { key: 'selected', title: 'Selected', roundIndex: null, kind: 'selected', cards: [] }
  const notCol: BoardColumn = { key: 'not-advancing', title: 'Not advancing', roundIndex: null, kind: 'not_advancing', cards: [] }

  for (const c of candidates) {
    const prog = c.perRound.find((p) => p.roundIndex === c.currentRoundIndex)
    const interviewId = prog?.interviewId
    const report = interviewId ? reportOf(interviewId) : undefined
    const scored = !!report && typeof report.overallScore === 'number' && report.notEvaluated !== true
    const sessionStatus = interviewId ? sessionStatusOf(interviewId) : undefined
    const roundStatus: BoardCard['roundStatus'] = !interviewId ? 'none'
      : scored || sessionStatus === 'completed' ? 'completed'
      : sessionStatus === 'in_progress' || sessionStatus === 'system_check' ? 'in_progress'
      : sessionStatus === 'expired' ? 'expired'
      : 'invited'
    const card: BoardCard = {
      pipelineCandidateId: c.id, candidateEmail: c.candidateEmail, candidateName: c.candidateName,
      currentRoundIndex: c.currentRoundIndex, status: c.status, roundStatus,
      score: scored ? (report!.overallScore as number) : null,
      advanceable: c.status === 'in_round' && scored,
    }
    if (c.status === 'selected') selectedCol.cards.push(card)
    else if (c.status === 'not_advancing') notCol.cards.push(card)
    else {
      const col = roundCols.find((rc) => rc.roundIndex === c.currentRoundIndex) ?? roundCols[0]
      col.cards.push(card)
    }
  }
  return { pipeline, columns: [...roundCols, selectedCol, notCol] }
}
```

Add the route:
```ts
pipelinesRouter.get('/:id/board', ah((req, res) => {
  const auth = requireAuth(req)
  const pipeline = loadOwned(req.params.id, auth)
  const candidates = [...db.pipelineCandidates.values()].filter((c) => c.pipelineId === pipeline.id)
  const board = buildBoard(
    pipeline, candidates,
    (id) => db.reports.get(id),
    (id) => db.sessions.get(id)?.status,
  )
  res.json(board)
}))
```

Add `buildBoard` to `__test`:
```ts
export const __test = { owns, normalize, loadOwned, ALLOWED_ROUND_MODES, buildPipelineCandidate, buildBoard }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `npx tsx server/routes/pipelines.test.ts`
Expected: PASS — all assertions incl. the new board ones.

- [ ] **Step 6: Type-check + build, then commit**

Run: `npx tsc -p server/tsconfig.json --noEmit` (exit 0), `npm run build` (exit 0).
```bash
git add shared/types.ts server/routes/pipelines.ts server/routes/pipelines.test.ts
git commit -m "feat(pipeline): board join helper + GET /pipelines/:id/board"
```

---

## Task 2: Client — `pipelinesApi.board`, kind-aware templates, CSV util (`src/lib/api.ts`)

**Files:**
- Modify: `src/lib/api.ts`

**Interfaces:**
- Produces: `pipelinesApi.board(id)`; `inviteEmailTemplatesApi.list(kind?)` (+ create/update already carry `kind` in the body object); `downloadCsv(filename, header, rows)`.

- [ ] **Step 1: Extend `pipelinesApi` (add `board`)**

Add the `PipelineBoard` import to the existing `@shared/types` import, and add to `pipelinesApi`:
```ts
  board: (id: string) => http<PipelineBoard>(`/pipelines/${id}/board`),
```

- [ ] **Step 2: Make `inviteEmailTemplatesApi.list` kind-aware**

Replace the `list` line:
```ts
  list: (kind?: string) => http<InviteEmailTemplate[]>(`/invite-email-templates${kind ? `?kind=${encodeURIComponent(kind)}` : ''}`),
```
(create/update already POST/PUT the full body; callers include `kind` in the body for non-invite kinds — no signature change needed there.)

- [ ] **Step 3: Add a CSV download util (bottom of the file)**

```ts
/** Build a CSV from rows and trigger a browser download. Values are quote-escaped. */
export function downloadCsv(filename: string, header: string[], rows: (string | number)[][]) {
  const esc = (v: string | number) => {
    const s = String(v ?? '')
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  const csv = [header, ...rows].map((r) => r.map(esc).join(',')).join('\r\n')
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
```

- [ ] **Step 4: Build, then commit**

Run: `npm run build` (exit 0).
```bash
git add src/lib/api.ts
git commit -m "feat(pipeline): client board api + kind-aware template list + CSV util"
```

---

## Task 3: Pipelines route + nav + `PipelinesPage` (filters + list)

**Files:**
- Modify: `src/App.tsx`, `src/components/layout/Nav.tsx`
- Create: `src/features/recruiter/PipelinesPage.tsx`

**Interfaces:**
- Consumes: `pipelinesApi.list`, `@tanstack/react-query`, `Select`/`Card`/`PageHeader` primitives.
- Produces: `/pipelines` route → `PipelinesPage`; `/pipelines/:id` route → `PipelineBoardPage` (Task 4); nav entry.

- [ ] **Step 1: Create `src/features/recruiter/PipelinesPage.tsx`**

```tsx
import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { pipelinesApi } from '@/lib/api'
import { Card, Select, PageHeader, EmptyState, Skeleton } from '@/components/ui'
import type { Pipeline } from '@shared/types'

export default function PipelinesPage() {
  const { data: pipelines, isLoading } = useQuery({ queryKey: ['pipelines'], queryFn: () => pipelinesApi.list() })
  const [role, setRole] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')

  const roles = useMemo(
    () => [...new Set((pipelines ?? []).map((p) => p.role).filter(Boolean))].sort(),
    [pipelines],
  )
  const filtered = useMemo(() => (pipelines ?? []).filter((p) => {
    if (role && p.role !== role) return false
    if (from && (p.createdAt || '') < from) return false
    if (to && (p.createdAt || '') > `${to}T23:59:59.999Z`) return false
    return true
  }), [pipelines, role, from, to])

  return (
    <div className="space-y-6">
      <PageHeader title="Pipelines" subtitle="Multi-round hiring flows. Pick one to see candidate progression." />
      <Card className="p-4">
        <div className="flex flex-wrap items-end gap-3">
          <Select label="Role" value={role} onChange={(e) => setRole(e.target.value)}
            options={[{ value: '', label: 'All roles' }, ...roles.map((r) => ({ value: r, label: r }))]} />
          <label className="text-sm">From<br /><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="input" /></label>
          <label className="text-sm">To<br /><input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="input" /></label>
          {(role || from || to) && (
            <button className="text-sm text-neutral-500 underline" onClick={() => { setRole(''); setFrom(''); setTo('') }}>Clear</button>
          )}
        </div>
      </Card>

      {isLoading ? <Skeleton className="h-24" />
        : filtered.length === 0 ? <EmptyState title="No pipelines yet" description="Create one from Sessions → Invite → Multiple Rounds." />
        : (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {filtered.map((p: Pipeline) => (
              <Link key={p.id} to={`/pipelines/${p.id}`}>
                <Card hover className="p-4">
                  <div className="font-semibold text-neutral-800">{p.role}</div>
                  <div className="text-sm text-neutral-500">{p.rounds.length} round{p.rounds.length === 1 ? '' : 's'} · {p.rounds.map((r) => r.name).join(' → ')}</div>
                  <div className="mt-2 text-xs text-neutral-400">Created {new Date(p.createdAt).toLocaleDateString()}</div>
                </Card>
              </Link>
            ))}
          </div>
        )}
    </div>
  )
}
```
Note: confirm the `.input` CSS class exists (the date inputs in `AnalyticsPage` use a class — match whatever that page uses for `<input type="date">`; if Analytics uses inline classes, copy those instead of `.input`). Confirm `PageHeader`/`EmptyState`/`Skeleton` prop names against `src/components/ui/index.tsx` and adjust.

- [ ] **Step 2: Add routes in `src/App.tsx`**

Add lazy/eager imports next to the other recruiter pages, and inside the `<Route element={<RecruiterShell />}>` group:
```tsx
<Route path="/pipelines" element={<PipelinesPage />} />
<Route path="/pipelines/:id" element={<PipelineBoardPage />} />
```
(Match the existing import style — if the file imports pages eagerly at top, do the same; `PipelineBoardPage` is created in Task 4, so add a minimal placeholder export first if needed to keep the build green, or sequence Task 4 before wiring `/pipelines/:id`. Simplest: in this task add only the `/pipelines` route + import; add `/pipelines/:id` in Task 4.)

- [ ] **Step 3: Add the nav entry in `src/components/layout/Nav.tsx`**

Insert into the `LINKS` array (after `Question Sets` or after `Results`):
```ts
  { to: '/pipelines', label: 'Pipelines' },
```

- [ ] **Step 4: Build + manual check + commit**

Run: `npm run build` (exit 0). Manually: nav shows Pipelines; `/pipelines` lists any multi-round pipelines created via the wizard, filters by role/date, and cards link to `/pipelines/:id` (board lands in Task 4).
```bash
git add src/features/recruiter/PipelinesPage.tsx src/App.tsx src/components/layout/Nav.tsx
git commit -m "feat(pipeline): /pipelines route, nav entry, filtered pipelines list"
```

---

## Task 4: `PipelineBoardPage` — read-only progression Kanban

**Files:**
- Create: `src/features/recruiter/PipelineBoardPage.tsx`
- Modify: `src/App.tsx` (wire `/pipelines/:id` if not already)

**Interfaces:**
- Consumes: `pipelinesApi.board`, `useParams`, `Badge`/`Card`/`PageHeader` primitives.
- Produces: read-only board (columns + cards). Advancement interactions are Plan 4.

- [ ] **Step 1: Create `src/features/recruiter/PipelineBoardPage.tsx`**

```tsx
import { useParams, Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft } from 'lucide-react'
import { pipelinesApi } from '@/lib/api'
import { Card, Badge, Skeleton, cn } from '@/components/ui'
import type { BoardCard, BoardColumn } from '@shared/types'

const ROUND_STATUS_LABEL: Record<BoardCard['roundStatus'], { label: string; variant: 'success' | 'info' | 'warning' | 'neutral' | 'danger' }> = {
  completed: { label: 'Scored', variant: 'success' },
  in_progress: { label: 'In progress', variant: 'info' },
  invited: { label: 'Invited', variant: 'neutral' },
  expired: { label: 'Expired', variant: 'danger' },
  none: { label: 'Invited', variant: 'neutral' },
}

function Cardlet({ card }: { card: BoardCard }) {
  const s = ROUND_STATUS_LABEL[card.roundStatus]
  return (
    <div className={cn('card p-3', card.advanceable && 'ring-1 ring-primary-300')}>
      <div className="font-medium text-sm text-neutral-800 truncate">{card.candidateName || card.candidateEmail}</div>
      <div className="text-xs text-neutral-400 truncate">{card.candidateEmail}</div>
      <div className="mt-2 flex items-center justify-between">
        <Badge variant={s.variant}>{s.label}</Badge>
        {card.score !== null ? <span className="text-sm font-semibold text-neutral-700">{card.score}</span> : <span className="text-xs text-neutral-300">—</span>}
      </div>
    </div>
  )
}

function Column({ col }: { col: BoardColumn }) {
  return (
    <div className="flex w-72 shrink-0 flex-col rounded-2xl bg-neutral-50 p-3">
      <div className="mb-2 flex items-center justify-between px-1">
        <span className="text-sm font-semibold text-neutral-700">{col.title}</span>
        <span className="text-xs text-neutral-400">{col.cards.length}</span>
      </div>
      <div className="space-y-2">
        {col.cards.length === 0 ? <div className="px-1 py-6 text-center text-xs text-neutral-300">Empty</div>
          : col.cards.map((c) => <Cardlet key={c.pipelineCandidateId} card={c} />)}
      </div>
    </div>
  )
}

export default function PipelineBoardPage() {
  const { id = '' } = useParams()
  const { data: board, isLoading } = useQuery({ queryKey: ['pipeline-board', id], queryFn: () => pipelinesApi.board(id), enabled: !!id })

  return (
    <div className="space-y-4">
      <Link to="/pipelines" className="inline-flex items-center gap-1 text-sm text-neutral-500 hover:text-neutral-700"><ArrowLeft size={15} /> Pipelines</Link>
      {isLoading || !board ? <Skeleton className="h-64" />
        : (
          <>
            <div>
              <h1 className="text-xl font-semibold text-neutral-800">{board.pipeline.role}</h1>
              <p className="text-sm text-neutral-500">{board.pipeline.rounds.length} rounds · candidate progression</p>
            </div>
            <div className="flex gap-3 overflow-x-auto pb-4">
              {board.columns.map((col) => <Column key={col.key} col={col} />)}
            </div>
          </>
        )}
    </div>
  )
}
```
Note: confirm `Badge` variant names (`success|warning|danger|neutral|info`) and that a `.card` CSS class exists — both were verified present in the codebase. If `PageHeader` is preferred over the inline `<h1>`, match the other pages.

- [ ] **Step 2: Ensure `/pipelines/:id` is wired in `src/App.tsx`**

If not added in Task 3, add the import + `<Route path="/pipelines/:id" element={<PipelineBoardPage />} />` inside the `RecruiterShell` group.

- [ ] **Step 3: Build + manual check + commit**

Run: `npm run build` (exit 0). Manually: open a pipeline from `/pipelines`; confirm columns = each round + Selected + Not-advancing; a candidate who completed+scored Round 1 shows their score and a highlighted (advanceable) card; an invited-but-not-started candidate shows "Invited" with no score.
```bash
git add src/features/recruiter/PipelineBoardPage.tsx src/App.tsx
git commit -m "feat(pipeline): read-only progression Kanban board page"
```

---

## Self-review notes (author)

- **Spec coverage (view slice):** Analytics-style filters (role/date) → Task 3; per-role board with columns=rounds+Selected+Not-advancing and cards showing per-round score/status/advanceable → Tasks 1 & 4. Advancement (drag/threshold), transition emails, CSV export action, and safeguards are **Plan 4** (the `downloadCsv` util lands here for Plan 4 to use).
- **Additive:** only new routes/pages/helpers + `shared/types.ts` view types; `invites.ts`/sessions/auth/email module untouched; single-interview surfaces unchanged.
- **Testability:** `buildBoard` (the only non-trivial server logic) is pure and unit-tested for the join/advanceable/column-placement rules; endpoints + React pages gate on `tsc`/`build` + documented manual checks (no browser/HTTP harness, consistent with prior features).
- **Score/status source:** local `db.reports`/`db.sessions` only — no Firestore reads, no change to the claim/scoring path.
- **Placeholder scan:** the two "confirm prop names / `.input` class" notes are explicit verification instructions, not TBDs — the implementer confirms against `src/components/ui/index.tsx` + `AnalyticsPage.tsx` and adjusts.
- **Follow-ups (Plan 4):** advance/select/not-advancing/move-back endpoints, the advancement service (transition emails via the `kind` engine), cross-column drag + quick-advance criteria bar + confirm/preview modal, transition-email editing (kind-aware preview), Selected CSV export, and audit log/view.
