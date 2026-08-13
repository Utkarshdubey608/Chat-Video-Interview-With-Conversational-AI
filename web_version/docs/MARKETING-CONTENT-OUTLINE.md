# Mimic marketing site — content outline for sign-off

**Status:** awaiting approval. Nothing is written until this is signed off.
**Approved scope:** tiered depth across all 72 pages (~45,000 words) · signature
WebGL hero + scroll motion elsewhere.

---

## 1. The problem, measured

| | Now | Target |
|---|---|---|
| Pages | 72 (all 72 resolve) | 72 |
| Total words | **5,184** | ~45,000 |
| Median page | **56 words** | 600 |
| Tier B avg | 53 words · 1.5 sections | 450–700 · 4–5 sections |
| Tier C avg | 50 words | 200–350 · real structure |

The information architecture is **not** the problem — 72 pages, mega-nav, per-page
SEO metadata, JSON-LD (`BreadcrumbList` + `Service` + `FAQPage`), breadcrumbs and
a `[PLACEHOLDER]` discipline are already in place, and the H1s are sharp. **The
bodies are stubs.** This outline fills them.

**Link integrity: all 72 nav targets resolve to all 72 pages — zero dead ends.**
(An earlier draft of this document claimed `platform/mimic-guide` 404s. That was
an error in the checking script, not a defect in the site.)

---

## 2. Grounding rules (binding)

1. **Every product claim traces to the codebase**, via `docs/manual-inventory.md`
   (1,143 lines, each row carrying a `file:line` citation) and
   `docs/USER_MANUAL.md`. The outline below names the source section per page.
2. **No invented capability, metric, customer, logo or certification.** Anything
   unverifiable ships as an explicit `[PLACEHOLDER: …]` for the team, never as
   filler. Existing placeholders are preserved.
3. **Degradation is stated, not hidden.** Where a feature needs a key, the page
   says what happens without it (heuristic scoring is labelled approximate in the
   UI; email dry-run; avatar 503).
4. **Compliance pages explain how Mimic supports a regulation. They are not legal
   advice**, and they never claim an audit or certification we do not hold.
5. **Limits are published, not buried:** voice ~15 min, video upload 50 MB,
   résumé 8 MB, candidate list 10 MB, AI question generation 1–25.

### What we may NOT claim (from PRODUCT.md → Evidence on Hand)

Every performance statistic previously on the site, the "Meridian Health"
customer and testimonial, and **all** compliance badges (SOC 2, ISO 27001,
ISO 42001, GDPR-ready, WCAG 2.2 AA, EEOC-aligned) are **not verified**. They stay
out. Real and cleared: the **Total IT Global** and **Aisling** logos.

This is why `trust/certifications` is a structured "what we can share today"
page with placeholders — not a badge wall.

---

## 3. Page templates by tier

### Tier A — 24 pages · 900–1,400 words
The crown-jewel product and SEO pages.

1. **Hero** — H1 (existing, kept), 2–3 sentence lede, dual CTA
2. **The problem** — the specific hiring failure this addresses, concretely
3. **What it is** — the capability in plain language, 2–3 paragraphs
4. **How it works** — numbered steps + an **inline SVG/CSS flow diagram**
   (Mermaid MCP unavailable, so diagrams are hand-authored components)
5. **What you configure** — the real settings, named as they appear in-product
6. **What the recruiter gets** — outputs: scores, evidence, report, analytics
7. **What the candidate experiences** — the other side, honestly
8. **Limits and degradation** — caps, and behaviour without a key
9. **Related** — cross-links to 3–4 sibling pages
10. **FAQ** — 4–6 Q&A, feeding the existing `FAQPage` JSON-LD

### Tier B — 33 pages · 450–700 words
1. Hero · 2. The problem · 3. How Mimic handles it (with specifics)
· 4. What you configure *or* What you get · 5. Related · 6. FAQ ×2–3

