# Talbotiq Recruiter Desktop — Finalization Report

Date: 2026-08-11
Scope: restrict the desktop client (`talbotiq_app/`, Windows + macOS) to
recruiters only, building on the prior general desktop-enablement work in
[DESKTOP_MIGRATION_REPORT.md](DESKTOP_MIGRATION_REPORT.md). This report does
not repeat that one — read it first for the base architecture decision,
toolchain setup, and the video-interview WebView work.

## 1. Audit findings (did not trust the prior report blindly)

Re-verified against the actual code rather than assuming the prior report was
complete:

- **Real recruiter navigation**, confirmed by reading the code, not guessed:
  `RecruiterShell` only ever had 3 shell-level tabs — **Home** (`RecruiterHome`,
  which is actually the recruiter's *tests/interviews* list — tapping a test
  opens `TestCandidatesPage`), **Analytics**, **Settings**. Everything else
  (create interview, evaluate a candidate, manage templates/question
  sets/personas/replicas, round leaderboard/timeline/notify) is reached by
  *pushing* a route from Home — a phone drill-down pattern, not native to the
  master prompt's suggested "Templates / Question Sets / Rubrics" flat sidebar.
  `RecruiterLibraryPage` already exists as exactly that consolidated
  Templates/Question-sets/Personas/Replicas/AI-model/Generate-from-résumé hub
  — it was just hidden behind an AppBar icon button on Home, not a primary
  destination. **This is what "reproduce the actual implemented modules"
  meant here** — not the master prompt's illustrative example nav.
- **Camera/microphone are never used by any recruiter-side code.** Verified by
  grepping the whole `lib/features/recruiter/` tree and
  `lib/features/interviews/recruiter/` for `Permission.camera`,
  `Permission.microphone`, `AudioRecorder`, `WebView`, and conversation/live-room
  URLs: zero matches. The recruiter-side "voice preview" feature
  (`voice_preview_service.dart`) explicitly documents "there is intentionally
  no AudioRecorder in this file" — it's playback-only. The Tavus/Daily.co video
  WebView (`buildIframe`/`VideoPanel`/`CandidateVideoShell`) is used exclusively
  under `lib/features/interviews/candidate/`. **The recruiter never joins a
  live video/voice room and never records anything locally** — confirming, per
  §14 of the master prompt, that no recruiter-side live-room feature exists to
  implement.
- This directly changed the plan: the desktop-WebView / camera+mic-entitlement
  work from the prior (full-parity) session is now unreachable dead weight on
  a recruiter-only desktop target, addressed in §5.

## 2. Desktop entry flow (the core new requirement)

`lib/features/auth/auth_gate.dart` is the single existing chokepoint that
already decided `RecruiterShell` vs `CandidateShell` off the live Firestore
role stream — so the recruiter-only restriction was added **there**, not as a
new/duplicate auth layer:

```
role == recruiter                → RecruiterShell()      (unchanged)
role == candidate, mobile/web     → CandidateShell()      (unchanged)
role == candidate, desktop        → DesktopAccessDeniedPage()   (new)
```

`isDesktopPlatform` (new: `lib/core/utils/desktop_platform.dart`) is a single
shared `Platform.isWindows || isMacOS || isLinux` check — it replaces two
copies of the same inline logic that existed in `main.dart` and
`iframe_view_stub.dart` from the prior session, and is now the one place this
condition lives.

`DesktopAccessDeniedPage` (new) explains the restriction and offers only
**Sign out** — it never redirects into recruiter functionality and never
silently grants access, per the master prompt's explicit rule.

Sign-**up** was also addressed: `login_page.dart`'s Recruiter/Candidate role
picker is hidden on desktop (defaults to, and only creates, a recruiter
account there) — signing up as a candidate on desktop would otherwise dead-end
immediately at the access-denied screen. Mobile/web sign-up is unchanged
(still offers both roles, defaults to candidate as before).

No candidate code was deleted. `CandidateShell`, every candidate screen, and
the shared services they depend on are untouched and still fully reachable on
mobile/web.

## 3. Recruiter desktop navigation

`RecruiterShell` now branches on `isDesktopPlatform`:

