# Design

<!-- impeccable:design-schema 1 -->

Recorded from the **built application**, not from a plan: the marketing site at
`/mimic`, and the recruiter workspace, candidate and interview surfaces verified
in a signed-in browser on 2026-08-12.

**One system now covers every surface.** Before this pass the product ran four
competing identities — violet marketing, a green-tinted workspace, a dark-green
candidate default, and a gold-on-black avatar room. They are now one.

Source of truth for values: `talbotiq-platform/tailwind.config.js`,
`talbotiq-platform/src/index.css`, `src/components/ui/index.tsx`, and
`src/features/marketing/mimicSite.css`. The older
`talbotiq-platform/DESIGN_SPEC.md` describes the retired green system and is
marked superseded — do not build from it.

## Visual world

Inherited from the parent brand, **Eightfold AI**, as it actually ships: a
violet→magenta spectrum on a pale lavender ground, with a mint-green primary
action and fully-rounded pill controls.

> **Correction on record.** An earlier pass rebased this on blue. That came from
> a text description of the parent site rather than its stylesheet, and was
> wrong. The violet ramp below matches the brand as rendered.

The marketing page refuses the category default it replaced — a hero band of
borrowed customer statistics — because none of ours are verified. In its place it
shows the scoring mechanism working on a real answer.

---

# Part 1 — Product (recruiter workspace, candidate, interview)

Tailwind tokens. These are what every application screen consumes.

## Colour

| Token | Value | Role |
|---|---|---|
| `primary` / `primary-700` | `#6B2BE0` | Brand, primary buttons, active nav pill, focus ring, section labels |
| `primary-800` | `#4A1BA8` | Active/pressed, pill ink |
| `primary-100` / `primary-50` | `#F0E9FD` / `#F8F5FE` | Pill and chip grounds, row hover |
| `magenta` | `#C42C93` | Warm terminus of the brand gradient |
| `mint` / `mint-hover` | `#8FE3D0` / `#79D9C3` | **Hero action fill** (ink on top), e.g. "Invite candidates" |
| `mint-ink` | `#0F7A66` | Mint used as text |
| `background` | `#F7F5FB` | App ground — lavender-neutral, never green |
| `surface` | `#FFFFFF` | Cards |
| `border` | `#E7E2F2` | Hairlines |
| `neutral-900` | `#1B0B3B` | Headings and body ink — the brand's near-black violet |
| `neutral-700` / `600` | `#4A4460` / `#524A69` | Strong body, field labels |
| `neutral-500` / `400` | `#645C7B` / `#746C8B` | Secondary, muted, placeholders |
| `neutral-300` and below | `#D2CBE4` → `#FAF9FD` | **Decorative only** — borders, tracks, skeletons |
| `success` | `#0F7A5F` on `#E4F6F0` | |
| `warning` | `#B45309` on `#FDF3E2` | |
| `danger` | `#DC2626` on `#FEF2F2` | |

