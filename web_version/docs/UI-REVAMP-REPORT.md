# TalbotIQ product-UI revamp — completion report

**Date:** 2026-08-12 · **Branch:** `feat/mimic-marketing-site`
**Scope:** frontend/UI only. No backend logic, frozen modules, interview
internals or auth paths were rewritten.

---

## 1. Gates

| Gate | Result |
|---|---|
| `npx tsc --noEmit` | **exit 0** |
| `npm run build` | **exit 0** — built in 28.66s, 4,369 modules |
| `npm test` | **all test files passed** (48 suites) |
| Design detector (`impeccable/detect.mjs`) | **0 anti-patterns** |
| WCAG contrast audit (37 token pairs) | **37 pass · 0 fail** |
| Console errors on `/sessions` | **0** |
| `npm run lint` | ❌ **broken — no ESLint config.** Pre-existing, see §6 |

Diff: **80 files, +8,257 / −4,230.**

## 2. Behavioural safety audit

The constraint was that this stays a UI pass. I verified it mechanically rather
than by assertion — counting behavioural tokens in every changed `.ts`/`.tsx`
file at `HEAD` versus the working tree:

```
useQuery(  useMutation(  queryKey  queryFn  mutationFn  invalidateQueries
.mutate(   registerAction  autopilot  signIn  onSubmit  preventDefault
```

**Zero removals or reductions across all 76 changed source files.** Every delta
was an addition, and each is accounted for:

| Change | File | Why |
|---|---|---|
| +2 `useEffect`, +1 `signOutUser`, +1 `navigate` | `Nav.tsx` | Mobile menu: close-on-route, Escape handler, menu sign-out, menu API-key CTA |
| +1 `.refetch()` ×5 | Sessions, Templates, TemplateEditor, Analytics, QuestionSets | "Try again" buttons on new error states |
| +1 `.mutate()` | `QuestionSetsPage` | Second "New set" button inside the empty state — same existing `create` mutation |
| +1 `navigate()` | `ReplicasPage`, `PipelinesPage`, `TemplateEditorPage` | New navigation affordances |

No query keys, no mutation functions, no autopilot registrations and no auth
paths were altered.

## 3. Screens verified in a signed-in browser

Desktop 1440×900 unless noted.

| Screen | Verdict | Notes |
|---|---|---|
| **Sessions** | ✅ | Executive console: avatar chip, track/status badges, right-aligned `tabular-nums` scores, mint hero action. 20 rows render. |
| **Templates** | ✅ | Card grid, track icon plates, Prep/Answer/KPI metric chips, Adaptive/Fixed badge. |
| **Question sets** | ✅ *fixed* | Master/detail. Question textareas were clipping mid-sentence — fixed. |
| **Pipelines** | ✅ | Filter card + numbered round-sequence chips (1 Screening › 2 Technical › 3 Final). |
| **Pipeline board** | ✅ *fixed* | 5 lanes, terminal lanes tinted, quick-advance bars. Subtitle states the safety guarantee. Duplicate email line fixed. |
| **Analytics** | ✅ | KPI numerals with context lines; "Position-level insights are hidden" explains absent data instead of showing an empty chart. |
| **Report** | ✅ | Brand-band strip, score ring, recommendation pill, strengths/improve split, Export PDF. |
| **Replicas** | ✅ *fixed* | Empty state was misleading with no API key — fixed. |
| **Settings** | ✅ | Masked keys, Show toggles, Test connection, status badge. Security copy is accurate. |
| **Sessions @ 390×844** | ✅ *fixed* | Nav overflow and sideways page scroll fixed. |

## 4. Defects found and fixed during the sweep

1. **API 500s / 10 console errors.** `/api/sessions`, `/api/templates`,
   `/api/settings/avatar`, `/api/avatar/status` all returned 500 and Sessions
   rendered as *empty*. Cause: a stale dev-server process predating the Phase-A
   changes. Restarting resolved it — and also resolved the green-tinted ground
   and the "empty square" on the login card, both of which were stale CSS.
   Verified after restart: ground `#F7F5FB`, ink `#1B0B3B`, border `#E7E2F2`,
   Figtree — exactly the tokens. **0 console errors.**

2. **Nav unusable on mobile.** The seven tabs overflowed off-screen with no
   menu, making Pipelines, Analytics, Avatar studio, Settings and sign-out
   **unreachable on a phone**; it also forced the whole page to scroll sideways.
   Added an accessible disclosure menu (`aria-expanded`/`aria-controls`, Escape
   to close, closes on navigation). Desktop unchanged.

3. **Question text clipped.** `QuestionSetsPage` capped the textarea at
   `h-16`/64px — ~1.8 lines — so every real résumé-generated question was cut
   mid-sentence. Removed the override; the shared `.textarea-base` 96px
   min-height fits three lines.

4. **Error rendered as empty (Sessions).** No `isError` branch, so a failed
   fetch told recruiters they had no sessions. Added a proper error state.

5. **Misleading empty state (Replicas).** `listReplicas` tolerates partial
   failure and resolves to `[]`, so a missing Tavus key never surfaces as an
   error — the screen said "No replicas yet" and sent users to Tavus, which
   cannot help. Now names the real blocker and routes to Settings. Fixed
   presentationally via the existing `tavusKey` store signal, so the service
   contract and its four consumers are untouched.

6. **Duplicate email line.** Unnamed candidates fall back to their email, which
   was then printed again beneath itself on every pipeline card and session row.
   Suppressed when it would repeat.

7. **Legacy email shell.** `shared/inviteEmail.ts` still rendered on
   `#eff5f0`/`#dde8e0`/`#0f172a`/`#94a3b8`, so the wizard's email preview had a
   visible seam. Retoned to the violet system; the `#94a3b8` footer (2.6:1) went
   to `#645C7B` (5.9:1). Both invite-email test suites still pass.

8. **Detector findings.** `animate-bounce` on the guide's typing dots →
   opacity-only `typing-dot`. `.bg-grid` (24px-tiled hairline dot field, on all
   three auth surfaces) → `.bg-brand-wash`, two large non-tiling radial washes.

9. **Redundant brand mark.** The login card stacked a generic sparkle plate
   directly above the real TalbotIQ logo. Removed the plate.

## 5. Housekeeping

- `talbotiq-platform/DESIGN_SPEC.md` describes the **retired green system** and
  was actively misleading. Marked **SUPERSEDED** with a pointer to `DESIGN.md`.
- `DESIGN.md` rewritten from the built app; now covers product *and* marketing.
- `.playwright-mcp/` added to `.gitignore`; screenshot artifacts moved out of the
  repo root.

## 6. Not done — and why

- **The four candidate interview experiences (Chatbot, Voice, Video Avatar,
  Video) are not visually verified.** `/take/:sessionId` sits behind
  `RequireCandidate`, which redirects recruiters to `/sessions`
  (`guards.tsx:136`). That guard is correct and I did not weaken it. Their code
  was restyled onto the tokens by the screen packets and passes typecheck, build
  and tests — but nobody has seen them rendered. **To verify, sign in as a
  candidate account and open an invite link.** This is the largest open risk.
- **`npm run lint` is broken** — ESLint 8 finds no config file. Pre-existing and
  unrelated to this work. Adding a config would surface a flood of pre-existing
  findings; that is a separate decision, not something to slip into a UI pass.
- **Bundle size** — main chunk 3.59 MB (1.01 MB gzipped), no code splitting.
  Pre-existing; a build concern outside this scope.
- **Tavus key is used from the browser.** Pre-existing architecture, untouched,
  but worth a deliberate decision.
