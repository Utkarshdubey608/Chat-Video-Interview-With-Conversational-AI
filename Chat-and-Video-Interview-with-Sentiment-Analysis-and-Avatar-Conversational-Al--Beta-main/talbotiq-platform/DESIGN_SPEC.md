# TalbotIQ — Design Specification (Hand-off)

A complete, implementation-ready spec of the TalbotIQ design system. Every value
below is taken from the live codebase (`tailwind.config.js`, `src/index.css`,
`src/components/ui/index.tsx`). Where a requested item does **not** exist in this
product, it's marked **— Not present** rather than invented.

> Source of truth: `tailwind.config.js` (tokens), `src/index.css` (base + component
> classes), `src/components/ui/index.tsx` (React components).

---

## 1. Overall Design Philosophy

- **Style:** Clean, calm, **enterprise / Fortune-500 SaaS**. Light, airy, content-first.
- **Principles:**
  - Restrained color — one deep-green brand color does almost all the work; color is reserved for meaning (status, scores).
  - Generous white space; cards float on a faintly green-tinted canvas.
  - Soft, low-elevation shadows; nothing harsh. Borders are pale, not black.
  - Crisp typographic hierarchy with tight negative letter-spacing on headings.
  - Micro-interactions are subtle (150ms), never flashy.
- **Brand personality:** Trustworthy, premium, composed, "executive-ready." Professional but warm (the green + rounded corners soften the enterprise feel).
- **Premium characteristics:** large radii (16px cards), tabular-nums for figures, monospace for codes/JSON, calm motion, no gradients-as-decoration.
- **Inspiration:** HireVue-style assessment tools + modern fintech dashboards (Linear/Stripe-adjacent restraint).
- **Theme:** **Single light theme. No dark mode** is implemented.

---

## 2. Color System

Defined in `tailwind.config.js → theme.extend.colors`. All HEX.

### Primary (deep green) — brand
| Token | HEX | Use |
|-------|-----|-----|
| `primary.DEFAULT` / `primary.700` | `#0d5c3a` | Brand, primary buttons, active nav, focus ring, section labels |
| `primary.50` | `#f0faf5` | Tint backgrounds (pills, active rows) |
| `primary.100` | `#dcf5e8` | Selection background |
| `primary.200` | `#b3e9cd` | Pill borders, input hover border |
| `primary.300` | `#7dd3a8` | |
| `primary.400` | `#4bb87f` | |
| `primary.500` | `#2a9e65` | |
| `primary.600` | `#1a8050` | Button hover (lighter) |
| `primary.800` | `#0a4a2e` | Button active (darker) |
| `primary.900` | `#073522` | |

### Accent (amber)
| Token | HEX |
|-------|-----|
| `accent.DEFAULT` | `#d97706` |
| `accent.light` | `#fef3c7` |
| `accent.pale` | `#fffbeb` |

The logo mark adds two secondary brand greens/yellows (from the PNG, not tokens): bright green `#28a865`, yellow `#e8a020`. These appear **only in the logo**, not the UI.

### Neutrals (slate ramp)
`50 #f8fafc` · `100 #f1f5f9` · `200 #e2e8f0` · `300 #cbd5e1` · `400 #94a3b8` · `500 #64748b` · `600 #475569` · `700 #334155` · `800 #1e293b` · `900 #0f172a`

### Semantic
| Role | Text/DEFAULT | Background (`*.bg`) | Border (`*.border`) |
|------|------|------------|-----------|
| Success | `#16a34a` | `#f0fdf4` | `#bbf7d0` |
| Warning | `#d97706` | `#fffbeb` | `#fde68a` |
| Danger | `#dc2626` | `#fef2f2` | `#fecaca` |
| Info (badge only) | `#2563eb` | `#eff6ff` | `#bfdbfe` |