The neutral ramp is violet-tinted, so even "gray" text carries the brand
undertone. `neutral-400`/`500` were darkened from the first draft specifically to
clear contrast as text — see [Accessibility](#accessibility).

**Dark surfaces** (avatar room, live call, the guide panel) use the `brand.*`
keys. The names are legacy — `brand.gold` is now the violet accent `#B98CFF` —
which let every consumer re-skin without touching a component.

`brand.black #0E0620` · `brand.card #1D1038` · `brand.border #332154` ·
`brand.gold #B98CFF` · `brand.gray #9D93B8` · `brand.green-light #8FE3D0`

### Gradients

Two, used as fields and accents — **never on text**.

- `bg-brand-field` — `132deg, #6D3BE8 → #8B34D6 44% → #C42C93`. Logo mark, avatar chips, report hero strip.
- `bg-brand-band` — `90deg, #5B6FE8 → #8B3FD9 50% → #D93BA8`. Hairline accent strips (login card, report header).

`.bg-brand-wash` gives the full-screen auth surfaces two large, soft, non-tiling
radial washes. It replaced a 24px-tiled dot grid, which reads as graph paper and
is a generic generated-UI tell.

## Type

**Figtree** carries the entire product, weights 400–900. **Roboto Mono** is the
only other face, reserved for machine values (API keys, model IDs, tokens) —
never as decoration.

Syne and DM Sans were removed: loaded on every page, referenced nowhere.

Scale is defined in `tailwind.config.js` with paired line-heights; `4xl`/`5xl`
carry negative tracking. Headings default to `-0.028em`.

## Shape and elevation

| Radius | Value | Applies to |
|---|---|---|
| Pill | `9999px` | **Every interactive control** — buttons, nav items, chips, badges |
| `2xl` | `16px` | Cards, panels |
| `xl` | `12px` | Inputs, textareas, list rows |

Inputs are the deliberate exception to the pill rule — a pill text field reads as
a search box.

Shadows are ink-toned (`rgb(27 11 59 / …)`), always offset plus soft blur, never
a zero-offset halo. Two coloured lifts exist for the buttons that use them:
`primary-sm/md` and `mint-sm`.

## Buttons

`variant`: `primary` (violet) · `mint` (hero action) · `secondary` (white) ·
`outline` · `ghost` · `danger`. All fully rounded, all with a `-1px` hover lift.

## Screen grammar

Every workspace screen is built from the same parts, in the same order:

1. **`PageHeader`** — uppercase violet `kicker` pill, `title`, one-line
   `description`, and an `action` cluster on the right (secondary then hero).
2. **Filter bar**, where the screen has filters — its own white card with
   uppercase micro-labels and a right-aligned result count.
3. **Content** — a card-wrapped table (executive console) or a card grid.

Tables: 11px uppercase `neutral-500` headers, `h-12`-class rows, hairline
dividers, `primary-50/40` row hover, right-aligned `tabular-nums` numerics, and
a trailing actions column.

## State doctrine

**Binding.** Every data view must distinguish three states, and an error must
never be rendered as an empty state. This was violated in two places and both
were fixed:

- `SessionsPage` had no error branch, so a failed `/api/sessions` told the
  recruiter they had no sessions. It now says the server was unreachable,
  reassures that nothing was lost, and offers **Try again**.
- `ReplicasPage` showed "No replicas yet" when the real blocker was a missing
  Tavus key (`listReplicas` tolerates partial failure and resolves to `[]`, so
  the query never errors). Without a key it now says **Connect your Tavus API
  key** and routes to Settings.

- **Loading** — skeletons shaped like the content they replace, never a bare spinner.
- **Empty** — lucide icon in a tinted plate, a title, a sentence explaining what
  will appear here, and the action that creates the first one.
- **Error** — what failed, what it means for their data, and a recovery action.

Where a section is hidden for a reason, say the reason. Analytics does this well:
"Position-level insights are hidden — select a Role or Template above."

## Icons

**lucide-react**, `strokeWidth` 1.75 for display and 2–2.25 inline. No emoji as
icons, no unicode glyphs (`✓`, `!`) standing in for symbols. The marketing site
uses its own authored 24×24 family in `icons.tsx`.

## Responsive

Breakpoint that matters is `md` (768px).

The top nav collapses below `md` into a disclosure menu holding all seven
destinations plus identity, sign-out and the API-key CTA. Before this, the seven
tabs simply overflowed: Pipelines, Analytics, Avatar studio, Settings and sign
out were **unreachable on a phone**, and the overflowing row also forced the whole
page to scroll sideways. Both are fixed — verified `scrollWidth 384 ≤ 390`.

Wide tables scroll inside their own container; the page body never scrolls
horizontally.

## Motion

Hover and state transitions 150ms. Entrances 250–350ms. The typing indicator is
opacity-only (`typing-dot`, 1.4s) — bounce and elastic easing read as dated.

`prefers-reduced-motion: reduce` collapses every animation and transition
globally in `index.css`.

## Accessibility

Audited with a WCAG 2.1 contrast script over the token system: **37 pass, 0
fail**. Three failures found in my own first-draft tokens were fixed at source
rather than patched per-screen:

| Token | Was | Now | Ratio on white |
|---|---|---|---|
| `neutral-400` | `#94A3B8` (2.88:1) | `#746C8B` | 4.6:1 |
| `neutral-500` | `#64748B` (4.01:1) | `#645C7B` | 5.9:1 |
| Input border | `#DDE8E0` (1.49:1) | `#948BAB` | 3.0:1 |

Also: `:focus-visible` is a 2px violet outline at 2px offset, globally; icon-only
controls carry `aria-label`; the mobile menu sets `aria-expanded` /
`aria-controls` and closes on Escape and on navigation.

---

# Part 2 — Marketing site (`/mimic`)

CSS custom properties in `mimicSite.css`. Same brand, separate token layer
because the page is a standalone document.

## Colour

| Token | Value | Role |
|---|---|---|
| `--mm-violet` | `#6B2BE0` | Primary brand, links, form submit |
| `--mm-violet-h` / `-d` / `-dd` | `#5A21C4` / `#4A1BA8` / `#2A1259` | Hover, eyebrow ink, footer field |
| `--mm-magenta` / `-l` | `#C42C93` / `#D93BA8` | Secondary hairline, gradient terminus |
| `--mm-indigo` | `#5B6FE8` | Cool end of the banner gradient |
| `--mm-mint` / `-h` / `-d` | `#8FE3D0` / `#79D9C3` / `#0F7A66` | **Primary action fill**, hover, mint-as-ink |
| `--mm-bg` / `--mm-bg-alt` | `#FFFFFF` / `#FAF7FE` | Ground, alternating band — lavender, never gray |
| `--mm-ink` / `-2` / `--mm-muted` | `#1B0B3B` / `#4A4460` / `#645C7E` | Headings, body, labels |
| `--mm-line` / `-2` | `#EAE3F5` / `#D9CFEC` | Hairlines, input borders |
| `--mm-tint` / `-2` / `-line` | `#F3EDFD` / `#E4D8FB` / `#CDB8F5` | Washes, icon plates, evidence highlight |

Three gradients and no others: `--mm-grad-band` (announcement bar only),
`--mm-grad-field` (full-bleed sections, logo mark, rubric bars),
`--mm-grad-hero` (two soft radial washes over white).

Status colours are used for status only: `--mm-green #0F7A5F`,
`--mm-amber #8F5A00`, `--mm-red #C1332B`.

## Type

**Figtree** carries the whole site, 400–900. No monospace anywhere.

- `h1` — `clamp(40px, 5.3vw, 72px)`, weight 800, tracking `-0.045em`
- `.h2` — `clamp(31px, 3.7vw, 50px)`, tracking `-0.038em`
- `.lede` — 18.5px / 1.62, capped 66ch · Body 16px / 1.6, article measure 74ch

## Eyebrow pills

The parent brand sets a pill label above its headings, so this site does too
(`.eyebrow`): 11.5px, weight 700, `.13em` tracking, uppercase, violet-deep on
`--mm-tint`, fully rounded, 20px below. `.eyebrow.on-dark` inverts on gradient
fields.

## Shape, elevation, buttons

`--mm-r-ctl 999px` on everything interactive — the strongest inheritance signal.
`--mm-r-card 16px`, `--mm-r-lg 22px` for product frames. Inputs at `14px`.

| Class | Fill | Ink | Border | Use |
|---|---|---|---|---|
| `.btn-primary` | Mint | Ink | — | The main action, everywhere |
| `.btn-ghost` | White | Ink | Magenta | Secondary beside primary |
| `.btn-light` | White | Violet-deep | — | On a gradient field |
| `.btn-outline-l` | Transparent | White | White 60% | On a gradient field |
| `.btn-violet` | Violet | White | — | Where mint would fight the surround |

Every button animates its arrow icon 3px right on hover.

## Spacing and components

Sections `108px` desktop, `66px` below 760px. Container `1260px`, gutters
`40 → 28 → 20px`. Bands alternate white → tinted → white, with two full-bleed
gradient fields as anchors.

- **Product frame** (`.frame`) — the hero's Sessions view; every instance carries a `.ph` "Sample data" chip.
- **Rubric card** (`.mech-card`) — question, answer with `<mark>` evidence spans, six criteria bars, weighted total, recommendation chip.
- **Format cards** (`.track`) — six-column grid so five cards fill two rows without a hole: three at `span 2`, two at `span 3`, statement card at `span 6`.
- **Process** — numbered pill tabs left, glass panel right; the active step's number goes mint.

## Motion

One authored entrance: `.reveal` — 16px rise plus fade on
`cubic-bezier(.16,1,.3,1)` over 700ms, IntersectionObserver-fired, staggered.
Hover 140–180ms. Nothing else animates in 2D.

## Scroll craft

Four primitives in `motion.tsx`, all additive over a design that already
worked, none of them changing layout — if the JS never runs, the page is exactly
the page. Every one is a no-op under `prefers-reduced-motion`, in both the JS
guard and the CSS.

| Primitive | What it does |
|---|---|
| `useSmoothScroll` | Lenis, dynamically imported (5.7 KB). In-page anchors handled explicitly — a smooth-scroll library that silently breaks `#demo` is a regression dressed as polish. |
| `ScrollProgress` | 2px brand-gradient reading rail. Driven by `scaleX`, never `width`, because animating width forces layout every frame. |
| `Parallax` | Vertical travel on scroll, IntersectionObserver-gated so off-screen elements cost nothing. Applied to the hero product frame at 22px. |
| `Magnetic` | Control leans toward the cursor. Gated on `hover: hover and pointer: fine` so it never fires on touch, capped at ~6px so it reads as responsiveness rather than a toy. |

**Bug worth remembering:** the progress rail first shipped at `z-index: 60`
while the sticky nav is `z-index: 100`, both at `top: 0` — the nav painted over
it and the feature was completely invisible. Anything `position: fixed` at the
top of this site must clear 100.

## The WebGL hero — built, not shipped

`three/HeroScene.tsx` — a drifting field of interview cards that scroll pushes
through. Instanced, so the whole field is one draw call. The layout is
**deterministic** (golden-ratio stride, no `Math.random`), because a hero that
reshuffles between loads reads as accidental rather than authored. ACES tone
mapping, bloom, vignette, and a whisper of chromatic aberration. Card colour
lerps violet→magenta with depth, with mint cards seeded through as the scored
ones. The camera dollies and tilts on scroll — no rolls, no swoops; the
restraint is the point.

`three/HeroCanvas.tsx` is the gate. The scene chunk loads **only** when all of
these hold:

- the browser can actually create a WebGL context
- the device is not low-tier or a software renderer (`detectTier`)
- `prefers-reduced-motion` is not set
- the hero is on screen (IntersectionObserver, 200px margin)

Scroll progress is written to a **ref**, never React state — a re-render per
scroll frame is exactly the jank this is meant to avoid. DPR capped at 1.5.

**Verified in the built output:** the critical path is `index` + `vendor-react` +
`vendor-query` + CSS. `three.module` appears only inside the dynamic import's
preload manifest, so a visitor who cannot use the scene never pays a byte for
it. The CSS hero underneath is a finished design, not a degraded placeholder.

The canvas is masked with a radial gradient so it dissolves into the page rather
than ending on a hard edge, sits behind the copy at `z-index: 0`, and never
intercepts pointer events.

## Content rules

Binding, and the reason the page is shaped as it is:

1. **No unverified figure appears anywhere** — no statistic, customer name,
   testimonial or certification badge ships without being real and cleared. See
   PRODUCT.md → Evidence on Hand.
2. **Synthetic demonstration data is labelled** with the `.ph` chip.
3. **Proof is a demonstration, not an assertion.** Where the category shows a
   metric, this site shows the mechanism operating.
4. Three real client logos, static row, honest scale. No marquee — sliding three
   logos implies a roster we do not have.

---

## Known gaps

- **The four candidate interview experiences have not been visually verified.**
  `/take/:sessionId` sits behind `RequireCandidate`, which redirects recruiters
  to `/sessions` ([guards.tsx:136](talbotiq-platform/src/features/auth/guards.tsx#L136)).
  Their code was restyled onto these tokens and typechecks, builds and passes
  tests — but no one has looked at them rendered. Verifying them requires a
  candidate sign-in.
- **`npm run lint` is non-functional** — ESLint 8 finds no config file. Pre-existing.
- **Main bundle is 3.59 MB** (1.01 MB gzipped) with no code splitting. Pre-existing.
- The Tavus replica list is fetched from the browser, so the key is client-side.
  Pre-existing architecture, untouched here, but worth a decision.