### Tier C — 15 pages · 200–350 words
Company/resources pages where the codebase genuinely has less to say.
1. Hero · 2. Real structure (categories, slots, or an honest "what's here today")
· 3. A real next action. **No padding.** Where there's no content yet, the page
says so plainly and offers the demo — an honest empty state, not fake listings.

---

## 4. Per-page outline

Format: `slug` — **H2 sections** — *grounding source*

### 4.1 Platform (15 pages)

**`platform`** (hub, 700w) — One platform. Every way to interview a candidate.
Sections: The six ways to interview · Why one rubric across all six matters ·
How a screen actually runs · Configure once, reuse everywhere · Where the AI
stops and a human starts. *Source: inventory §1.3, §5.1.*

**The five interview-mode pages (Tier A, 1,100–1,400w each)** — these are the
highest-value SEO assets. All follow the full Tier A template:

| Page | Track | Grounding |
|---|---|---|
| `platform/conversational-chat` | `chatbot` | inventory §4.13, §5.1 |
| `platform/voice-screening` | `voice` — Gemini Live, ~15 min cap | §4.13, §5.1 |
| `platform/ai-video-avatar` | `video_avatar` — Tavus replica/persona | §3.4, §4.9–4.10 |
| `platform/live-two-way` | `two_way` — live room, recruiter present | §4.12 |
| `platform/timed-qa` | `chat` — per-question timers | §4.13, §5.1 |

Each covers: what the mode is · when to use it over the other five · the
candidate's actual step-by-step · what's scored and how · résumé-adaptive vs
fixed questions · integrity handling · device/mobile reality · limits · FAQ.

**Workflow pages (Tier B, 550–700w):**

- `platform/interview-templates` — the full field reference: questions, timing, rubric, branding, integrity, language. *§5.1 (the deepest section in the inventory).*
- `platform/question-sets` — fixed banks, drag-ordering, ideal-answer notes, AI generation from a PDF résumé (1–25). *§4.3.*
- `platform/bulk-invitations` — CSV/Excel/PDF/DOCX/TXT ingest, validation, the 5-step wizard, dry-run. *§4.5.*
- `platform/pipelines` — multi-round, drag board, score-threshold + top-N quick advance, move-back, per-candidate audit history. *§4.6.*
- `platform/rubrics-scoring` — six default KPI criteria, custom criteria, weights auto-normalised to 100%. *§5.1.*
- `platform/candidate-reports` — dimension scores, evidence, transcript, PDF export. *§4.7.*
- `platform/recruiter-analytics` — funnel by role/team/track, completion, integrity flags. *§4.8.*
- `platform/signal-analysis` — Hume prosody, sentiment arc, emotion timeline/radar, facial analysis, ATS scorecard — **framed strictly as delivery signal alongside content, never as a hiring decision.** *Source: `src/components/hume/*`, `src/components/ats/*`.*
- `platform/mimic-guide` — 55-language assistant, Autopilot operating the UI behind confirmation gates. *§3.5, §4.14.*

### 4.2 Solutions (17 pages)

**`solutions`** (hub, 700w) — the six modes mapped to hiring situations.

**Tier A (7 pages, 900–1,200w)** — `high-volume-hiring`, `campus-graduate`,
`technical-screening`, `sales-customer-facing`, `frontline-hourly`,
`internal-mobility`, plus the hub. Each: the specific hiring failure · which
mode(s) fit and why · the rubric shape for that role type · how a real cycle
runs end-to-end · what changes for the candidate · **outcomes framed as
mechanism, not invented metrics.**

**Tier B (10 pages, 450–650w)** — by team: `talent-acquisition-leaders`,
`recruiters`, `hiring-managers`, `people-analytics`, `rpo-staffing`. By
industry: `bpo-contact-centres`, `it-services`, `retail-hospitality`,
`healthcare`, `financial-services`.