### Surfaces & structure
| Role | HEX |
|------|-----|
| App background (canvas) | `#eff5f0` (green-tinted) |
| Surface / card / modal | `#ffffff` |
| Sidebar | **— Not present** (top nav only; nav bar is `#ffffff`) |
| Border (brand) | `#dde8e0` |
| Border (neutral, inputs/dividers) | `#e2e8f0` |

### Text
| Role | HEX |
|------|-----|
| Primary text / headings | `#0f172a` (neutral-900) |
| Body | `#334155`–`#475569` |
| Muted / secondary | `#64748b` (neutral-500) |
| Faint / placeholder | `#94a3b8` (neutral-400) |
| On-primary (text on green) | `#ffffff` |

### Interaction states
| State | Value |
|-------|-------|
| Hover (input border) | `#b3e9cd` |
| Hover (neutral surface) | `bg #f8fafc / #f1f5f9` |
| Active (primary button) | `#0a4a2e` |
| Focus ring | `2px solid #0d5c3a`, `outline-offset: 2px`; inputs use `box-shadow: 0 0 0 3px rgba(13,92,58,0.1)` |
| Disabled | `opacity: 0.5; cursor: not-allowed` |
| Selection | bg `#dcf5e8`, text `#0d5c3a` |
| Overlay / scrim | `rgba(15,23,42,0.40)` (neutral-900/40) + `backdrop-blur(2px)` |

### Gradients
- **None used as UI decoration.** The only gradient is functional: the range-slider/countdown track fill — `linear-gradient(to right, #0d5c3a 0% … #e2e8f0 …)`. Otherwise flat fills.
- Dashboard JSON preview uses solid `#0a0a0a`/`#0f172a` dark panels with emerald text `#34d399`-ish.

### Dark mode
**— Not implemented.**

---

## 3. Typography

- **Font family (UI):** `Inter`, weights 300–900, loaded via Google Fonts `@import` in `src/index.css`.
- **Monospace:** `JetBrains Mono` (400, 500) — codes, JSON previews, numeric IDs, timers.
- **Fallback stack:** `'Inter', system-ui, -apple-system, sans-serif`; mono: `'JetBrains Mono', 'Fira Code', monospace`.
- **Base:** `html { font-size: 16px }`; body `line-height: 1.6`, `letter-spacing: -0.01em`, antialiased.
- **Headings:** `letter-spacing: -0.025em`, `line-height: 1.2`, color `#0f172a`.

> Note: `index.html` still preloads `Syne`/`DM Sans` from an earlier iteration, but the applied font everywhere is **Inter** (set in `index.css` + Tailwind `fontFamily.sans`). Treat Inter as canonical.

### Type scale (`fontSize` tokens — size / line-height)
| Token | Size | Line height | Extra |
|-------|------|-------------|-------|
| `2xs` | 0.625rem (10px) | 1rem | uppercase micro-labels |
| `xs` | 0.75rem (12px) | 1.125rem | hints, captions, badges |
| `sm` | 0.875rem (14px) | 1.375rem | body / UI default |
| `base` | 1rem (16px) | 1.625rem | paragraph |
| `lg` | 1.125rem | 1.75rem | card titles |
| `xl` | 1.25rem | 1.875rem | |
| `2xl` | 1.5rem | 2rem | section headers |
| `3xl` | 1.875rem | 2.375rem | page titles (`PageHeader`) |
| `4xl` | 2.25rem | 2.75rem | `-0.02em` |
| `5xl` | 3rem | 1.2 | `-0.03em` hero |

### Weights in use
300, 400 (body), 500 (medium UI), 600 (semibold labels/buttons), 700 (bold headings), 800–900 (display / wordmark).

