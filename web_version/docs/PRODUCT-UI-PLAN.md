# Product UI — what to change for a Fortune 500 feel

Recommendations for the **recruiter workspace and candidate interview** (roughly
30 screens). The marketing site at `/mimic` is already rebuilt; this is the plan
for everything behind the login.

Ordered by impact per unit of effort. Nothing here has been implemented — the
agreed scope for this pass was the marketing site.

---

## The finding that matters most

**The product runs four different visual identities.** This is the single biggest
thing separating it from an enterprise-grade product, and it is worth more than
any amount of component polish.

| Surface | Ground | Accent | Where |
|---|---|---|---|
| Marketing site | Lavender / white | **Violet `#6B2BE0` → magenta `#C42C93`, mint `#8FE3D0` actions** | `/mimic` — done |
| Recruiter workspace | Green-tinted `#eff5f0`, borders `#dde8e0` | Violet `#6B2BE0` | `tailwind.config.js` |
| Candidate interview | White | Dark green `#0d5c3a` | `server/store/defaults.ts` → `DEFAULT_BRANDING` |
| Avatar screening room | Near-black `#080808` | Gold `#f0c040` | `tailwind.config.js` → `brand.*` |

**Good news:** the workspace's primary is *already* `#6B2BE0` — the same violet
the marketing site now uses. The work is smaller than it looks. What actually
clashes is the **green-tinted ground** (`#eff5f0` / `#dde8e0`), the **dark-green
candidate default**, and the **gold** avatar room.

A buyer who sees the marketing site, signs in, and then sends a candidate an
interview passes through three unrelated colour worlds in about ninety seconds.
Enterprise software reads as expensive largely because it refuses to do this.

There is a second, quieter version of the same problem in typography:
`index.html` loads **Syne** and **DM Sans**, but `tailwind.config.js` declares
`sans: Roboto` and `display: Figtree`. Two families are downloaded on every page
load and never used.

---

## Priority 1 — Unify the identity (highest impact)

**Effort: 1–2 days. Touches: `tailwind.config.js`, `src/index.css`,
`server/store/defaults.ts`, `index.html`.**

**Confirmed by the user: violet everywhere.** The palette is the one in
`DESIGN.md`; no further brand decision is outstanding.

1. Replace the green-tinted `background: #eff5f0` and `border: #dde8e0` in
   `tailwind.config.js` with the lavender ground and hairline
   (`#FAF7FE` / `#EAE3F5`). The green is a leftover from an earlier TalbotIQ look
   and no longer matches anything.
2. Add `magenta`, `mint` and the two gradient tokens to the Tailwind theme so app
   screens can reach the same spectrum, not just the primary violet.
3. Change `DEFAULT_BRANDING.accentColor` from `#0d5c3a` to `#6B2BE0`, so a
   recruiter who never touches branding still sends candidates something that
   matches. Recruiters who *have* set a custom accent keep theirs — this only
   moves the default. Note this also changes the default e-mail button colour in
   `shared/inviteEmail.ts`, which hardcodes `#0d5c3a` in four places.
4. Keep the avatar screening room dark — a live video call genuinely wants a dark
   surround, and that is a considered decision rather than a clash. But restate
   it in `--mm-violet-dd` `#2A1259` with mint accents instead of gold-on-black,
   so it reads as the same product in a different mode.
5. Adopt **mint for primary actions** in the workspace, the way the marketing
   site now does. This is the single change that will make the app feel like the
   same company as the website.
6. Drop the unused Syne and DM Sans font links, and set Figtree as the app's text
   face too. Free performance win on every page, and one family across the funnel.

---

## Priority 2 — Make the report the flagship screen

**Effort: 2–3 days. Touches: `src/features/recruiter/ReportPage.tsx`.**

The per-candidate report is what a hiring manager actually looks at, what gets
exported to PDF, and what gets forwarded to people who never log in. It is the
screen that decides whether the product feels serious.

1. **Give the score and the recommendation a proper masthead.** Right now the
   gauge and the badge sit in a small card alongside the summary. Make the top of
   the report a decisive band: candidate, role, format, overall score at display
   scale, recommendation, and the export action.
