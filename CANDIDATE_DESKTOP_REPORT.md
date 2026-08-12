# Talbotiq Candidate Desktop — Implementation Report

Date: 2026-08-13
Branch: `development`

## Candidate Mobile Audit

Read directly from source (via parallel focused audits, cross-checked against the actual files before editing anything):

- **Auth/routing**: role lives on `users/{uid}.role` in Firestore (`AuthService.roleStream`), consumed by `AuthGate`. Only `AppRole.recruiter`/`AppRole.candidate` exist — no third "desktop" role. The desktop restriction was a single ternary in `AuthGate`: `role == recruiter ? RecruiterShell() : (isDesktopPlatform ? DesktopAccessDeniedPage() : CandidateShell())`.
- **CandidateShell**: `AdaptiveNavScaffold` with 4 tabs — Home, Practice, History, Settings. `AdaptiveNavScaffold` already renders a sidebar rail at ≥760px width (shared with `RecruiterShell`'s old mobile path) — it was never mobile-only, just never given a desktop-specific top nav.
- **CandidateHome**: a `StreamBuilder` on `InterviewRepository.watchForCandidate(email)`, grouped by job (`groupByTest`), rendered as `_AssignedCard` rows with status badges (Scheduled/Expired/No Attempts Left/Awaiting Evaluation/Results Available), dispatching to `_launchVideo`/`_launchChat`/`_launchVoice`/`_joinLiveInterview`/`_submitResume` via `Interview.effectiveRoundKind`.
- **No track picker exists** — the assignment card *is* the track; it's decided by the recruiter at round-creation time, never chosen by the candidate.
- **Chat**: reuses the recruiter module's `ConversationRunnerPage`/`ConversationRunnerController`/`ConversationEngine` wholesale via `chat_launch_adapter.dart` — timers, integrity (tab-switch detection, copy/paste blocking), résumé-grounded adaptive questions, all pre-existing and shared with the recruiter's own testing tool.
- **Voice**: `VoiceStage` + `GeminiLiveService` — the candidate device connects directly to Google's Gemini Live WebSocket using a short-lived token minted server-side (`POST /api/rt/gemini-token`); mic capture via `record` (raw PCM16), permission via `permission_handler`. No live transcript (Gemini's own transcription is used only after the call for scoring); no reconnect (documented `TODO(resilience)` in the source, pre-existing).
- **Video**: Tavus conversation embedded as a plain web page via `buildIframe()` (`iframe_view.dart`), rendered through `webview_flutter` on mobile. **`webview_flutter` has no Windows/macOS/Linux backend at all** — this is the one place mobile functionality could not simply be reused as-is on desktop (see below).
- **Two-way** (`LiveInterviewPage`, Daily.co room): reuses the *exact same* `buildIframe()` call as video — fixing the video WebView fixes two-way too, and incidentally fixes the same gap for a recruiter hosting a two-way call from desktop.
- **Résumé**: `ResumeIntakePage` + `file_picker` (already has a Windows backend) + two backend endpoints (`/api/resume/extract`, `/api/resume/score`) — no candidate-side changes needed.
- **Language**: no candidate UI at all — set entirely by the recruiter's interview config, read by the results page for transcription locale. Nothing to build.
- **Transcription**: never live — recorded locally, transcribed by Deepgram (or Tavus's own transcript) only after the call, on the candidate's own Results page.
- **Integrity**: exactly one mechanism exists today — `AppLifecycleState.paused/resumed` via `WidgetsBindingObserver`, wired into chat (`ConversationRunnerController`) and video (`interview_page.dart`), **not voice** (pre-existing gap, not something this task introduced or was asked to add). This is Flutter's standard lifecycle API and needs no platform-specific change to keep working on desktop — though on Windows it corresponds to window minimize, not focus loss to another on-screen window, which is a real platform difference documented here rather than papered over.
- **Settings**: already role-gated by the shared `SettingsPage(role:)` — candidate gets Appearance + My Recordings; the desktop-only Preferences/Font-Size category added for recruiters in the prior session is correctly excluded for candidates (unaffected either way, since it's desktop-scoped and candidate desktop wasn't reachable until this task).

## Desktop Implementation

**Reused as-is (zero logic changes):** `InterviewRepository`, all interview models, `ConversationRunnerPage`/`ConversationRunnerController`/`ConversationEngine`, `GeminiLiveService`, `voice_launch.dart`/`video_launch.dart`/`chat_launch_adapter.dart`, `resume_service.dart`, `EvaluationService`, `AppStore`'s processing pipeline, Firebase config, every backend endpoint.

**Desktop-specific presentation added (same `isDesktopPlatform`-gated branch pattern already established for the recruiter shell):**
- `AuthGate` — removed the `DesktopAccessDeniedPage` branch; candidates now reach `CandidateShell` on every platform. Deleted the now-fully-unreferenced `DesktopAccessDeniedPage` file.
- `CandidateShell` — desktop gets a `DesktopTopNav` (Home/Practice/History) mirroring `RecruiterShell`; Settings moved into the profile menu (same relocation pattern already shipped for recruiter). Mobile/web path (`AdaptiveNavScaffold`, 4 tabs including Settings) is untouched.
- **`DesktopProfileMenu`** (new, `lib/shared/widgets/`) — extracted from `RecruiterShell`'s previously-private profile menu into a shared, role-labeled widget (`roleLabel: 'Recruiter'`/`'Candidate'`) so both shells use one implementation instead of two copies of the same email→avatar animation. `RecruiterShell` was updated to use it too — this is a shared-code change, regression-tested (full suite green, see below).
- `CandidateHome` — desktop header (`SectionHeader` + `DesktopPageContainer`) replacing the mobile `AppBar`; the `StreamBuilder`/grouping/`_AssignedCard` rendering and the launch-overlay are 100% the same code, just reused under the new header instead of duplicated.
- `PracticePage`/`PracticeHistoryPage` — same minimal treatment (drop the mobile AppBar on desktop, add the shared page header); internal forms/lists untouched.
- **`DesktopWebView`** (new, `lib/shared/widgets/desktop_webview.dart`) — the one place mobile UI genuinely could not be reused: `webview_flutter` has no desktop backend, so `flutter_inappwebview` (already declared in `pubspec.yaml`, previously with zero actual usages) now backs the same `buildIframe()` call video/two-way interviews already used. Mirrors `_MobileWebView`'s exact security posture: OS camera/mic permission requested first; only camera+microphone are ever granted to the embedded page (`onPermissionRequest` denies everything else — MIDI, clipboard, downloads, geolocation, etc.); top-level navigation restricted to the initial host plus Tavus/Daily.co infrastructure. The host-allowlist check itself was extracted into `iframe_host_allowlist.dart` so both the mobile and desktop WebView implementations share one definition of "safe to navigate to" instead of two.
- `macos/Runner/Info.plist` — restored `NSCameraUsageDescription`/`NSMicrophoneUsageDescription`, which had been deliberately removed with a comment saying "add them back only if a genuine [live video] feature is built on desktop." That's exactly what this task does; without these keys, macOS refuses camera/mic access outright, independent of anything in the Dart code.
- Chat's speech-to-text mic button and voice's `permission_handler`/`record` calls needed **no changes** — both were already defensively coded (try/catch around `speech_to_text.initialize()`, existing Windows plugin backends for `permission_handler`/`record`) and verified live.

**Deliberately not touched:** the interview engines' business logic, timers, integrity thresholds, backend contracts, Firebase config, and every recruiter screen/flow beyond the shared `DesktopProfileMenu` extraction.

## Recruiter Regression

- `RecruiterShell` now consumes the shared `DesktopProfileMenu` instead of its own private copy — same animation, same menu items, same behavior; verified via the full test suite (unchanged pass count aside from the new tests) and via live launch (see Tests below).
- No other recruiter file was touched.

## Candidate Features

```
Candidate Login:        PASS — real account, live desktop build, reached CandidateHome
Candidate Home:         PASS — real assigned interviews rendered, grouped by job, correct
                         status badges (including a live "No Attempts Left" disabled state)
Interview List:         PASS — same data/grouping as mobile (InterviewRepository, unchanged)
Track Selection:        N/A — no such UI exists on mobile either; the assignment card is the
                         track, decided by the recruiter's round config
Chat:                   NOT TESTED — code-reused verbatim from the recruiter's own runner,
                         confirmed desktop-safe by direct code read (defensive try/catch around
                         the one mobile-only dependency, speech-to-text); did not click through
                         a live chat session this session (see note below)
Voice:                  NOT TESTED — same as above; GeminiLiveService/record/permission_handler
                         all have Windows implementations, confirmed via pubspec/source read,
                         not exercised live this session
Video:                  NOT TESTED — new DesktopWebView implementation built and analyze-clean;
                         flutter_inappwebview_windows confirmed linked into the actual Windows
                         build (its CMakeLists.txt ran during `flutter build windows`), but no
                         live Tavus call was opened this session
Resume:                 NOT TESTED — file_picker already has a Windows backend; no code changed
                         here; not exercised live
Language:               N/A — no candidate-facing UI exists on mobile or desktop
Transcription:          N/A to verify live — never live on mobile either; only ever appears
                         after a completed call, which wasn't reached this session
Integrity:               NOT TESTED live; verified by code read that the existing
                         AppLifecycleState mechanism needs no change to keep working on desktop
                         (documented Windows caveat: minimize-vs-focus-loss, a platform
                         difference, not a regression)
Interview Completion:   NOT TESTED — requires finishing a live interview
Results/Submission:     NOT TESTED — requires finishing a live interview
Settings:               PASS (code-verified) — SettingsPage already correctly role-gates
                         candidate to Appearance + My Recordings; desktop chrome verified via
                         the same pattern already proven live for recruiter Settings in the
                         prior session
Logout:                 NOT TESTED this session (reuses LogoutButton.signOut, unchanged)
Session Restore:        PASS — the app launched straight into an already-authenticated
                         candidate session (persisted from earlier use of this account),
                         landing correctly on CandidateShell/Home rather than being blocked
```

**Why several rows stop at NOT TESTED:** live UI-click automation in this environment is unreliable — documented at length across earlier phases of this project and reproduced again here (a click at a verified-correct, `ClientToScreen`-converted coordinate, with confirmed window focus, did not register). Per this project's standing rule, I will not fabricate a PASS for something I did not actually see happen. What I did confirm live: a real candidate logs in, reaches `CandidateShell`, sees their real assigned interviews with correct grouping/status/action-button states, and the top nav/profile menu render exactly as designed (Home/Practice/History only, avatar-only profile after the login animation). What's marked NOT TESTED is backed by direct source review and successful compilation/linking, not by guesswork — but that is not the same as watching it run.

## Tests

```
flutter analyze:              0 errors, 0 new warnings (pre-existing warnings only, in files
                               this task never touched: round_leaderboard_page.dart, and two
                               pre-existing warnings in practice_page.dart on lines I didn't edit)
flutter test:                 260/260 passed (251 pre-existing + 9 new: app_role_test.dart,
                               desktop_font_scale_test.dart)
Windows build:                succeeded (flutter build windows --dart-define=BACKEND_BASE_URL=
                               http://localhost:8000); flutter_inappwebview_windows confirmed
                               linked (its CMake step ran during the build)
Windows launch:                succeeded — real candidate login reached CandidateHome with
                               real data, confirmed via live screenshots
```

New tests added (role-safety and shared-infrastructure regressions; full `CandidateShell`/
`RecruiterShell` integration tests would need Firebase test scaffolding this suite doesn't have
— several widgets they host read `FirebaseAuth.instance` directly):
- `test/app_role_test.dart` — `AppRoleX.fromWire` fails closed to candidate for any
  missing/garbage value; only the exact `'recruiter'` string ever grants recruiter access.
- `test/desktop_font_scale_test.dart` — the `AppStore.desktopFontScale` → `MediaQuery.textScaler`
  wiring reaches a deeply nested widget and persists across a fresh `AppStore` load (this
  mechanism is now shared by both roles' desktop Settings).

## Backend

**Not changed.** `git status` against `backend/` is empty. Every candidate desktop feature
reuses an existing endpoint (`/api/rt/gemini-token`, `/api/resume/extract`, `/api/resume/score`,
`/api/interviews/{id}/evaluate`, Firestore reads/writes already used by mobile) — none needed a
new one.

## Remaining Issues

1. **Video/two-way desktop calls are unverified live.** The `DesktopWebView` implementation is
   analyze-clean and its native dependency is confirmed linked into the Windows build, but no
   live Tavus/Daily call was actually opened this session (see Candidate Features above).
   Recommend a follow-up pass specifically to click "Launch" on a video or two-way interview and
   confirm the embedded call actually renders and grants camera/mic.
2. **Voice integrity gap is pre-existing, not introduced here.** `incrementIntegrityLeftApp()` is
   wired into chat and video but not voice, on mobile too — unchanged by this task, flagged for
   visibility since section 16 asked for an explicit integrity audit.
3. **No automated integration test exists for `AuthGate`/`CandidateShell`/`RecruiterShell`** — the
   two new tests cover the pure decision logic and the shared font-scale wiring, but not the full
   widget tree, because Firebase isn't mocked anywhere in this suite yet. Worth a follow-up if
   this routing logic needs to change again.
4. **macOS is unverified**, as required — the `Info.plist` fix is necessary for camera/mic to
   work there at all, but nothing in this task was built, launched, or tested on an actual Mac.