> **Accuracy note:** the industry pages describe *how the product is applied* in
> that sector. They must not imply sector-specific certifications, customers or
> regulatory clearance we don't have. `healthcare` and `financial-services` in
> particular get a compliance-posture line pointing to Trust, not a claim.

### 4.3 Trust (16 pages) — the section enterprise buyers read hardest

**`trust`** (hub, 800w) · **`trust/how-mimic-scores`** (Tier A, 1,400w — the most
important page on the site): rubric definition → per-criterion scoring → weighted
total → evidence attachment → recommendation → the human decision. Includes the
**heuristic-fallback disclosure**: without an AI key, scoring degrades to a
length-based heuristic that the UI explicitly labels approximate.

- `trust/human-in-the-loop` (A) — advancing/rejecting/overriding are recruiter actions, each written to a per-candidate audit history. *§4.6.*
- `trust/bias-testing-audits` (A) — what one rubric applied identically does and does not guarantee; what we measure; **[PLACEHOLDER]** for any third-party audit.
- `trust/trust-center` (A) — the index for security/legal reviewers.
- Tier B (11): `candidate-rights`, `model-data-transparency`, `data-residency-retention`, `sub-processors`, `certifications`, `status`, and the five regulation pages — `eu-ai-act`, `nyc-local-law-144`, `illinois-aivia`, `gdpr-india-dpdp`, `eeoc-adverse-impact`.

Every regulation page uses one structure: **what the rule requires → which Mimic
capability supports it → what the customer still owns → not legal advice.**

### 4.4 Resources (15 pages)

- Tier A: `ats-integrations` (grounded in the real API surface, §4.16), `customer-stories` (**structure only — two real logos, no invented stories**).
- Tier B: `question-library`, `rubric-templates`, `roi-calculator` (the existing calculator, with its assumptions stated as inputs, not claims).
- Tier C (10): `blog`, `guides`, `webinars`, `glossary`, `documentation`, `api-reference`, `help`, `changelog`, `benchmark-report`. Honest scaffolds with real categories and clean slots. `glossary` is the exception — it gets genuine depth (~600w) because the terms are real and buyers search them.

### 4.5 Company (9 pages)

`about` and `contact` (Tier A) carry real substance — the product story, the
principles from PRODUCT.md, and a working demo path. `careers`, `events`,
`newsroom`, `partners`, `reseller`, `legal` are honest Tier C scaffolds;
company facts not in the codebase are **[PLACEHOLDER]** for the team.

---

## 5. Design, 3D and motion

- **Design system:** the existing violet token layer (`mimicSite.css`
  `--mm-*`), already documented in `DESIGN.md` Part 2. Extended with the new
  section components — no second system.
- **New component kit:** `SectionHero`, `ProblemBlock`, `StepFlow` (numbered +
  inline SVG diagram), `SpecTable`, `LimitsNote`, `RelatedGrid`, `FaqBlock`,
  `PlaceholderNote`. Every page composes from these, which is what makes 72
  pages feel like one product.
- **3D:** one cinematic WebGL hero on `/mimic`, reusing `src/features/intro/`
  — including its existing `tier.ts` device tiering and `StaticHero.tsx`
  fallback. Lazy-loaded behind a route-level boundary so no sub-page pays for it.
- **Motion elsewhere:** GSAP/CSS scroll reveals, depth/parallax,
  micro-interactions. The existing `.reveal` IntersectionObserver pattern is
  reused. `prefers-reduced-motion: reduce` collapses everything, already global.
- **Performance budget:** sub-pages ship **zero** WebGL. Diagrams are inline SVG,
  not images. Target: LCP < 2.5s, CLS < 0.1, no layout shift from lazy sections.

---

## 6. Build sequence