2. **Lead with evidence, not charts.** The strongest thing this product does is
   attach the answer to the score. Promote the per-question breakdown above the
   radar chart, and show the scoring evidence inline rather than behind an
   accordion click.
3. **Make the two honest-degradation banners look designed**, not like error
   states. "Not evaluated" and "Heuristic scoring" are trust-building messages —
   they currently read as warnings.
4. **Tighten the PDF export.** It is the artifact that leaves the building. It
   should carry the company's branding, not the app's chrome.

---

## Priority 3 — Density, rhythm and empty states

**Effort: 2–3 days across the workspace.**

1. **One table treatment.** Sessions, pipelines and analytics each style rows
   differently. Standardise row height, header treatment, hairline weight, and
   the tabular-figure column for scores.
2. **One spacing scale.** Page padding varies between `max-w-[1440px] px-6 py-8`,
   `max-w-2xl`, `max-w-5xl` and `max-w-[900px]` across screens. Pick one page
   frame and apply it everywhere.
3. **Author the empty states.** Several exist and are good ("No interview
   sessions yet"); others are bare. Every list should say what the thing is, why
   it is empty, and offer the one action that fills it.
4. **Loading states.** Skeletons exist on some screens and spinners on others.
   Prefer skeletons that match the shape of the content that will land.

---

## Priority 4 — The candidate experience

**Effort: 2 days. Touches `src/features/interview/screens/*`.**

This is the surface most people outside your company will ever see, and it is
currently the least considered. It is also, bluntly, employer-brand collateral
for your customers.

1. Apply the recruiter's branding more thoroughly — accent, logo and company name
   are honoured, but the surrounding chrome is generic.
2. Bring the six track entry screens to one standard. Welcome, system check,
   consent and face-fit each have their own layout logic.
3. Make the completion screen worth reaching. It is the last thing a candidate
   sees and currently it is a tick and two sentences.

---

## Priority 5 — Reconsider the intro splash

**Effort: 30 minutes to gate it; longer to redesign.**

`src/main.tsx` mounts `MimicIntro`, a play-once gold-on-black WebGL splash, above
**every route including the marketing site**. I hit it while capturing
screenshots — the first thing a visitor to `/mimic` sees is a cinematic
"MIMIC AI — THE FUTURE OF INTERVIEWS" title card in a completely different visual
world from the page behind it.

For a B2B marketing page benchmarked against Eightfold, this works against you on
three fronts: it delays first contentful paint for a buyer who arrived from a
search result, it introduces a fourth colour world in the first two seconds, and
no enterprise software company in this category ships one.

**Recommendation:** exclude `/mimic*` from the splash — the same way `/take/` and
`/interview` are already excluded in `MimicIntro.tsx` — and keep it for the
signed-in app if you like it there. That is a two-line change.

If you want to keep it on the marketing site, it needs re-rendering in the blue
world so it reads as an intro *to this product* rather than a separate title
sequence.

---

## What I would not change

- **The information architecture.** Seven top-level areas is right, the naming is
  clear, and Sessions is the correct home.
- **The invite wizard's five-step structure.** It is well-paced and the gating
  logic is sound.
- **The pipeline board.** Drag-to-advance with a confirm modal, quick-advance
  rules and an audit history is genuinely good product design.
- **The honest-degradation behaviour throughout.** Dry-run email, heuristic
  scoring, "not evaluated" — this is a real differentiator and most competitors
  hide it. Make it look intentional rather than removing it.

---

## Suggested sequence

| Stage | Work | Outcome |
|---|---|---|
| 1 | Brand decision + Priority 1 | The funnel becomes one product |
| 2 | Priority 5 (splash gate) | Marketing site loads straight to content |
| 3 | Priority 2 (report) | The screen buyers judge you on becomes the best one |
| 4 | Priority 3 (density) | The workspace stops feeling assembled |
| 5 | Priority 4 (candidate) | Your customers' employer brand is protected |

Stages 1 and 2 together are roughly two days and account for most of the
perceived quality gap.