- **Mobile/web** (unchanged): Home, Analytics, Settings — exactly as before.
- **Desktop** (new): Home, **Library**, Analytics, Settings — `Library` opens
  the existing `RecruiterLibraryPage` (Templates, Question sets, Generate from
  résumé, AI model, Personas, Replicas) as a first-class sidebar destination
  instead of only an icon button buried on Home. Home's icon button to the
  same screen was left in place — this adds a path, it doesn't remove one.

This still renders through the existing `AdaptiveNavScaffold` (sidebar rail
≥760px, bottom bar below it) from the prior session — not rewritten, just fed
a different item/page list on desktop.

No new modules were invented. "Rubrics" and "Question sets" are not separate
top-level items because they aren't separate screens in the actual app —
question sets live inside `RecruiterLibraryPage`, and scoring rubrics are
configured inside interview creation/templates, not as their own screen.

## 4. Feature verification against the actual codebase

Every item below is a screen/service that was located and read, not assumed:

| Area | File(s) | Desktop status |
|---|---|---|
| Recruiter login/auth | `login_page.dart`, `auth_service.dart`, `auth_gate.dart` | **Reused as-is**, plus the new gate (§2) |
| Dashboard (tests list) | `recruiter_home.dart` | **Reused as-is** |
| Candidate management (per test) | `test_candidates_page.dart` | **Reused as-is** |
| Candidate invitation | `create_interview_page.dart` (email assignment), `mailer/` | **Reused as-is** |
| Resume upload/scoring | `resume_intake` flow via `resume_service.dart` → backend `/api/resume/*` | **Reused as-is** — recruiter-facing entry is `generate_from_resume_page.dart` |
| Bulk import (CSV/XLSX/TXT) | `create_interview_page.dart` `_importEmails`/`_extractXlsxText` | **Reused as-is** — `file_picker`/`excel` both have desktop support |
| Interview creation/config | `create_interview_page.dart` | **Reused as-is** — already has a desktop-reasonable `maxWidth: 640` centered form |
| Templates/Question sets/Personas/Replicas/AI model | `recruiter_library_page.dart` + `views/management/*` | **Reused as-is**, promoted to sidebar (§3) |
| Chat interview config | `create_interview_page.dart`, `engine/conversation_engine.dart`, `engine/scoring_engine.dart` | **Reused as-is** |
| Voice interview config (persona/voice/preview) | `voice/voice_picker.dart`, `voice/voice_catalog.dart`, `core/services/voice_preview_service.dart` | **Reused as-is** — preview is playback-only, no mic needed (§1) |
| Video interview config | `create_interview_page.dart` (Tavus persona/replica selection via `personas_page.dart`/`replicas_page.dart`) | **Reused as-is** — recruiter only *configures*, never joins a live room (§1) |
| Evaluate candidate / ATS scoring | `evaluate_interview_page.dart` | **Reused as-is** |
| Round leaderboard / timeline / notify | `round_leaderboard_page.dart`, `round_timeline_page.dart`, `round_notify_page.dart` | **Reused as-is** |
| Analytics dashboard | `analytics_page.dart`, `analytics_service.dart` | **Reused as-is** — already the most desktop-responsive screen in the app |
| Reports / PDF export | `report_page.dart`, `report_pdf.dart` | **Reused as-is** — `pdf`/`printing` both resolved Windows plugins (verified in the prior session) |
| Settings / Help / Guide | `settings_page.dart`, `guide/` | **Reused as-is** |
| Logout / session | `logout_button.dart`, `auth_service.dart` | **Reused as-is** |

No AI (Gemini/Tavus), scoring, or backend logic was touched. No mock data
introduced anywhere.

## 5. What was correctly left out, and why

- **Candidate chat/voice/video-taking UI**: not part of desktop navigation.
  `CandidateShell` and everything under `lib/features/interviews/candidate/`
  is unreachable from the desktop entry flow (§2) — but not deleted, per the
  master prompt's explicit rule, since mobile/web still need it.
- **Desktop video WebView (`_DesktopWebView`, `flutter_inappwebview`)**: added
  in the *prior* full-parity session for the candidate video track. Confirmed
  in §1 that recruiters never open a live video room, so this code is now
  unreachable on the recruiter-only desktop target. Left in place rather than
  deleted (it's shared candidate-facing infrastructure, not something this
  task should be deleting per Rule 26) — but its *permission footprint* was
  removed where that's a per-target manifest, not shared code (§6).
