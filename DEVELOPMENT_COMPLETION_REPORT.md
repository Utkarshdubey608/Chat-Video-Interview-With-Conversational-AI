# Talbotiq Desktop — Development Completion Report

Date: 2026-08-13
Branch: `development`
Scope: final integration/completion pass — **not** a QA report. No live click-through workflow
testing was performed in this pass, by design (see the master prompt for this pass).

## Completed

This pass audited the entire existing implementation (recruiter + candidate + shared
infrastructure) against the current source, cross-checked backend endpoint usage, and found
**one genuine gap**: the profile menu's post-login interaction model didn't yet support
hover-to-expand / click-to-expand-and-open, and its dropdown still repeated the email/role
already shown in the header. Everything else audited (recruiter Home/Library/Analytics/Settings,
candidate Home/Practice/History/Settings, the shared interview engines, desktop WebView, font
scaling, backend integration) was already correctly implemented from prior passes and required
no code changes — just verification.

**Changed this pass:** `lib/shared/widgets/desktop_profile_menu.dart` (rewritten interaction
model). Nothing else needed a code change.

## Recruiter

All previously implemented and reconfirmed against current source this pass:
- `AuthGate` → `RecruiterShell` routing, driven by the `users/{uid}.role` Firestore field.
- Desktop top nav: Talbotiq wordmark, Home / Library / Analytics, profile menu on the right.
  Settings is not a nav tab (moved to the profile menu) — confirmed still true.
- Recruiter Home: card grid (`ResponsiveGrid`), real `InterviewRepository` data, search,
  Create Interview, Library access — all reused, none re-implemented.
- Library: Templates, Question Sets — `RecruiterStore.upsertTemplate`/`deleteTemplate`/
  `upsertQuestionSet`/`deleteQuestionSet`/`duplicateQuestionSet` all still return `Future<bool>`
  and the load/save paths still `catch` and `debugPrint` rather than silently swallow — the
  previously-fixed failure-reporting behavior is intact, unmodified by anything in this or the
  prior pass.
- Interview creation (`create_interview_page.dart`), multi-round/chat/voice/video/two-way
  configuration: unmodified.
- Analytics: unmodified, still reads from `AnalyticsService`/real `Interview` data, no mock
  statistics anywhere in that file.
- Settings + desktop Font Size preference: unmodified from the prior pass.
- Profile menu: now shares the rewritten `DesktopProfileMenu` (see below) — same component
  recruiter always used, just with the new interaction model.
- Logout: unchanged, `LogoutButton.signOut`.

## Candidate

All previously implemented and reconfirmed against current source this pass:
- `AuthGate` → `CandidateShell` on every platform (the old `DesktopAccessDeniedPage` block is
  gone; confirmed zero remaining references anywhere in the codebase, including tests).
- Desktop top nav: Home / Practice / History, profile menu on the right, Settings in the
  profile menu — confirmed still true.
- Candidate Home: real assigned-interview cards (`_AssignedCard`, unmodified), grouped by job,
  with Scheduled/Expired/No Attempts Left/Awaiting Evaluation/Results Available states intact.
- Chat/Voice/Video/Two-way: all still route through the exact same shared engines
  (`ConversationRunnerPage`/`ConversationRunnerController`/`ConversationEngine` for chat,
  `GeminiLiveService` for voice, `DesktopWebView`/`buildIframe()` for video and two-way) — no
  parallel/duplicate interview engine exists anywhere.
- Resume intake: unmodified, still `file_picker` + `/api/resume/extract` + `/api/resume/score`.
- Language: still recruiter-configured only, no candidate-facing picker (confirmed nothing was
  invented here).