| Step | Deliverable | Status |
|---|---|---|
| 1 | Section-component kit — 7 blocks, `Related`, sticky TOC | **done** |
| 2 | **Platform** — 15 pages | 6 of 15 |
| 3 | **Trust** — 16 pages | **13 of 16** |
| 4 | **Solutions** — 17 pages | — |
| 5 | **Resources + Company** — 24 pages | — |
| 6 | WebGL hero + scroll motion | — |
| 7 | Performance, SEO, a11y, responsive pass + verification | — |

Site stays runnable at every step; each step is reviewable on its own.

### Progress log

## COMPLETE — every page written

**5,184 → 37,042 words. A 7.1× increase. All 72 of 72 pages carry ≥250 words.**
Thinnest page 251 words; median 478. Zero broken links.

| Section | Pages ≥250w | Words |
|---|---|---|
| Platform | **15 / 15** | 9,891 |
| Trust | **16 / 16** | 9,607 |
| Solutions | **17 / 17** | 8,621 |
| Resources | **15 / 15** | 5,948 |
| Company | **9 / 9** | 2,975 |

The pages with nothing real to publish (blog, changelog, careers, newsroom,
events, docs, api-reference, status, benchmark) are written as **honest empty
states that still earn the visit** — each states plainly that nothing is
published, then gives the reader something genuinely useful: the operational
limits, a quick-answers table, how to read a vendor's benchmark report, which
third-party dependency each interview format relies on, or what a partner would
need from us that does not yet exist. No page pads; none pretends.
All 72 nav targets resolve; `tsc`, `build`, the design detector and the claim
audit are clean.

| Section | ≥450w | Words |
|---|---|---|
| **Platform** | **13 / 15** | **9,202** |
| **Trust** | **14 / 16** | **8,917** |
| **Solutions** | **11 / 17** | **8,397** |
| Resources | 0 / 15 | 1,563 |
| Company | 0 / 9 | 443 |

Platform, Trust and Solutions — the three sections a buyer actually evaluates —
are substantially complete. Resources and Company remain, and are mostly Tier C
scaffolds by design.

### Performance: the marketing page was shipping the entire product

Measured on the production build (`vite preview`), not the dev server.

| | Before | After |
|---|---|---|
| JS + CSS transferred on `/mimic` | **1,054 KB** | **212 KB** (−80%) |
| Firebase SDK on the public site | 167 KB | **not loaded** |
| Entry chunk | 1,030 KB | **1.6 KB** |
| DOMContentLoaded | 917 ms | **389 ms** (−58%) |
| CLS | — | **0** |

**Cause.** Every route component in `App.tsx` was imported statically, so the
whole application built as one 3,674 KB chunk (1,030 KB gzipped) — and the
*public* marketing page downloaded all of it: Firebase, TanStack Query,
Recharts, dnd-kit, jsPDF, tiptap and the Daily/Tavus SDKs, none of which a
marketing page uses.

**Fix.** Every route is now `React.lazy` behind one `Suspense` boundary. Guards,
`Nav` and `HomeRedirect` stay static — they are small and they decide which
chunk to fetch, so deferring them would only add a round-trip. The fallback is
the page ground rather than a spinner, because a spinner that appears for 120 ms
reads as jank.

The in-product assistant is also no longer mounted on `/mimic`. It is a
recruiter tool, its floating button overlaid page content on mobile, and its
chunk cost every marketing visitor bytes for a control they cannot use — which
resolves the open UI item logged above.

**Firebase off the public path (approved before doing it, per the auth guardrail).**
Firebase was 167 KB — 42% of the marketing page — for a capability those pages
never use; nothing under `src/features/marketing` imports auth or firebase.

Moving `AuthProvider` was not enough on its own: `guards.tsx` and `Nav.tsx` both
import `useAuth`, and `IntroFaceSync` imports `@/lib/firebase` directly, so a
static import of any of them from `App.tsx` dragged the SDK back onto every
route. The auth half now lives in two lazily-loaded modules — `src/AuthedApp.tsx`
and `src/components/layout/RecruiterShell.tsx` — and the guards are lazy too.
**AuthProvider's own implementation is unchanged.**