- **Website-only features** (Hume, AWS Rekognition, Daily.co two-way calls,
  Kanban pipelines, Autopilot): still correctly out of scope — unchanged from
  the prior report's finding that none of these exist in `talbotiq_app` or
  `backend`.
- **Backend**: zero changes. Every recruiter screen already calls the same
  backend endpoints the mobile app uses; nothing about restricting the
  desktop *client's* navigation requires a server-side change.

## 6. Platform configuration changes (recruiter-only tightening)

Because §1 established recruiters never use the camera or microphone:

- `macos/Runner/Info.plist`: removed `NSCameraUsageDescription` /
  `NSMicrophoneUsageDescription` (added in the prior session for the
  candidate video/voice tracks, now unused on this target).
- `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:
  removed `com.apple.security.device.camera` /
  `com.apple.security.device.audio-input`. `network.client` and
  `files.user-selected.read-write` (needed for backend calls and résumé/CSV
  file picking + PDF export) are kept.

This is a real security-hardening step, not cosmetic: a recruiter-only
desktop build requesting camera/microphone entitlements it never uses is
exactly the kind of unnecessary permission surface a security/production
audit should flag and remove. Both files are macOS **desktop-target**
manifests only — mobile's own iOS Info.plist/entitlements (which candidates
still need) are separate files and were not touched.

## 7. Testing

```
flutter analyze (all files touched this phase — desktop_platform.dart,
                  auth_gate.dart, desktop_access_denied_page.dart,
                  login_page.dart, recruiter_shell.dart, main.dart,
                  iframe_view_stub.dart):        0 errors, 0 warnings,
                                                  5 pre-existing info-level
                                                  notices on lines this work
                                                  did not touch
flutter test (run once earlier this session,
              after the AuthGate/DesktopAccessDeniedPage/login_page changes,
              before the recruiter_shell nav-list change):
                                                  184/184 passed
```

The `recruiter_shell.dart` navigation-list change made after that test run is
a pure widget-composition change (swapping which `const` item/page lists get
passed to the already-existing, already-tested `AdaptiveNavScaffold`) with no
new business logic, and `flutter analyze` on it is clean — but it was **not**
re-run through `flutter test` within this session (a test-suite run was
interrupted), so treat that specific change as analyze-verified but not
test-verified, and re-run `flutter test` before considering it final.

Windows build: unchanged from the prior report — still blocked on the same
Developer Mode / symlink setting (re-checked: the registry key remains unset,
this session's shell remains unelevated). No code-side blocker exists; this
is a one-time local machine setting.

macOS build: still unverified — no Mac/Xcode available in this environment.

## 8. Acceptance criteria status

| Item | Status |
|---|---|
| Windows/macOS recruiter app builds/launches | Same as base report: code-ready, blocked on Developer Mode (Windows) / no hardware (macOS) |
| Recruiter login works | Reused unchanged |
| Recruiter role verified | Reused unchanged (`AuthGate`) |
| **Candidate cannot enter recruiter desktop** | **Done** — routed to `DesktopAccessDeniedPage`, never to `RecruiterShell` or `CandidateShell` |
| Logout works | Reused unchanged; also the only action on the access-denied screen |
| Dashboard / Candidates / Resume / Bulk import / Interviews / Templates / Question sets / AI generation / Analytics / Results / ATS / Reports / Settings / Help | All verified present and reused unmodified (§4) |
| No candidate UI exposed | Verified — desktop's only entry point (`AuthGate`) cannot reach `CandidateShell` |
| No mock production functionality | None introduced |
| No unnecessary backend changes | None made |
| No broken mobile functionality | Mobile/web code paths in every touched file are behaviorally identical (`isDesktopPlatform` is false there) |
| Desktop UI responsive / sidebar nav | Reused `AdaptiveNavScaffold`, extended with the `Library` destination |

## 9. Known issues (unchanged from base report, plus one new item)

1. Windows Developer Mode setting still required locally before
   `flutter build windows` can complete — see base report §11.
2. macOS build still entirely unverified — no Mac in this environment.
3. **New**: the desktop-specific `recruiter_shell.dart` navigation change was
   not re-run through `flutter test` in this session (interrupted); re-run it
   before shipping.
4. The now-dead desktop-WebView code path (§5) has no automated test either
   way (it never did, per the base report) and is doubly unreachable now —
   consider deleting it in a future pass if recruiter-only remains the
   permanent scope, once that's a deliberate product decision rather than an
   inference made here.