### Named text styles (from `index.css` / components)
- **`.field-label`** — 0.75rem, weight 600, `#475569`, `letter-spacing 0.025em`, **UPPERCASE**, margin-bottom 6px. (All form labels.)
- **`.section-label`** — 0.7rem, weight 700, `letter-spacing 0.1em`, UPPERCASE, **green `#0d5c3a`**. (Section dividers, stat labels.)
- **`.pill`** (kicker) — 0.6875rem, weight 600, `0.06em`, UPPERCASE, green on `#f0faf5` w/ `#b3e9cd` border.
- **PageHeader title** — `text-3xl font-bold tracking-tight` `#0f172a`.
- **Caption / hint** — `text-xs text-neutral-400`.
- **Button text** — `font-semibold`, size follows button size (xs/sm = 12px, md = 14px, lg = 16px).
- **Nav links** — `text-sm font-semibold`.
- **Numerals** — `tabular-nums` for scores/timers; `font-mono` for IDs/keys/JSON.

---

## 4. Spacing System

- **Base unit:** Tailwind default **4px** scale (`1` = 0.25rem). Custom additions: `4.5 = 1.125rem`, `13 = 3.25rem`, `15 = 3.75rem`, `18 = 4.5rem`.
- **Page container:** `max-w-[1440px]` centered, horizontal padding `px-6` (24px), vertical `py-8` (32px). Narrow pages: Settings `max-w-2xl`, Report `max-w-[1100px]`, candidate flow `max-w-2xl/3xl` centered.
- **Card padding:** `p-5` (20px) standard; `p-6`/`px-6 py-4/py-5` for sectioned cards; `p-0` when the card wraps a table/list with its own padded rows.
- **Section spacing:** vertical rhythm `space-y-6` / `space-y-8` between major sections; `mb-8` under `PageHeader`.
- **Grid gaps:** `gap-4` (16px) card grids, `gap-6` (24px) two-column layouts.
- **Field spacing:** `space-y-4` / `space-y-5` between form fields; label→input 6px.
- **Grid system:** CSS grid via Tailwind. Common: `grid sm:grid-cols-2 lg:grid-cols-3` (card galleries), `lg:grid-cols-[260px_1fr]` / `[1fr_360px]` (list+editor, form+rail), `md:grid-cols-2` (charts).
- **Responsive breakpoints (Tailwind defaults):** `sm 640` · `md 768` · `lg 1024` · `xl 1280` · `2xl 1536`.

---

## 5. Border Radius

`borderRadius` tokens: `sm 4px` · `DEFAULT 6px` · `md 8px` · `lg 10px` · `xl 12px` · `2xl 16px` · `3xl 20px`.

| Element | Radius |
|---------|--------|
| Buttons | `rounded-lg` = **10px** |
| Inputs (`.input-base`) | **10px** |
| Textarea (`.textarea-base`) | **8px** |
| Cards (`.card`) | **16px** (2xl) |
| Modals/dialogs | **16px** (`rounded-2xl`) |
| Badges / pills / chips / "Live" | **9999px** (full) |
| Dropdowns / selects | 10px (input-base) |
| Tables | wrapped in a 16px card; rows square |
| Nav pills (active tab) | 9999px |
| Avatar | full circle |
| Small icon buttons | `rounded-lg` (8–10px) |
| Empty-state icon tile | `rounded-2xl` (16px) |

---

## 6. Shadows & Elevation

`boxShadow` tokens:
| Token | Value |
|-------|-------|
| `xs` | `0 1px 2px 0 rgb(0 0 0 / .05)` |
| `sm` | `0 1px 3px 0 rgb(0 0 0 / .08), 0 1px 2px -1px rgb(0 0 0 / .05)` |
| `DEFAULT` | `0 2px 8px -1px rgb(0 0 0 / .08), 0 2px 4px -2px rgb(0 0 0 / .05)` |
| `md` | `0 4px 12px -2px rgb(0 0 0 / .08), 0 2px 6px -2px rgb(0 0 0 / .05)` |
| `lg` | `0 8px 24px -4px rgb(0 0 0 / .10), 0 4px 10px -4px rgb(0 0 0 / .06)` |
| `xl` | `0 16px 40px -8px rgb(0 0 0 / .12), 0 8px 16px -8px rgb(0 0 0 / .08)` |
| `inner` | `inset 0 2px 4px 0 rgb(0 0 0 / .06)` |
| `primary-sm` | `0 2px 8px -2px rgb(13 92 58 / .3)` |
| `primary-md` | `0 4px 16px -4px rgb(13 92 58 / .35)` |

