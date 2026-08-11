# Talbotiq Recruiter Desktop — UI/UX Redesign

Date: 2026-08-12
Scope: visual redesign only — no business logic, API, backend, auth, data
model, or scoring changes. Builds on the recruiter-only desktop work in
[RECRUITER_DESKTOP_REPORT.md](RECRUITER_DESKTOP_REPORT.md) and
[FINAL_HARDENING_REPORT.md](FINAL_HARDENING_REPORT.md).

## Architecture decision

Rather than editing pages in place, this added a small set of reusable
desktop-only widgets and had each existing page opt into them via an
`isDesktopPlatform` branch — the same pattern already used to gate desktop
behavior throughout this migration. `AdaptiveNavScaffold` (the sidebar rail
used by `CandidateShell` and by `RecruiterShell` on mobile/web) was **not**
modified — a new, separate `DesktopTopNav` widget was added instead, so
candidate/mobile/web navigation is provably untouched.

New shared widgets (`lib/shared/widgets/`, `lib/core/theme/desktop_tokens.dart`):

| Widget | Purpose |
|---|---|
| `DesktopTopNav` + `DesktopTopNavItem` | The horizontal top nav — logo/wordmark, tabs with hover + active-underline states, a trailing slot |
| `DesktopPageContainer` | Max-width (1600px, so cards don't stretch into ribbons on ultrawide monitors) + responsive horizontal padding (32px, 20px below ~1360px width) |
| `DesktopCard` | The premium-SaaS card surface: 14px radius (vs. the app's existing global 24-28px `CardTheme`, which is untouched — this is scoped to new desktop widgets only), subtle border, optional title/trailing |
| `MetricCard` | Compact KPI tile — icon, label, value, optional real footnote. **Deliberately has no trend/delta field** — see "Data integrity" below |
| `ResponsiveGrid` | Promoted out of `analytics_page.dart`'s private `_ResponsiveGrid` so every new grid (KPIs, Library tiles) shares one implementation |
| `SectionHeader` | Title/subtitle/trailing-action header, used at both page level and section level |
| `StatusBadge` | Completed/In Progress/Assigned/Published pill, colors matching the app's existing semantic palette (green/amber/muted — no new colors) |
| `TalbotiqWordmark` | The app's actual in-UI branding (a styled "talbotiq" text mark) promoted from a private duplicate in `recruiter_home.dart`/`login_page.dart` — no logo image exists anywhere in this app's UI, so none was invented |

`LogoutButton.signOut()` was extracted as a static method so the new desktop
profile menu reuses the exact existing sign-out logic instead of duplicating
it.

## 1. Top navigation

`RecruiterShell` now branches: mobile/web renders exactly as before
(`AdaptiveNavScaffold`, bottom bar or sidebar rail depending on width — zero
change); desktop renders `DesktopTopNav` (Home / Library / Analytics /
Settings, active tab shown with a green underline + bold label, hover state
on inactive tabs) with a profile menu on the right showing the **real**
authenticated user's display name (falling back to email) and "Recruiter",
with a dropdown for Settings and Sign out (reusing `LogoutButton.signOut`).
No global search was added — there is no existing app-wide search feature
(only page-local ones: "Search tests by name" on Home, "Search this test by
name or email" on a test's candidate list), and the brief is explicit not to
fabricate one.

Because there's now one persistent top bar, each page's *own* local
`AppBar` — which would otherwise stack a second toolbar directly under the
first — is skipped on desktop only:

- `RecruiterHome`: desktop shows a `SectionHeader` ("Interviews" + subtitle)
  with "Library" and "Create interview" as header actions, replacing the
  AppBar+FAB. The search bar and test list (`_searchBar()`, `_body()`) are
  the exact same methods, called unchanged.
- `RecruiterLibraryPage`: desktop shows a `SectionHeader` ("Library") over a
  `ResponsiveGrid` of the same six destinations (Templates, Question sets,
  Generate from résumé, AI model, Personas, Replicas) as compact cards
  instead of tall full-width rows — same navigation targets, same pages.
- The Settings tab wrapper (`_RecruiterSettingsTab`) renders `SettingsPage`
  directly on desktop, with no wrapping `Scaffold`/`AppBar`/`LogoutButton` —
  `SettingsPage` itself already has its own title treatment and (at wide
  widths) a two-column category/content layout, which needed no rework.

Mobile/web: every one of the above still returns its original
`Scaffold`+`AppBar` unchanged — confirmed by reading the diff, not assumed.

## 2. Analytics — the full redesign

`AnalyticsPage`'s `StreamBuilder`/filter state (`_track`, `_testId`,
`_roleController`, `_dateFrom`, `_dateTo`, `_openFilterSheet`) is completely
unchanged — the desktop branch computes `summary`/`filtered`/`testOptions`
through the exact same `AnalyticsService.applyFilter`/`compute` calls the
mobile dashboard already used, then renders a new `_DesktopDashboard` instead
of the existing `_Dashboard`. The mobile `_Dashboard` and every chart class it
uses are still in the file, byte-for-byte unchanged, and still rendered for
mobile/web.

- **Header**: "Analytics Overview" + subtitle, with a date-range chip
  (shows "All time" or the active range) and a Filter button — both open the
  *existing* filter sheet; no new filtering logic was written.
- **KPI row**: `MetricCard`s for Total Interviews, Completion Rate (with a
  real footnote — "X of Y completed" — not a fabricated delta), Average
  Score, Evaluated Candidates, Published.
- **Interview Funnel**: a dedicated card with a labeled horizontal bar per
  stage (Total/Assigned/In Progress/Completed/Published), each showing its
  real count and its real percentage of the total.
- **Performance Trend**: the existing `_TrendChart` widget, reused as-is
  (same real day-by-day average-score data — this app has no historical
  data beyond that, and none was invented), just restyled inside the new
  `DesktopCard`.
- **Score Distribution**: replaced the old full-width bar chart with a
  donut + legend, real bucket counts/percentages, and the average score
  shown prominently above it in large type ("22.7 / 100" scale). Bucket
  colors are a low-to-high *intensity* scale (muted → brand green) rather
  than a red-to-green "bad/good" scale — a low-score bucket isn't an error
  state, so it doesn't get an error color.
- **"Top Skills Performance"**: this app has no per-skill/KPI dataset
  anywhere (checked `AnalyticsSummary` directly) — per the brief's own
  fallback instruction, this slot uses the KPI data that *does* exist:
  per-track (video/chat/voice) average score and completion rate, relabeled
  "Performance by Track."
- **Recent Interviews**: a new table (Candidate / Role / Date / Status)
  built from the same filtered `Interview` list already in memory, sorted by
  `createdAt` descending. Each row navigates to `EvaluateInterviewPage`
  directly (it already holds the full `Interview` object, so unlike the
  existing "Top Candidates" list this doesn't even need a repository
  round-trip). `StatusBadge.forInterview` derives the pill from the same
  `status`/`resultPublished` fields the funnel already uses — no new status
  concept.

## Data integrity — what was deliberately not added

- **No fabricated trend/delta values.** `MetricCard` has no percentage-change
  field at all; nothing in this app computes a period-over-period
  comparison, so none is shown.
- **No fabricated historical trend.** The trend chart is the same real
  per-day data as before.
- **No fabricated skills data.** "Performance by Track" uses real `byType`
  data instead of inventing a skills taxonomy the app doesn't have.
- **No hardcoded names/data anywhere.** The profile menu reads
  `FirebaseAuth.instance.currentUser` live; every number on the redesigned
  Analytics page flows through the same `AnalyticsService`/`Interview` data
  the mobile dashboard already used.

## Responsiveness & window behavior

`DesktopPageContainer` caps content at 1600px and scales horizontal padding
down below ~1360px width. `window_manager`'s configuration (`main.dart`) was
not touched. Both were verified live, not assumed:

- Forced the running window to exactly **1280×720** — full top nav, header
  actions, profile menu, and content all rendered correctly, no clipping.
- Forced a resize down to 500×400 — clamped to exactly **1024×700**, the
  configured minimum, unchanged by this work.
- Resized up to this machine's actual maximum available screen size
  (~1554×978 — the real display here is smaller than 1920×1080/2560×1440, so
  those exact resolutions could not be physically tested; the max-width
  cap's logic was verified by code review instead, and is a simple
  `ConstrainedBox`, low risk).

## Verification

```
flutter analyze:   0 errors, 0 warnings, 162 pre-existing info-level notices
                   (unchanged from before this redesign — all predate it)
flutter test:      202/202 passed
flutter build windows --dart-define=BACKEND_BASE_URL=http://localhost:8000:
                   succeeded
Windows launch:    succeeded — process responsive, title "Talbotiq", no
                   crash, no error dialog
```

**Visually inspected live**, with screenshots, not assumed:
- Top nav rendering correctly (wordmark, 4 tabs, active-tab underline, real
  profile menu with real account name/role) — at 1280×720 and at this
  machine's max resolution.
- Analytics: KPI cards, Interview Funnel (with real percentages), and
  Performance Trend chart all rendering correctly with real production data
  (Total 9, Completion Rate 67%, Average Score 22.7, real trend points).
- Home: new header + "Library"/"Create interview" actions + the existing
  search bar and test list, all rendering correctly.
- Settings: renders cleanly under the top nav with no duplicate toolbar,
  two-column category layout intact.

**Not re-confirmed visually in this pass** (code-reviewed and
`flutter analyze`-clean, but I did not get a fresh screenshot of them):
Score Distribution donut, Performance by Track bars, and the Recent
Interviews table. GUI click-automation in this environment is intermittently
unreliable (documented at length in the earlier live-QA session) — several
attempts to click into Analytics from a resized window landed on Settings
instead. I'm flagging this rather than claiming a screenshot I don't have.

## What was intentionally left alone

- Every business-logic file (`AnalyticsService`, `Interview`, backend
  clients, auth) — zero changes.
- The mobile/candidate UI — `AdaptiveNavScaffold`, `CandidateShell`, and
  every mobile chart/card class are byte-for-byte unchanged.
- `SettingsPage`'s internals — already had a clean two-column layout at wide
  widths; only its wrapper (`_RecruiterSettingsTab`) changed, to remove the
  now-duplicate AppBar.
- The global `CardTheme`/typography scale in `AppTheme` — the new desktop
  cards use their own tighter radius via `DesktopCard`, scoped to the new
  widgets, not a site-wide theme change.
