# Multi-Round Interview Pipeline — Design Spec

**Date:** 2026-07-22
**Branch:** `feat/avatar-screening-migration`
**Status:** Draft — awaiting user review

## Problem / goal

Today TalbotIQ supports a single interview per candidate: the recruiter sets up one
interview at `/sessions/new` (`InviteWizard`), invites candidates, each candidate takes it,
and the AI scores it. There is no notion of a candidate progressing through ordered
**rounds** (e.g. Screening → Technical → Final) toward a final selection.

This feature adds **multi-round hiring pipelines**. At setup the recruiter chooses
**Single Interview** (today's flow, unchanged default) or **Multiple Rounds**. Multiple
opens a round-builder Kanban. In Results, a per-role progression Kanban lets the recruiter
advance candidates round → round by **dragging cards** or by a **score threshold / top-N**,
each advance triggering a **confirm+preview** step then a configurable transition email
(reusing the just-built email module) plus the next round's interview invite — continuing to
a **Selected** final list with CSV export, and an optional opt-in **Not advancing** lane.

## Scope & principles

- **Additive.** The single-interview path stays the current default and is byte-for-byte
  unchanged. A single-interview setup creates **no** pipeline record.
- **Reuse.** The existing interview-mode config, candidate-add + invite flow, AI scoring,
  Analytics-style filters, auth/role model, and the newly-built configurable email module.
- **Frozen modules untouched.** Sessions/templates/question-sets internals, the auth/role
  model, the invite-link `/take/:id` + claim (`materializeInviteSession`) logic, and the
  Firestore `interviews/{id}` interop field names are extended **only additively**. If any
  change would require rewriting these, PAUSE and ASK.
- **Server-side keys.** Brevo/SMTP + Firebase Admin stay server-side; no secret reaches the
  browser.
- **No silent auto-advance.** A human confirms every advancement batch.

## Verified context (facts this design relies on)

Two data stores, bridged by the invite flow:
- **Firestore `interviews/{id}`** — durable invite/interview docs, shared with a Flutter app.
  Created in `server/routes/invites.ts` (`POST /api/invites`). Link = `${origin}/take/<id>`.
  Frozen interop fields: `testId, recruiterId, recruiterEmail, recruiterName, candidateEmail,
  candidateEmailLower, candidateName, type ('video'|'chat'), title, prompt, questions,
  durationMinutes, status, keyOverrides, maxAttempts, attemptsUsed, resultPublished,
  createdAt, updatedAt`. Web-only additive fields already present: `mode` (precise
  `TrackType`), `role`, `screening`, and (from the email work) `invite` (`InviteSendStatus`).
  Flutter ignores unknown keys — the established pattern for additive fields.
- **Local Express/JSON store** — `server/store/db.ts` → `server/data/db.json`. In-memory
  `Map`s (`templates, questionSets, sessions, reports, users, settings,
  inviteEmailTemplates`) with debounced snapshot save/load. **Scoring, results, and analytics
  read from here** (`db.reports`, keyed by `sessionId`). Sessions are the one genuinely
  owned-per-recruiter surface (`recruiterId: auth.uid` server-stamped; reads filtered by
  `ownsSession`, `server/middleware/auth.ts`). **We mirror Sessions.**

Invite → session bridge (frozen): candidate opens `/take/:id` → `POST /sessions/:id/claim`
→ `materializeInviteSession` (`server/services/inviteBridge.ts`) verifies
`data.candidateEmailLower === auth.email` (403 on mismatch, 409 if completed), synthesizes a
local template + session (`id === interviewId`), marks the Firestore doc `in_progress`. On
completion, `maybeScore` (`server/routes/sessions.ts`) writes `db.reports.set(sessionId,
ResultReport)` and `syncInviteResult` mirrors score/status back to `interviews/{id}`.
`ResultReport.overallScore` (0–100, server-computed, `server/services/scoring.ts`) is the
number the pipeline's threshold advancement uses.

Auth: Firebase Email/Pw; role from `users/{uid}.role` (`'recruiter'|'candidate'`); every
`/api` call carries a Firebase ID token; `authenticate` + `requireRecruiter` gate recruiter
routes; cross-tenant access returns 404 (no existence leak). Admin = recruiter whose verified
email is in `ADMIN_EMAILS`.

Setup UI: `src/features/recruiter/InviteWizard.tsx` — now a **5-step** wizard (Mode & role →
Tailor/reuse → Add candidates → **Invite email** → **Review & send**). Per-mode config type
`TailorConfig { style, techCount, nonTechCount, difficulty, domains, model }`
(`InviteWizard.tsx`), plus a saved `QuestionSet` picker. Modes: `TrackType = 'chat' |
'chatbot' | 'video_avatar' | 'voice' | 'video' | 'two_way'` (`shared/types.ts`).

Analytics filters (to mirror): `AnalyticsFilters { track?, templateId?, role?, dateFrom?,
dateTo? }` (`shared/types.ts`), filter bar in `src/pages/AnalyticsPage.tsx`; `role` resolves
through the session's template role; dates filter `createdAt`.

Drag-and-drop: `@dnd-kit/*` installed; only consumer is a single-column sortable list
(`src/features/recruiter/QuestionSetsPage.tsx`). **No multi-column Kanban exists** — we build
it on the same primitives (`DndContext`, `useSortable`/`useDroppable`, `DragOverlay`).

The configurable email module (JUST built, uncommitted working tree):
- `shared/inviteEmail.ts` — `renderTemplate(str, vars)`, `escapeHtml`, `unknownTokens`
  (GENERIC); `MERGE_VARS` (6 invite tokens), `REQUIRED_TOKENS = ['{{interview_link}}']`,
  `renderInviteEmail(tpl, vars, opts)` shell + `exactEmailNote` + `ctaButton` +
  `defaultInviteEmailTemplate()` (INVITE-specific). **No `kind` discriminator.**
- `shared/types.ts` — `InviteEmailTemplate { id, recruiterId, name, isDefault, sender
  {verifiedSenderEmail, fromName, replyTo?}, subject, bodyHtml, cta {text,color}, branding,
  deadlineText?, createdAt, updatedAt }`; `InviteSendStatus`/`InviteSendStatusValue`.
- `server/services/inviteEmailRender.ts` — `sanitizeBodyHtml()` (GENERIC) + `buildInviteEmailHtml`.
- `server/services/brevo.ts` — `listVerifiedSenders()`, `brevoReady()` (`BREVO_API_KEY`,
  senders only; **sending stays SMTP**).
- `server/services/email.ts` — `sendMail({to, subject, html, text?, from?, replyTo?,
  headers?})` (GENERIC, per-send sender/reply-to/headers).
- `server/routes/inviteEmailTemplates.ts` — CRUD, ownership pattern (`owns`, `loadOwned`,
  `normalize`, server-stamped `recruiterId`, owner-filtered list, 404-no-leak, auto-seed
  default), store map `db.inviteEmailTemplates` keyed by template id.
- `server/routes/invites.ts` — create path renders via template (inline `emailConfig` or
  `emailTemplateId`, else legacy), `GET /senders`, `POST /test`, `POST /:id/retry`,
  per-recipient status stamped on the doc.
- `server/routes/brevoWebhook.ts` — public `POST /api/invites/brevo-webhook` (shared-secret),
  updates `interviews/{id}.invite`.
- UI: `src/features/recruiter/invite-email/` (`InviteEmailStep`, `EmailPreview`, `ReviewSend`,
  `RichTextEditor` — Tiptap with an "Insert variable" dropdown driven by the merge-var list).

## Resolved decisions

| Fork | Decision |
|---|---|
| Round → takeable interview | **Each round is its own `interviews/{id}` invite doc** (reuses the frozen `/take/:id` + claim + scoring path). Additive fields link it to the pipeline. |
| Pipeline data storage | **Local Express/JSON store**, mirroring Sessions ownership (`recruiterId` server-stamped, owner-filtered reads). No new Firestore surface. |
| Round interview modes (v1) | **Async auto-scored only**: `chatbot, voice, video_avatar, chat (Timed Q&A), video`. Two-way deferred (manual-review scoring). |
| Transition emails | **Reuse the built email module**, extended with a `kind` discriminator (`invite` default). Lean now = editable subject/body + preview + test-send + confirm; Tiptap editor, verified-sender dropdown, and webhooks come free by reuse. |
| Email module reuse | **Extend with `kind`** (option E1): one template model/store/CRUD/editor, kind-aware vars + locked tokens + render shell. Invite path stays byte-for-byte unchanged (kind defaults to `'invite'`). |
| Results placement | **New "Pipelines" recruiter area** (nav entry near Results/Sessions); today's `/results` avatar-screening page untouched. Single-interview results stay in Sessions. |
| Role → pipeline | A role may have **multiple pipeline batches**; filtered list shows them by created date; a single match opens its Kanban directly. |

## Data model (additive)

### New local-store records (`server/store/db.ts` → `db.json`)

```ts
type PipelineType = 'single' | 'multi'         // 'single' pipelines are never persisted (see Setup)
type AdvanceRule = { kind: 'threshold'; value: number } | { kind: 'topN'; value: number }

interface RoundDef {
  index: number                                 // 0-based, contiguous
  name: string                                  // "Screening", "Technical", "Final"
  mode: TrackType                               // async auto-scored subset in v1
  source?: 'tailor' | 'set'                     // reuse InviteWizard question-source
  config?: TailorConfig                         // when source === 'tailor'
  questionSetId?: string                        // when source === 'set'
  advanceRule?: AdvanceRule                      // optional default threshold/top-N
}

interface Pipeline {
  id: string
  recruiterId: string                           // OWNER — server-stamped from auth.uid
  role: string
  type: 'multi'                                  // only multi is stored
  name?: string
  rounds: RoundDef[]                             // ordered; rounds.length >= 1
  createdAt: string
  updatedAt: string
}

// 'in_round'      = currently in a round (invited / taking / scored, awaiting an advance decision)
// 'selected'      = advanced past the last round into the final Selected list (terminal)
// 'not_advancing' = moved to the opt-in rejection lane (terminal)
// 'advanced'      = transient marker set during a batch advance before currentRoundIndex is
//                   committed; resting state after a successful advance is 'in_round' in the new round
type PipelineCandidateStatus = 'in_round' | 'advanced' | 'selected' | 'not_advancing'

interface RoundProgress {
  roundIndex: number
  interviewId: string                           // the interviews/{id} doc + local session id for this round
  invitedAt: string
  // derived live at read time from db.sessions/db.reports (not duplicated here):
  //   sessionStatus, overallScore, completedAt, emailStatus
}

interface AuditEntry {
  at: string
  byUid: string
  action: 'invited' | 'advanced' | 'selected' | 'not_advancing' | 'moved_back'
  fromRound?: number
  toRound?: number
  basis?: string                                // "drag" | "threshold>=60" | "topN=5"
  emailResult?: 'accepted' | 'failed' | 'skipped'
}

interface PipelineCandidate {
  id: string
  pipelineId: string
  recruiterId: string                           // OWNER — server-stamped
  candidateEmail: string
  candidateEmailLower: string                   // assignment key (matches interviews doc)
  candidateName?: string
  role: string
  currentRoundIndex: number
  status: PipelineCandidateStatus
  perRound: RoundProgress[]                     // one per round the candidate has entered
  history: AuditEntry[]
  createdAt: string
  updatedAt: string
}
```

Store maps (added to snapshot load/save exactly like `inviteEmailTemplates`):
`db.pipelines: Map<id, Pipeline>`, `db.pipelineCandidates: Map<id, PipelineCandidate>`.
`Snapshot` gains `pipelines?: Pipeline[]` and `pipelineCandidates?: PipelineCandidate[]`.

### Additive fields on `interviews/{id}` (Flutter-safe, unknown keys ignored)

```ts
pipeline?: {
  pipelineId: string
  roundIndex: number
  pipelineCandidateId: string
}
```

Frozen fields (`testId, candidateEmailLower, type, status, resultPublished, maxAttempts,
attemptsUsed, keyOverrides, …`) untouched. Each round's doc is a normal single-attempt
invite (`maxAttempts: 1`).

### Email module `kind` extension (additive to the built module)

```ts
type EmailKind = 'invite' | 'advance' | 'selected' | 'rejection'
// InviteEmailTemplate gains:  kind: EmailKind   // default 'invite'
```

- Kind-aware merge vars (`mergeVarsFor(kind)`), superset of today's:
  - `invite`  → today's 6 (unchanged).
  - `advance` → `candidate_name, role, round_name` (the round being advanced INTO),
    `interview_link` (**locked/required**, next-round link), `recruiter_name, company`,
    optional `previous_round_name, score`.
  - `selected` / `rejection` → `candidate_name, role, recruiter_name, company`, optional `score`.
- Kind-aware locked tokens (`requiredTokensFor(kind)`): `['{{interview_link}}']` for
  `invite` & `advance`; `[]` for `selected` & `rejection`.
- Generalized render shell: `renderInviteEmail` becomes a thin wrapper over an internal
  `renderEmailShell(tpl, vars, opts, { includeLink, includeExactEmailNote })`. `invite` &
  `advance` → link + exact-email note; `selected` & `rejection` → no link, no note.
  Existing `renderInviteEmail(tpl, vars, opts)` signature/behavior preserved for the invite
  call sites (it internally passes `{includeLink:true, includeExactEmailNote:true}`).
- One store map + one CRUD router serve all kinds; list is `?kind=` filtered; a default per
  kind per recruiter is auto-seeded (`defaultTemplateFor(kind)`). `/test` becomes
  kind-aware (kind-appropriate sample vars/link).

## Setup — Single vs Multiple Rounds (`InviteWizard`)

- **Step 1 (Basics):** add a **Single Interview | Multiple Rounds** toggle (design-system
  segmented control). Single → current behavior (mode + role). Multiple → role only (mode
  moves into each round).
- **Step 2:** Single → today's Questions step, unchanged. Multiple → **round-builder Kanban**
  (`RoundBuilder`): ordered round columns; each column = name + the existing mode selector +
  the existing per-mode config (`TailorConfigPanel` / question-set picker) + optional advance
  rule. Add / rename / remove / drag-reorder rounds (reuse `@dnd-kit` sortable). Enforce ≥1
  round; modes limited to the async auto-scored subset.
- **Step 3 (Candidates):** unchanged.
- **Steps 4–5 (Invite email / Review & send):** unchanged; the Round-1 invite uses the
  existing invite email (kind `invite`).
- **Submit (multi):** `POST /api/pipelines` creates the `Pipeline`; then the existing invite
  create path creates each candidate's **Round-1** `interviews/{id}` doc (now stamped with
  `pipeline{pipelineId, roundIndex:0, pipelineCandidateId}`) + a `PipelineCandidate`
  (`currentRoundIndex:0`, `status:'in_round'`, first `RoundProgress`, first `AuditEntry`
  `invited`) and sends the Round-1 invite email. Single submit is unchanged (no pipeline).