**Elevation ladder:** card rest = `0 1px 4px rgba(0,0,0,.05), 0 1px 2px rgba(0,0,0,.03)` → card hover = `md` + `translateY(-1px)` → nav bar = `0 1px 3px rgba(0,0,0,.06)` → **modal** = `shadow-xl`. Primary buttons gain a green `primary-sm` glow on hover.
**Blur:** modal scrim `backdrop-blur(2px)`; hero grid uses a 1px radial-dot pattern (`.bg-grid`, 24px tile), not blur.

---

## 7. Component Library

No third-party UI kit — all components are hand-built in `src/components/ui/index.tsx` and styled with Tailwind + the `@layer components` classes. `cn()` = `twMerge(clsx())` for class merging.

### Button
- **Variants:** `primary` (green fill, white text), `secondary` (white, border, neutral text), `ghost` (transparent, neutral), `danger` (`#fef2f2` bg, `#dc2626` text, red border), `outline` (transparent, 2px green border, green text).
- **Sizes:** `xs h-7 px-2.5 text-xs` · `sm h-8 px-3.5 text-xs` · `md h-10 px-5 text-sm` (default) · `lg h-12 px-7 text-base`.
- **Shape:** `rounded-lg`, `font-semibold`, `gap-2`, `whitespace-nowrap`.
- **States:** hover = lighter/darker shade (`primary→600` / active `→800`); focus = `ring-2 ring-primary-700 ring-offset-2`; disabled = `opacity-50` + no pointer events; **loading** = swaps icon for a spinning ring (`border-2 border-current border-t-transparent`) and disables.
- **Icon slot:** optional leading icon; hidden while loading.

### Inputs / Textarea / Select
- **Input** (`.input-base`): 44px tall, `1.5px` `#dde8e0` border, 10px radius, 14px padding; hover border `#b3e9cd`; focus border `#0d5c3a` + `0 0 0 3px rgba(13,92,58,.1)` ring. Optional `prefix`/`suffix` adornments, `label`, `hint`, `error`. Error = red border + `⚠` message.
- **Textarea** (`.textarea-base`): min-height 96px, `1.5px #e2e8f0`, 8px radius, `resize: vertical`; optional `charLimit` counter (turns red past 90%).
- **Select:** uses `.input-base` + `appearance-none` + custom chevron SVG; `cursor-pointer`.

### Toggle (switch)
- 40×22px track, 16px white thumb with `shadow-sm`; on = `bg-primary-700`, off = `bg-neutral-200`; 200ms transition; `role="switch"`, focus ring. Optional label + description (stacked left).

### Slider
- Native range, 4px track, 16px green thumb with `0 1px 3px rgba(13,92,58,.3)`; filled portion via inline `linear-gradient`; hover thumb halo `0 0 0 6px rgba(13,92,58,.12)`. Label + live value (`font-mono text-primary-700`).

### Card
- `.card`: white, `1px #dde8e0`, **16px** radius, rest shadow (see §6). `hover` variant lifts `-1px` + `md` shadow. Compose with `p-5` or `p-0`+inner sections.

### Badge / Pill / Chip
- **Badge** (`.badge`): pill, 0.6875rem, weight 600, variants `success/warning/danger/neutral/info` (bg+text+border per §2). 
- **Pill / kicker** (`.pill`): green uppercase tag above page titles.
- **"Live" indicator:** pill with pulsing 6px dot (`.live-dot`, `#16a34a`, 2.5s pulse).