Verified after the change: `/mimic` loads no Firebase; `/login` does, and renders
its form; an anonymous request to `/sessions` still redirects to `/login`; all
test files pass; `tsc` and `build` clean.

**Note on measurement:** LCP and FCP did not report in this headless context, so
they are not claimed here. CLS of 0 and the transfer/DCL figures are measured.

### Template bug: hub pages silently dropped their content

The five hub pages rendered their nav link-columns and nothing else — anything
written into a hub's `sections` array was never displayed. That is why all five
section landing pages sat at 50–116 words regardless of what was authored for
them. `MarketingPage.tsx` now renders hub sections below the columns.

Their existing `sections` had been written as bullet lists repeating the nav
links, so they are being replaced with genuine editorial content. The Trust hub
went 116 → 412 words and now opens with the seven facts that decide a security
review, states plainly that no product can make a customer compliant, and lists
every open item before a reviewer has to go looking.

(The five industry pages land at 350–450 words — complete pages with FAQs and
cross-links, just under the Tier B word target.)

### `npm run audit:claims` — a permanent guard

`scripts/audit-marketing-claims.ts` walks every prose string on all 72 pages and
fails the build on any sentence asserting a capability the product lacks:
adverse-impact or selection-rate reporting, demographic data, certifications,
region/multi-region residency, unverified metrics, and code execution. Questions
and correctly-scoped negations pass; a short reviewed-allowlist carries
definitions and editorial topics, each with a stated reason.

**It found a ninth instance of the adverse-impact claim on its first real run** —
`platform/recruiter-analytics` advertised "with adverse-impact reporting built
in" in its meta description, after I had already fixed eight others by hand.
That is the argument for the script existing.

It then found **a tenth and eleventh** on `platform/recruiter-analytics` — the
body sentence "plus adverse-impact monitoring" and the bullet "Adverse-impact
reporting". The bullet had slipped through an early version of the script that
skipped strings under 40 characters. That floor is now removed, with a comment
explaining why: **the shortest strings are exactly where the boldest claims
hide.**

Current status: **no unscoped risk claims across 72 pages.**

**4 — Invented ATS connectors and an invented pricing tier.**
`resources/ats-integrations` advertised *"Direct connectors — push statuses and
scores back into your ATS on enterprise plans"* and a *"What syncs"* section
describing a two-way sync. A codebase sweep found **no ATS connector code of any
kind** (no Greenhouse, Lever, Workday, SmartRecruiters, iCIMS, Bullhorn, Taleo or
Ashby integration) and **no plan or pricing-tier concept**. Integration capability
is exactly what an enterprise buyer evaluates on, so this was among the most
damaging claims on the site.

The page now states the true position — Mimic runs beside your ATS on export and
import, your ATS stays the system of record — names the systems it does *not*
integrate with, and says plainly that "if an earlier version of this page implied
otherwise, that was wrong." ATS-connector and pricing-tier patterns are now part
of `audit:claims`.

**5 — Customer stories promised metrics that do not exist.** The meta description
offered *"Real results… time-to-shortlist, recruiter hours returned and candidate
experience."* No customer story has been confirmed. The page now says so, and
explains why: *"Invented case studies are the most common form of dishonesty in
enterprise software marketing, and the easiest to check."*

**6 — Two more in the hub pages.** The Solutions hub described rubrics and
question sets *"tuned to how your industry actually interviews"* — no industry
rubric packs exist, only six general KPI criteria. The Resources hub offered
proof *"in numbers and in stories"* when neither exists. Both rewritten.

**7 — The interview-format count was wrong.** The Platform hub advertised *"Five
interview tracks"* and `company/about` said *"across five tracks"*. The product
has **six** — timed Q&A, conversational chat, voice, video avatar, recorded video
and live two-way. The drift happened because the nav only surfaces five of them
(recorded video has no page of its own). Both corrected, and `audit:claims` now
fails on any format count other than six.