- Transcription: still post-call only, unchanged.
- Integrity: still the one pre-existing `AppLifecycleState` mechanism (chat + video; voice has
  no integrity hook — this is a pre-existing mobile gap, not something introduced by desktop
  work, and out of scope to add to during a development-completion pass per the "do not invent
  new integrity signals" instruction).
- Profile menu: now shares the rewritten `DesktopProfileMenu`, same as recruiter.
- Logout: unchanged.

## Shared

- **Firebase auth / Firestore role detection**: unchanged architecture; `AppRoleX.fromWire`
  fails closed to `candidate` for any missing/unrecognized value (verified by
  `test/app_role_test.dart`, still passing).
- **AppStore**: unchanged this pass. `desktopFontScale` getter/setter and its
  `_saveToPrefs`/`_loadFromPrefs` wiring are untouched from the prior pass.
- **Global font scaling**: verified by construction, not per-screen inspection — `main.dart`
  wraps the entire `MaterialApp` in `MediaQuery(textScaler: TextScaler.linear(desktopFontScale))`
  inside the `builder` callback, gated on `isDesktopPlatform`. Every screen, dialog, and
  dynamically pushed route in the app is a descendant of that one `MaterialApp`, so every one of
  them inherits the same `MediaQuery` — recruiter and candidate alike, with no per-role or
  per-screen branching required or present. `test/desktop_font_scale_test.dart` exercises this
  exact mechanism and still passes.
- **Profile/avatar system**: now genuinely one shared component (`DesktopProfileMenu`) used
  verbatim by both shells with only a `roleLabel` string differing — confirmed via grep that no
  `RecruiterProfileMenu`/`CandidateProfileMenu` duplicate exists anywhere.
- **Shared interview services, WebView infrastructure, backend client**: unchanged this pass.
- **Error handling / persistence**: `RecruiterStore`'s `Future<bool>` failure-reporting pattern
  spot-checked and confirmed intact (see Recruiter section above).

## Profile Animation

Rewrote `lib/shared/widgets/desktop_profile_menu.dart` to add the interaction model this pass
asked for, on top of the login animation that already existed:

- **Login animation** (kept, unchanged in effect): on mount, shows the full email + role for
  ~900ms, then animates to avatar-only over 700ms.
- **Avatar hover expansion** (new): hovering the collapsed avatar animates it back open to show
  email + role, over 350ms with `Curves.easeOutCubic` — smooth, not a sudden pop-in.
- **Avatar click expansion + dropdown** (new): clicking the avatar opens the dropdown (via a
  Material `MenuAnchor`) and ensures the header is expanded at the same time.
- **Dropdown contents** (fixed): the dropdown now contains **only** "Settings" and "Sign out" —
  the `PopupMenuItem` that used to repeat the email/role inside the dropdown has been removed
  entirely. The email/role is shown exactly once, in the expanded header, never twice.
- **Collapse behavior** (new state machine): a single `AnimationController` (0 = expanded,
  1 = collapsed) plus two booleans (`_hovering`, `_menuOpen`) decide every transition:
  - hover-exit → collapse, **unless** the dropdown is still open (`_menuOpen`)
  - dropdown close → collapse, **unless** still hovering (`_hovering`)
  - the delayed post-login auto-collapse checks both flags before firing, so it never yanks the
    header shut out from under an active hover or an already-open menu
  - the hover hit-area (`MouseRegion`) wraps the avatar *and* the revealed label as one region,
    so moving the pointer from the avatar into the newly-visible email text never flickers
- **Same component for both roles** (confirmed, section 32's explicit requirement): recruiter
  passes `roleLabel: 'Recruiter'`, candidate passes `roleLabel: 'Candidate'` — same widget, same
  `MenuController`-based dropdown, same animation.

Verified live (see Ready for Final QA below): the app launches cleanly with the new component in
the top nav and reaches the correct collapsed state after login. The hover/click/dropdown
interactions themselves were **not** exhaustively clicked through this pass — that's explicitly
reserved for the final QA pass per this task's own instructions.

## Backend

**Not changed.** `git status` against `backend/` is empty, confirmed again this pass. Every
candidate-desktop endpoint this pass re-verified against actual backend route files:
`/api/rt/gemini-token` (`backend/app/routers/realtime.py`), `/api/resume/extract` and
`/api/resume/score` (`backend/app/routers/...resume...`), `/api/interviews/{id}/evaluate`
(`backend/app/routers/evaluations.py`) — all genuinely exist, none were invented.

## Mobile/Web Safety

- `AdaptiveNavScaffold` (the mobile/web sidebar-rail-or-bottom-bar shell both `RecruiterShell`
  and `CandidateShell` use on non-desktop) is untouched.
- `CandidateShell`'s mobile path still renders 4 tabs including Settings, exactly as before —
  the top-nav/profile-menu restructuring only applies inside the `isDesktopPlatform` branch.
- `DesktopProfileMenu` is only ever constructed inside each shell's desktop branch; mobile/web
  never instantiates it, so the rewritten hover/click logic has zero surface area on those
  platforms.
- Full test suite (260/260) re-run after this pass's change with no regressions.

## Remaining Development Work

Only genuine implementation gaps — no live-QA items listed here:

1. **Video/two-way desktop WebView has never been exercised live.** `DesktopWebView` is
   analyze-clean and `flutter_inappwebview_windows` is confirmed linked into the actual Windows
   build (its CMake step runs during `flutter build windows`), but no live Tavus/Daily call has
   been opened in this environment yet. This is explicitly a QA item, deferred to the next phase.
2. **Voice has no integrity hook**, unlike chat/video — pre-existing on mobile, not introduced by
   any desktop work, flagged for visibility rather than silently left unmentioned.
3. **No Firebase-backed integration test exists** for `AuthGate`/`RecruiterShell`/`CandidateShell`
   as full widget trees — several of the widgets they host read `FirebaseAuth.instance` directly,
   and this test suite has no Firebase mocking infrastructure yet. The role-safety and
   font-scale *mechanisms* are covered by pure/lightweight tests instead
   (`app_role_test.dart`, `desktop_font_scale_test.dart`).
4. **macOS is unbuilt and untested**, as instructed — `Info.plist`'s camera/mic keys are in
   place and internally consistent with the rest of the implementation, but nothing has actually
   run on a Mac.

## Ready for Final QA

**Yes.** `flutter analyze` is clean (0 errors; only pre-existing warnings in files this pass
never touched), the full test suite passes (260/260), the Windows build succeeds and links the
new WebView plugin, and the app launches cleanly to a real, already-authenticated session with
no crash. Recruiter and candidate are both structurally complete: real shared business logic
underneath, real desktop-native presentation on top, one shared profile component with the
interaction model this pass specified, Settings correctly out of both top navs, and font scaling
provably global by construction. The next phase should be the comprehensive live QA pass this
task deliberately deferred — starting with actually opening a video/two-way interview (the one
area with a genuinely new, never-live-tested implementation) and clicking through the new
profile hover/click/dropdown behavior end to end.