### Table
- Wrapped in a `p-0` card. `thead` row: `border-b border-border`, labels `text-xs font-semibold uppercase tracking-wide text-neutral-500`. Body rows: `border-b border-border last:border-0`, `hover:bg-neutral-50`, ~`py-3 px-5`. Numbers `tabular-nums`. No zebra striping. (See §13.)

### Modal
- Centered, `max-w-xl` default, white, **16px** radius, `shadow-xl`, `max-h-90vh` scroll. Scrim `bg-neutral-900/40 + backdrop-blur(2px)` with `animate-fade-in`; panel `animate-slide-up`. Header (title + description + ✕ close), padded body. Closes on `Esc` and scrim click; locks body scroll while open.

### Tabs (top-nav pills)
- Horizontal pill nav (see §9). Active = `bg-[#0d5c3a] text-white`; inactive = `text-neutral-500 hover:text-neutral-800 hover:bg-neutral-100`; `rounded-full px-4 py-1.5 text-sm font-semibold`.

### Accordion
- Used in the candidate report (per-question). Row = full-width button with chevron that rotates 180° on open; body reveals on a `bg-neutral-50/60` panel. (Hand-rolled with `useState`, not a library.)

### Toasts
- `react-hot-toast`, **bottom-right**, 8px gutter, 4s duration. Style: white bg, `#0f172a` text, `1px #e2e8f0` border, **10px** radius, `12px 16px` padding, 13px/weight-500, `0 4px 12px rgba(0,0,0,.08)` shadow, `max-width 380px`. Icon themes: success/loading green `#0d5c3a`, error red `#dc2626`.

### Avatar
- 36×36 (`w-9 h-9`) circle, `bg-[#0d5c3a]`, white initials, `text-xs font-bold`.

### Progress / countdown
- **CircularCountdown** (candidate): custom SVG ring, `stroke-dashoffset` drives progress; color shifts green→amber→red near the warning threshold; gentle pulse near deadline (disabled under reduced-motion).
- **Gauge** (report): custom SVG donut, 12px stroke, color by score band, big tabular-nums value centered.
- **KPI bars:** `h-2.5` rounded track `bg-neutral-100` with colored fill (`width %`).

### Skeleton
- `.animate-pulse bg-neutral-100 rounded-lg`, sized per use (e.g., `h-16 w-full`, `h-96`).

### Empty state
- Centered, `py-20`, 56px rounded-2xl `bg-neutral-100` emoji tile, bold title, muted description, optional action button.

### StatCard / KPI card
- `Card p-5 flex-col gap-2`: `.section-label` label, `text-3xl font-bold` value (color-able), optional trend line (`↑/↓` success/danger).

### JsonPreview
- Dark code panel: header bar `bg-neutral-900` with method chip + endpoint; body `bg-neutral-950` emerald monospace, `overflow-x-auto`, `max-h-80`.

### Search bar, Pagination, Drawer, Command palette, AI chat bubbles, Tooltip
- **— Not present** as dedicated components. Filtering is inline; lists aren't paginated (small datasets); there's no slide-in drawer, command palette, or chat-bubble UI. Native `title` attributes serve as tooltips. (Build these in the same language if needed: 10px radius, `#dde8e0` borders, `sm` shadow, Inter.)

---

## 8. Icons

- **Library:** `lucide-react`.
- **Style:** outline (stroke), default stroke width **2** (lucide default; some inline SVGs use 2.5).
- **Sizes:** 13–18px inline with text (commonly `size={14|15|16}`); 26–28px for empty-state/feature glyphs.
- **Color rules:** inherit `currentColor`; muted controls `text-neutral-300/400`, hover `text-neutral-700`; semantic icons take the semantic color (e.g., danger trash on hover `text-danger`). No filled icons.

---

## 9. Layout System