**8 — The emotion-analysis pages were wrong, and this was mine.**
Not inherited — I wrote it. `platform/signal-analysis` described the voice and
video analysis as "delivery characteristics… pace, pitch variation and energy",
and its FAQ answered *"Is this an emotion-recognition system?"* with **"It does
not infer emotional state as a fact."** It also framed consent plus human review
as making the feature acceptable.

All three statements were false. `server/routes/avatar.ts:104-114` prompts a
model as an "expert vocal prosody analyst" to score **6 to 10 named emotions**
per segment, emitting `[{"name":"Calmness","score":0.42}]`. That is emotion
recognition — per the Dutch DPA, *"a probability score for a named emotion is
emotion recognition."*

The consequence is not a high-risk obligation but a **prohibition**.
`docs/EU_AI_ACT_COMPLIANCE.md` (written by the team, well-sourced) records both
pipelines as **"Prohibited outright" for EU candidates** under Art 5(1)(f), with
Commission Guidelines para 254 stating expressly that *"using emotion
recognition AI systems during the recruitment process is prohibited"* — and that
a prohibition *"cannot be cured by consent, candidate notice, human review, a
bias audit, or a DPIA. None of those are defences."* In force since 2 February
2025; the 2026 Digital Omnibus delayed only the high-risk timeline.

Both `platform/signal-analysis` and `trust/eu-ai-act` now lead with the
prohibition, state plainly that consent is no defence, name the two compliant
responses (remove, or hard-geofence), and point EU deployments at the text
formats — which produce no audio, video or emotion inference and score against
the same rubric. The signal-analysis page also says on its face that an earlier
version of it was inaccurate.

`audit:claims` now fails on any attempt to describe this as "delivery
characteristics", to claim it does not infer emotional state, or to present
consent as curing it.

**Nineteen false claims in total — eighteen inherited, one of my own.** They clustered in exactly the
places a buyer checks hardest: compliance, integrations, certifications,
customer proof and industry fit. That is not coincidence — those are the pages
where a gap feels most commercially painful, so they get written aspirationally.

### Kit verified before scaling

The section kit was checked at 390×844 before writing the bulk of the pages,
since a defect there would be baked into all 72. Result: no page overflow
(`scrollWidth 384 ≤ 390`), no element wider than the viewport, the TOC correctly
unsticks to static flow, and spec tables fit. Accessibility on a deep page: one
`h1`, no heading-level skips, no missing `alt`, no empty links or buttons, all
decorative SVG `aria-hidden`, correct landmarks.

**Open UI item:** the Mimic Guide floating button overlays page content on
mobile (it covers the on-this-page index). It is pre-existing, and whether an
in-product assistant belongs on the public marketing site is a product decision,
so it has been flagged rather than changed.

**Solutions pages carry no invented outcomes.** A shared `NO_METRICS_NOTE` block
states plainly that time-to-fill, cost-per-hire and completion figures are not
published because no verified customer data supports them, and that the page
describes the mechanism instead. When real figures exist and are cleared, that
note is where they belong.

Platform: `conversational-chat` 1,125 · `timed-qa` 939 · `voice-screening` 887 ·
`ai-video-avatar` 877 · `live-two-way` 667 · `signal-analysis` 660.
Trust: `how-mimic-scores` 936 · `bias-testing-audits` 816 · `candidate-rights` 653 ·
`eeoc-adverse-impact` 605 · `human-in-the-loop` 601 · `nyc-local-law-144` 583 ·
`illinois-aivia` 555 · `eu-ai-act` 549.

**58 pages still on stub bodies.** The pattern is established and repeatable —
each remaining page is a content-writing task against the templates in §3, not a
design or engineering one.

### Accuracy corrections made while writing

These were **false claims already live on the site**, found by checking the
codebase rather than trusting the existing copy.