## Results — filters + per-role progression Kanban

- **`PipelinesPage`** (new recruiter route, e.g. `/pipelines`): a filter bar mirroring
  Analytics (`role`, `dateFrom`, `dateTo`) plus **round** and **status** refinements, over
  the recruiter's pipelines. Selecting a role lists its pipeline batch(es) by date; opening
  one (or a sole match) routes to the Kanban.
- **`PipelineBoardPage`** (`/pipelines/:id`): the **progression Kanban**.
  - **Columns** = `rounds` in order → **Selected** → optional **Not advancing** lane.
  - **Cards** (one per `PipelineCandidate` in that round's column) show name, this round's AI
    score (once scored), status (invited / in-progress / completed-scored), completion state.
    Present round on the left, next round adjacent on the right.
  - **Advanceable** only when the current round's interview is **completed AND scored**
    (`db.reports.get(interviewId)` exists with a numeric `overallScore`, not `notEvaluated`).
  - Data via `GET /api/pipelines/:id/board`, which joins each candidate's current
    `RoundProgress.interviewId` to `db.sessions` (status) + `db.reports` (score) — no
    Firestore read needed for the recruiter view.

## Advancement (drag + criteria + confirm)

1. **Drag** a card from its round column to the next round column, **or** use the
   **quick-advance bar**: enter `overall score ≥ X` or `top N` → **Apply** selects every
   eligible (completed+scored) candidate in the current round who meets it.
2. Either path opens a **confirm + preview modal**: recipient list + the transition email
   preview (kind `advance`, template-driven). **Nothing commits until OK.** Cancel = full undo.
3. **On OK** (`POST /api/pipelines/:id/advance`, body: candidate ids, targetRoundIndex,
   emailTemplateId/emailConfig, basis): for each candidate — create the next round's
   `interviews/{id}` doc (reusing the invite doc-builder, stamped with `pipeline{…,
   roundIndex:target}`), append a `RoundProgress`, set `currentRoundIndex = target`
   and `status:'in_round'` (now in the new round), append an `advanced` `AuditEntry`; then send the `advance`
   transition email (with `{{interview_link}}` = the new `/take/:id`) via the reused send
   path; return **per-recipient status** (accepted/failed) with **retry** on failure.
4. The candidate takes the next round (claims → scored) → becomes advanceable in that column.
   **Repeat to the last round.**
5. **Final selection:** advancing from the LAST round moves candidates into **Selected**
   (`status:'selected'`, `selected` email, no link). **CSV export** of the Selected list.
6. **Not advancing (opt-in, OFF by default):** move a card to the lane
   (`status:'not_advancing'`); optional polite `rejection` email — recruiter must opt in,
   editable + preview.

## Safeguards

- **Undo-before-send:** advancement is two-phase — preview commits nothing; only OK creates
  docs + sends. After send, "**move back a round**" is allowed as a **logged correction**,
  permitted only while the created next-round interview is not yet completed. It **deletes the
  created next-round `interviews/{id}` doc** via the Admin SDK (recruiter owns delete), so the
  candidate's `/take/:id` link then 404s — **no change to the frozen claim path**
  (`materializeInviteSession`); it also reverts `currentRoundIndex`/`RoundProgress`. The UI
  states clearly the email itself can't be unsent.
- **Audit log:** every advance/select/reject/move-back appends an `AuditEntry` (who, when,
  from→to round, score/criteria basis, email result); a per-pipeline audit view lists them.
- **No silent auto-advance:** per-round `advanceRule` is only a *default* pre-filled into the
  quick-advance bar; a human clicks Apply → confirm for every batch.

## New server routes (all `authenticate, requireRecruiter`, owner-scoped)

- `POST /api/pipelines` — create pipeline (stamps `recruiterId`); `GET /api/pipelines`
  (owner-filtered, `?role=&dateFrom=&dateTo=`); `GET /api/pipelines/:id`; `PUT
  /api/pipelines/:id` (rounds edit, guarded); `DELETE /api/pipelines/:id`.
- `GET /api/pipelines/:id/board` — joined board (candidates × current-round status/score).
- `POST /api/pipelines/:id/advance` — batch advance/select (creates round docs + sends
  emails; per-recipient status).
- `POST /api/pipelines/:id/not-advancing` — move to lane (+ optional rejection email).
- `POST /api/pipelines/:id/move-back` — logged correction (expire created doc, revert index).
- `GET /api/pipelines/:id/export` — CSV of the Selected list.
- Email CRUD/test reused from `inviteEmailTemplatesRouter` with `?kind=`; `/test` kind-aware.

Firestore/Storage rules: **no changes** — round docs are ordinary `interviews/{id}` docs
already covered by existing rules (owner recruiter / assigned candidate). New pipeline data
lives in the local store, not Firestore.

## Client API + UI surfaces (new)

- `src/lib/api.ts`: `pipelinesApi` (list/get/create/update/remove/board/advance/notAdvancing/
  moveBack/exportCsv); extend `inviteEmailTemplatesApi`/`invitesApi.test` with `kind`.
- Setup: `RoundBuilder` in `InviteWizard` Step 2 + the Single/Multiple toggle in Step 1.
- Results: `PipelinesPage` (filters + list) and `PipelineBoardPage` (Kanban board, cards,
  quick-advance bar, confirm+preview modal, Selected column, Not-advancing lane, audit view,
  CSV export). Reuse `src/components/ui/*`, the Kanban built on `@dnd-kit`.
- Transition-email editing reuses `RichTextEditor` + `EmailPreview` (kind-parameterized),
  surfaced inside the confirm+preview modal (edit/save/load/test the `advance`/`selected`/
  `rejection` template) and/or a small template manager.

## Build order (phased implementation, one plan)

1. **Data model + store** — `Pipeline`, `PipelineCandidate`, `RoundDef`, additive
   `interviews/{id}.pipeline`, store maps + snapshot wiring, `EmailKind` extension to the
   email module (kind-aware vars/locked-tokens/shell, default `'invite'`). Confirm schema.
2. **Setup** — Single/Multiple toggle + `RoundBuilder` Kanban (reuse mode config per round).
3. **Round-1 wiring** — multi submit creates pipeline + Round-1 invite docs + candidates;
   per-round interview instance + scoring join verified.
4. **Results** — `PipelinesPage` filters + `PipelineBoardPage` progression Kanban (columns =
   rounds; cards with live scores/status).
5. **Advancement** — drag + quick-advance-by-criteria + confirm/preview modal +
   `advance` endpoint (create next-round doc + send email + per-recipient status).
6. **Transition emails** — `advance`/`selected`/`rejection` templates (kind-aware defaults,
   preview, test-send) end-to-end.
7. **Final Selected column + CSV export**; opt-in **Not-advancing** lane + rejection email.
8. **Safeguards** — undo-before-send, move-back correction, audit log/view, no silent auto-advance.
9. **Verify** against acceptance criteria (multi-account, full round-to-final walkthrough).

## Testing

- Unit: `mergeVarsFor`/`requiredTokensFor`/`renderEmailShell` per kind; advance eligibility
  (completed+scored gate); threshold/top-N selection; CSV export; move-back doc-expiry.
- Server: pipeline CRUD owner isolation (404 no-leak); advance creates a correctly-stamped
  `interviews/{id}` doc + sends the kind `advance` email; board join reads score from
  `db.reports`; email `/test` kind-aware.
- Manual: full walkthrough — create multi pipeline → invite Round 1 → candidate takes+scored
  → advance (drag & threshold) with confirm/preview → next-round email + link works → repeat
  → Selected + CSV → optional rejection; single-interview path unchanged.

## Guardrails restated

Additive only. Single-interview path unchanged. Frozen modules (sessions/templates/question
-sets internals, auth/role, invite-link/claim logic, Firestore interop field names) untouched
— round docs reuse the existing invite doc shape + `/take/:id` + claim path. Brevo/SMTP +
Firebase Admin keys stay server-side. `shared/*` stays the single source of truth for
cross-boundary shapes. If implementation reveals a needed change to any frozen module or the
just-built email files beyond the additive `kind` extension, PAUSE and ASK.

## Open items (defaulted; flag to change at review)

- Results placement → **new "Pipelines" area under Results** (not reshaping `/results`).
- Role → **multiple pipeline batches** allowed (listed by date).
- Two-way rounds → **deferred** to a later phase (manual-review scoring).
- Per-round timers → v1 reuses the existing `DEFAULT_TIMING` applied at materialization
  (`inviteBridge`); a per-round timer control is not exposed in the round builder yet.

## Acceptance criteria

- [ ] Setup offers Single (default, unchanged) vs Multiple Rounds; Multiple opens the
      round-builder Kanban (add/rename/remove/reorder; per-round mode + config + optional rule).
- [ ] Candidates are invited into Round 1 via the existing invite flow.
- [ ] Results has Analytics-style filters (role, date, + round, status); selecting a role
      opens the progression Kanban for a multi-round role.
- [ ] Cards show per-round scores; advanceable only after that round is completed + scored.
- [ ] Advance by drag AND by score threshold / top-N; a confirm+preview modal precedes any send.
- [ ] Advancing creates the next-round interview + per-candidate `/take` link and sends a
      configurable `advance` email; flow repeats to the final round.
- [ ] Final round → Selected list (drag/criteria) with a `selected` email + CSV export;
      optional opt-in rejection lane/email.
- [ ] Transition emails are configurable, previewable, test-sendable, per recruiter; keys
      server-side (reuse of the built module + `kind`).
- [ ] Additive; single-interview path unchanged; frozen modules & auth/invite-link logic
      untouched; interop field names preserved; undo-before-send + audit log present.