- **Top navigation (no sidebar):** sticky header, **height 60px**, `bg-white`, `border-b #dde8e0`, shadow `0 1px 3px rgba(0,0,0,.06)`, inner `max-w-[1440px] px-6`, three zones: **logo** (left, `img h-10`), **center pill nav** (`flex-1 justify-center`), **right** ("Live" pill if active, "Add API Key" pill if unset, avatar).
- **Content width:** `max-w-[1440px]` default; report `1100px`; settings `2xl`; candidate flow centered narrow.
- **Dashboard grid:** responsive card grids `sm:2 / lg:3`; analytic pages mix `recharts` blocks in `md:grid-cols-2`.
- **List + editor pattern:** `lg:grid-cols-[260px_1fr]` (Question Sets). **Form + summary rail:** `lg:grid-cols-[1fr_360px]` (Template editor).
- **Candidate flow:** chrome-minimal — **no nav**; a centered branded shell, single column, mobile-friendly.
- **Responsive behavior:** multi-col grids collapse to single column below `lg`/`md`; nav is horizontal (wraps/scrolls on small widths — primarily a desktop recruiter tool). Mobile is fully supported for the **candidate** flow.

---

## 10. Motion & Animation

- **Library:** `framer-motion` (candidate flow transitions) + Tailwind/CSS keyframes.
- **Durations:** micro-interactions **150ms**; cards/toggles **200ms**; entrances **250–300ms**.
- **Easing:** `ease` / `ease-in-out` (default CSS). Slider/hover use linear-ish 150ms.
- **Named animations (Tailwind):** `fade-in` (0.25s), `slide-up` (0.3s, `translateY(12px)→0`), `pulse-soft` (3s), `spin-slow` (2s).
- **Modal:** scrim `fade-in`, panel `slide-up`.
- **Question transitions (candidate):** framer-motion fade/slide between questions, keyed by question id; **respects `prefers-reduced-motion`** (via `useReducedMotion()` — disables ring pulse and entrance offsets).
- **Loading:** button spinner (rotating ring), `Loader2` spin, skeleton pulse.
- **Hover:** card lift `-1px`; nav/ghost background fill; button shade shift; slider thumb halo.
- **Chart animation:** recharts default enter animations.
- **Drawer animations:** **— Not present.**

---

## 11. Charts & Data Visualization

- **Library:** `recharts`.
- **Palette:** brand green `#0d5c3a` as primary series; score-banded colors for KPIs — **≥75 green `#16a34a`, ≥55 amber `#d97706`, else red `#dc2626`** (see `scoreColor()` in `ReportPage.tsx`).
- **Radar (KPI profile):** `PolarGrid stroke #e2e8f0`, angle ticks `fontSize 10, fill #64748b`, radius axis hidden, `Radar stroke #0d5c3a fill #0d5c3a fillOpacity 0.25`, domain `[0,100]`.
- **Gauge (overall score):** custom SVG donut (not recharts), 12px stroke, color by band, value in tabular-nums.
- **KPI bars:** custom `div` bars (sorted desc), `h-2.5` rounded, color-banded fill, value at right.
- **Grid/axis styling:** pale `#e2e8f0` grid, muted slate ticks, no heavy axis lines.
- **Tooltip/legend:** recharts defaults, kept minimal; KPI lists prefer inline labels over legends.
- **KPI presentation:** `StatCard` (label / big value / trend) for metrics; gauge + radar + bar list for the candidate report.

---

## 12. Forms

- **Labels:** `.field-label` — uppercase, 12px, weight 600, `#475569`, 6px below.
- **Helper text:** `text-xs text-neutral-400` under field.
- **Required indicator:** none standardized — requiredness is conveyed in hints/validation (no asterisk convention).
- **Validation / error:** red border (`#dc2626`) + `0 0 0 2px rgba(...)`-style ring; message line `text-xs text-danger` prefixed `⚠`.
- **Success:** inline status text (e.g., Settings "✓ Connected" in `text-success`) + success toast.
- **Focus ring:** inputs `border #0d5c3a` + `0 0 0 3px rgba(13,92,58,.1)`; global `:focus-visible` `2px solid #0d5c3a` offset 2px.
- **Input spacing:** fields stacked `space-y-4/5`; two-up grids `grid-cols-2 gap-4`.
- **Disabled:** `opacity-50`, not-allowed cursor.