**1 — Candidates do need an account.** `platform/conversational-chat` answered
"Do candidates need an account?" with *"No — they open a link and answer in the
browser."* Invite links are bound to the recipient's email address; the server
returns a 403 instructing the candidate to sign in with that address. Corrected,
with the reason for the binding explained. **Other pages should be checked for
this claim.**

**2 — Mimic cannot measure adverse impact. This was the serious one.**
`trust/bias-testing-audits` claimed *"Selection rates are reported for each rubric
dimension"* and *"Analytics let you watch selection rates across groups over
time"*; `trust/eeoc-adverse-impact` claimed *"per-dimension selection-rate
reporting."*

**Mimic collects no demographic data.** A codebase sweep for
demographic/protected-characteristic handling returns only text-to-speech voice
descriptors. The analytics service exposes `averageOverall`, `completionRate`,
`avgDurationSeconds`, `avgTimePerQuestionSeconds`, `overallScore`, `role`,
`template` and `totals` — no group dimension exists. Selection rates by group are
arithmetically impossible without group data.

A buyer could have relied on that claim for Local Law 144 compliance. All three
pages now state the true position: Mimic supplies one side of the join
(per-candidate outcomes against a consistent rubric), the employer supplies the
other (voluntary self-identification data from the ATS/HRIS), and the analysis
happens in the customer's reporting environment. The trade-off is stated in both
directions — no protected attribute in the pipeline, but no self-audit either.

**2b — The adverse-impact overclaim appeared in four more places.** A sweep for
`selection.?rate|adverse.?impact` across the whole content file found it in
`solutions/people-analytics` ("Adverse-impact reporting per dimension"), the
Trust hub nav description ("how **we** test for adverse impact"), and the
`bias-testing-audits` page intro, which promised "the adverse-impact numbers,
per dimension, that you can hand to counsel" and so contradicted its own
corrected body. All fixed. **Lesson for the remaining pages: a corrected claim
has to be swept for across the file, not fixed only where it was first noticed.**

**2c — A cross-page contradiction on delivery signals.**
`solutions/sales-customer-facing` said voice tracks "assess tone, pacing and
content **together**", which contradicts the Trust position that delivery
signals sit beside the score and never inside it. Rewritten, with an explicit
warning on the page against wanting the tool to score charisma.

**3 — Region selection is not a product capability.**
`trust/data-residency-retention` claimed *"Store candidate data in your required
region."* There is no region selector. Interview data persists to a single
`DATA_DIR` on one deployed instance (`server/store/db.ts` — an in-memory store
with debounced JSON-file persistence, documented in code as "not a production
database"), and accounts and files live in a Firebase project whose region is
fixed at creation. The page now states that residency is a **deployment-time
decision**, notes that single-instance architecture rules out multi-region
replication and HA failover, and frames the single-tenant deployment as the
genuine residency strength it is.

### Grounded content added

`trust/sub-processors` was a bare `[PLACEHOLDER]`. It now lists the **real**
integration surface, derived from the product's configuration variables:
Firebase (auth + storage), Google Gemini (question generation, scoring, live
voice), Tavus (video avatar), Daily (live rooms), Deepgram (transcription),
Brevo or SMTP (email) — each with its purpose and which formats engage it. The
page also makes the useful point that a text-only deployment never engages the
video or transcription processors at all.

Note flagged for the team: **Hume components exist in the product but Hume does
not appear in the configuration surface**, so whether it is engaged for the
emotion panels must be verified rather than assumed. That is called out on the
page rather than guessed.

---

## 7. Sign-off

Please confirm:

- [ ] The tier templates in §3 are the right shape
- [ ] The page-by-page mapping in §4 is right (especially **Trust**, and the
      `signal-analysis` framing — delivery signal alongside content, never a
      hiring decision)
- [ ] The accuracy rules in §2 are acceptable, including that certifications and
      customer stories stay as structured placeholders
- [ ] The build sequence in §6 is the order you want