---

## 13. Tables

- **Header:** `border-b border-border`, `text-xs font-semibold uppercase tracking-wide text-neutral-500`, left-aligned (actions right).
- **Row height:** ~`py-3` (≈44–52px), `text-sm`.
- **Hover:** `hover:bg-neutral-50`. No zebra striping.
- **Dividers:** `border-b border-border last:border-0`.
- **Cells:** primary value `font-medium text-neutral-800` with a muted sub-line; numbers `tabular-nums`; status via `Badge`.
- **Sorting indicators / filters / pagination / row selection:** **— Not implemented** (datasets are small; lists are simple). Add chevron sort glyphs + a filter row in the same styling if needed.
- **Empty state:** table replaced by the `EmptyState` component inside the card.

---

## 14. AI Elements

- The product is AI-powered (Gemini generates questions and scores answers **server-side**), but there is **no chat/assistant UI**. So:
  - **AI assistant / prompt box / message bubbles / streaming animation:** **— Not present.**
  - **AI badges:** adaptive/AI features are marked with the **info `Badge`** (e.g., `adaptive`) and the `Sparkles` lucide icon on "Generate from résumé" actions.
  - **Thinking/loading:** standard `Loader2` spinner + "Generating…/Scoring in progress…" copy; the report polls until the AI result is ready.
  - **Degraded/fallback state:** amber warning banner (`warning` tokens) when no AI key is configured.

---

## 15. Design Tokens (copy-paste)

### Tailwind config (`tailwind.config.js → theme.extend`)
```js
colors: {
  primary: { DEFAULT:'#0d5c3a',50:'#f0faf5',100:'#dcf5e8',200:'#b3e9cd',300:'#7dd3a8',400:'#4bb87f',500:'#2a9e65',600:'#1a8050',700:'#0d5c3a',800:'#0a4a2e',900:'#073522' },
  accent:  { DEFAULT:'#d97706', light:'#fef3c7', pale:'#fffbeb' },
  neutral: { 50:'#f8fafc',100:'#f1f5f9',200:'#e2e8f0',300:'#cbd5e1',400:'#94a3b8',500:'#64748b',600:'#475569',700:'#334155',800:'#1e293b',900:'#0f172a' },
  surface:'#ffffff', background:'#eff5f0', border:'#dde8e0',
  success:{ DEFAULT:'#16a34a', bg:'#f0fdf4', border:'#bbf7d0' },
  warning:{ DEFAULT:'#d97706', bg:'#fffbeb', border:'#fde68a' },
  danger: { DEFAULT:'#dc2626', bg:'#fef2f2', border:'#fecaca' },
},
fontFamily: { sans:['Inter','system-ui','sans-serif'], display:['Inter','system-ui','sans-serif'], mono:['JetBrains Mono','Fira Code','monospace'] },
borderRadius: { sm:'4px', DEFAULT:'6px', md:'8px', lg:'10px', xl:'12px', '2xl':'16px', '3xl':'20px' },
// fontSize, spacing (4.5/13/15/18), boxShadow, animation → see §3/§4/§6/§10
ringColor: { primary:'#0d5c3a' },
```

### CSS variables (equivalent, if not using Tailwind)
```css
:root{
  --brand:#0d5c3a; --brand-50:#f0faf5; --brand-100:#dcf5e8; --brand-200:#b3e9cd;
  --accent:#d97706;
  --bg:#eff5f0; --surface:#fff; --border:#dde8e0; --border-neutral:#e2e8f0;
  --text:#0f172a; --text-muted:#64748b; --text-faint:#94a3b8;
  --success:#16a34a; --warning:#d97706; --danger:#dc2626; --info:#2563eb;
  --radius-btn:10px; --radius-card:16px; --radius-input:10px; --radius-pill:9999px;
  --shadow-card:0 1px 4px rgba(0,0,0,.05),0 1px 2px rgba(0,0,0,.03);
  --shadow-modal:0 16px 40px -8px rgb(0 0 0/.12),0 8px 16px -8px rgb(0 0 0/.08);
  --focus-ring:0 0 0 3px rgba(13,92,58,.1);
  --font-sans:'Inter',system-ui,sans-serif; --font-mono:'JetBrains Mono',monospace;
}
```
The reusable component classes (`.input-base`, `.textarea-base`, `.card`, `.field-label`, `.section-label`, `.pill`, `.badge*`, `.live-dot`, `.divider`) are in `src/index.css` — copy that `@layer components` block verbatim for an exact match.

---

## 16. Frontend Stack

| Concern | Choice |
|--------|--------|
| Framework | **React 18 + TypeScript**, **Vite 5** (client-only SPA) |
| Backend (for the AI features) | **Express 4 + TypeScript** (run via `tsx`); Gemini called server-side only |
| CSS framework | **Tailwind CSS 3.4** (+ PostCSS, Autoprefixer) |
| Component library | **None** — bespoke kit in `src/components/ui/index.tsx` |
| Icons | **lucide-react** |
| Animation | **framer-motion** (+ Tailwind keyframes) |
| Charts | **recharts** |
| State / data | **Zustand** (+ `persist`) for client state; **@tanstack/react-query** for server data |
| Routing | **react-router-dom v6** |
| Toasts | **react-hot-toast** |
| Drag & drop | **@dnd-kit** (core + sortable) — question reordering |
| PDF export | **jspdf** + **html2canvas** |
| Utilities | `clsx` + `tailwind-merge` (`cn()`), `date-fns` |
| Fonts | **Inter** + **JetBrains Mono** via Google Fonts `@import` in `index.css` |
| AI | **@google/genai** (Gemini, `gemini-2.5-flash` default), **server-side only** |

---

## 17. UI Patterns

- **Card composition:** white card, 16px radius, pale `#dde8e0` border, soft rest shadow; either uniform `p-5`, or `p-0` with a bordered header (`px-6 py-4`) + padded body (`px-6 py-5`) for "settings-style" sections.
- **Page composition:** `PageHeader` (green `.pill` kicker → `text-3xl` bold title → muted description, with an optional right-aligned action button) → `mb-8` → content. Wrapped in `max-w-[1440px] px-6 py-8`.
- **Section hierarchy:** `SectionTitle` = green uppercase `.section-label` + a hairline rule filling remaining width; sections separated by `space-y-8`.
- **Information density:** medium-low. Generous padding, one idea per card, lots of breathing room — "executive-ready," never cramped.
- **Visual rhythm:** consistent 4px-based spacing; repeating card → header → body → footer-actions structure; the deep green recurs as the single accent that ties screens together.
- **Alignment:** left-aligned labels/content; actions right-aligned in headers, footers, and table rows; numbers right-aligned + tabular.
- **White-space:** the green-tinted canvas (`#eff5f0`) shows generously between/around white cards; modals get `p-6` interiors.
- **Component consistency:** every input/button/badge/card comes from the shared kit + `@layer components` classes, so radius, borders, focus rings, and shadows are identical everywhere. Status is always a `Badge`; primary action is always the green `Button`; destructive actions are a muted trash icon that turns red on hover.

---

### Quick "feel" summary for the teammate
> Light **enterprise** SaaS. Canvas `#eff5f0`, white 16px-radius cards with feather-soft shadows, **one** deep-green brand color `#0d5c3a` for all primary/active/focus, **Inter** everywhere with tight heading tracking, **lucide** outline icons at stroke-2, **150ms** calm motion, pale `#dde8e0` borders, pill badges, uppercase micro-labels. No dark mode, no sidebar (top pill-nav), no gradients. Recharts in brand green with score-banded green/amber/red.
