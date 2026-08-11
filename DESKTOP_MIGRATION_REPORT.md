# Talbotiq Desktop (Windows/macOS) — Migration Report

Date: 2026-08-11
Scope: `talbotiq_app/` (Flutter client), informed by `backend/` (FastAPI) and the
reference website `Chat-and-Video-Interview-with-Sentiment-Analysis-and-Avatar-Conversational-Al--Beta-main/talbotiq-platform/`.

## 1. Architecture decision

**Chosen: extend the existing Flutter app directly with Flutter Desktop
(Windows + macOS), reusing 100% of the existing business logic, models,
services, and backend contracts.** No separate desktop project, no
Electron/Tauri/web-wrapper.

Why this was viable: `talbotiq_app` already had `windows/` and `macos/`
platform folders (stock `flutter create` scaffolds, unconfigured), state
management is plain `provider`/`ChangeNotifier` (platform-agnostic), routing
is a hand-rolled `AuthGate` + imperative `Navigator` (platform-agnostic), and
the backend (`backend/`) authenticates via `Authorization: Bearer <Firebase
ID token>` / `X-API-Key` headers — not cookies — so a native desktop client
is not subject to CORS and needs no proxy; it calls the same REST endpoints
the mobile app calls, unchanged.

The one real architectural risk was the **video-interview track**, which
embeds a Tavus/Daily.co call via `webview_flutter` — a package with **no**
Windows/macOS desktop backend. That is addressed in §5.

## 2. Feature parity matrix

Columns are Website (reference only), talbotiq_app (mobile — source of
truth), Backend, and Desktop (this work). "Native" = fully reused, no new
code. "Adapted" = new code required and added. "Blocked" = not implemented,
requires a decision beyond this task's scope.

| Feature | Website | talbotiq_app (mobile) | Backend | Desktop |
|---|---|---|---|---|
| Auth (Firebase email/password) | Yes | Yes | Verifies Firebase ID tokens | **Native** — same `AuthService`/`AuthGate`, unchanged |
| Recruiter role routing | Yes | Yes (`RecruiterShell`) | Role read from Firestore | **Native** |
| Candidate role routing | Yes | Yes (`CandidateShell`) | — | **Native** |
| Chat interview | Yes (chatbot track) | Yes, fully native (`ConversationRunnerPage` + `ConversationEngine`) | Scoring via `/api/gemini/generate` | **Native** — no WebView, no platform code, runs as-is |
| Voice interview (Gemini Live) | Yes (voice track, server-relayed) | Yes, native: `record` mic → raw WebSocket direct to Google → `audioplayers` playback | Mints ephemeral token only (`/api/rt/gemini-token`); does not proxy audio | **Native at the architecture level.** `record`, `audioplayers`, `permission_handler` all resolved real Windows + macOS plugin implementations (verified via `pubspec.lock` + generated plugin registrant) |
| Video interview (Tavus/Daily.co) | Yes (video_avatar track) | Yes, via `webview_flutter` (mobile) / `HtmlElementView` (web) | Mints Tavus conversation server-side | **Adapted** — new `flutter_inappwebview`-based desktop path added (§5); mobile path untouched |
| Résumé upload/scoring | Yes | Yes (`file_picker` → `/api/resume/extract`, `/api/resume/score`) | PDF→text via Gemini, scoring via Gemini | **Native** — `file_picker` has first-class desktop support |
| Bulk candidate import (CSV/XLSX/TXT) | Partial (invite wizard) | Yes (`file_picker` + `excel` package) | — | **Native** |
| Recruiter analytics dashboard | Yes (richer: funnel, trend, top candidates) | Yes (`fl_chart`, already the most responsive-aware screen in the app — `_ResponsiveGrid` uses `LayoutBuilder`) | Data read live from Firestore | **Native**, and already desktop-friendly |
| PDF report export | Yes | Yes (`pdf`/`printing`) | — | **Native** — `printing` resolved a Windows plugin |
| Settings / appearance / logout | Yes | Yes | — | **Native** |
| Deep links (candidate invite) | N/A (web URLs) | Yes (`app_links`) | — | **Native** — `app_links` resolved a Windows implementation |
| Gemini AI (scoring, question gen) | Yes | Yes, via backend proxy | `providers/gemini.py` | **Native** — no client-side key, unchanged |
| Tavus AI avatar | Yes (2 generations: legacy screening + video_avatar track) | Yes (conversation-only, via backend `providers/tavus.py`) | Yes | **Adapted** (desktop WebView, §5) |
| Hume AI (voice-prosody emotion) | **Yes** (`src/services/hume.ts`, legacy screening flow) | **Not found** in `talbotiq_app` or `backend` | **Not found** (`backend/app/providers/` has no Hume client) | **N/A — out of scope.** Per the task's own rule ("don't treat the website as source of truth when the app doesn't implement a feature"), this is website-only and not part of desktop parity work |
| AWS Rekognition (facial emotion) | **Yes** (`src/services/rekognitionService.ts`) | **Not found** | **Not found** | **N/A — out of scope**, same reasoning |
| Daily.co two-way live recruiter↔candidate call | **Yes** (`LiveInterviewPage`/`TwoWayStage`) | **Not found** as a distinct track (only the video_avatar-style Tavus embed) | **Not found** | **N/A — out of scope** |
| Multi-round hiring pipelines (Kanban) | **Yes** (`PipelinesPage`/`PipelineBoardPage`) | Only single-round + basic round timeline (`InterviewRound`) — not a Kanban pipeline | Partial (`fetch_round_criteria`, no pipeline/Kanban concept) | **N/A — out of scope** (app has its own simpler round model, already reused as-is) |
| "Autopilot" agentic UI operator | **Yes** (website-only) | Not found | Not found | **N/A — out of scope** |
| Mimic Guide in-app assistant | **Yes** (website-only) | App has its own `guide/` feature (simpler onboarding help) — different implementation, already exists | — | **Native** — reused app's own guide as-is, no website port needed |

**Bottom line on parity:** every feature that exists in `talbotiq_app` (the
actual source of truth per the task's own rules) now has a working or
clearly-scoped desktop path. Website-only features (Hume, Rekognition,
Daily.co two-way, pipelines/Kanban, Autopilot) were **not** ported — the task
explicitly says not to treat the website as authoritative over the app, and
building brand-new product features was out of scope for a desktop migration.

## 3. Reused code (unchanged)

Effectively the entire app: `lib/core/`, `lib/features/auth/`,
`lib/features/interviews/` (chat + voice engines, models, repositories),
`lib/features/recruiter/` (analytics, conversation engine, scoring engine,
Gemini service), `lib/features/mailer/`, `lib/features/settings/`,
`lib/shared/providers/app_store.dart`, `lib/features/recruiter/store/recruiter_store.dart`,
all backend API contracts (`lib/core/net/backend_client.dart`,
`backend_config.dart`), the Gemini Live WebSocket client
(`lib/core/services/gemini_live_service.dart` — completely untouched;
architecturally desktop-ready as written), and the mobile WebView
implementation in `iframe_view_stub.dart` (`_MobileWebView` — byte-for-byte
unchanged; still used on Android/iOS).

## 4. New desktop code (added)

| File | Purpose |
|---|---|
| `lib/shared/widgets/iframe_view_stub.dart` — `_DesktopWebView`, `_isAllowedHost` | New `flutter_inappwebview`-based video-call WebView for Windows/macOS/Linux, selected at runtime via `Platform.isWindows	 	 isMacOS	 	 isLinux`; mirrors the mobile implementation's host-allowlist and camera/mic permission-grant logic |
| `lib/shared/widgets/adaptive_nav_scaffold.dart` | New `AdaptiveNavScaffold` — renders the existing `FloatingNavBar` below 760px width, a Material `NavigationRail` sidebar at/above it. No page or business-logic changes; only chrome adapts |
| `lib/main.dart` | Added `_initDesktopWindow()` (via `window_manager`): default 1440×900 window, 1024×700 minimum, centered, titled "Talbotiq" — desktop-only, gated on `Platform.isWindows	 	 isMacOS	 	 isLinux` |
| `lib/features/interviews/recruiter/recruiter_shell.dart`, `lib/features/interviews/candidate/candidate_shell.dart` | Swapped raw `Scaffold`+`FloatingNavBar` for `AdaptiveNavScaffold`; identical `_index` state, identical page list, identical `FloatingNavItem`s |
| `pubspec.yaml` | Added `flutter_inappwebview: ^6.1.5` (desktop video WebView), `window_manager: ^0.4.3` (window sizing) |
| `windows/runner/main.cpp`, `windows/runner/Runner.rc` | Window title/branding "Talbotiq" (was `talbotiq_app`/`com.example`), default size 1440×900 |
| `macos/Runner/Info.plist` | Added `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` (previously absent — required for the OS permission prompt to appear at all) |
| `macos/Runner/DebugProfile.entitlements`, `Release.entitlements` | Added `com.apple.security.network.client`, `com.apple.security.device.camera`, `com.apple.security.device.audio-input`, `com.apple.security.files.user-selected.read-write` (previously only had `app-sandbox`, meaning outbound network calls, camera, mic, and file picking would all have been silently blocked under the sandbox) |
| `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_NAME` → "Talbotiq" (title bar), copyright string updated. Bundle identifier deliberately **left unchanged** (`com.example.talbotiqApp`, matching Android's `com.example.talbotiq_app`) — that's a signing/provisioning decision requiring a real Apple Developer Team ID, not a desktop-support change |
| `lib/core/net/live_token.dart` | **Bug fix**, not a desktop feature: the missing-timestamp fallback returned `DateTime.now()` instead of a genuinely past timestamp, so a token with no `expiresAt`/`connectBy` didn't reliably "fail closed" as the code's own comment intended (caught by the pre-existing `backend_client_test.dart` test, which was failing before this fix). Fixed to return epoch-0. Directly relevant here because the voice-interview desktop path depends on this exact token-staleness check |

## 5. Platform-specific code

- **Video-interview WebView split** (the one real platform fork): mobile
  (Android/iOS) keeps `webview_flutter`; desktop uses `flutter_inappwebview`
  (WebView2 on Windows, WKWebView on macOS). Chosen at runtime inside the
  already non-web-only `iframe_view_stub.dart` file, so the compile-time
  web/native split (`iframe_view.dart`'s `dart.library.html` conditional
  export) is untouched.
- **Window management**: `window_manager` only initializes on
  Windows/macOS/Linux — a no-op on Android/iOS/Web.
- **macOS entitlements/Info.plist** and **Windows runner branding**: platform
  config files only, no Dart code affected.

## 6. UI changes (how mobile layouts were adapted, not replaced)

Per the task's explicit instruction not to stretch mobile UI: the **only**
navigation-chrome change is `AdaptiveNavScaffold` — a width-based
(`LayoutBuilder`, 760px breakpoint) swap between the existing bottom
`FloatingNavBar` (narrow) and a `NavigationRail` sidebar (wide desktop
window). Every page body (`RecruiterHome`, `AnalyticsPage`, `CandidateHome`,
`PracticePage`, etc.) is rendered exactly as before, in the same
`IndexedStack`, with the same state.

Not changed, deliberately: the analytics dashboard (`analytics_page.dart`)
was already found to be the most desktop-considerate screen in the app
(responsive column-count grid) and needed no changes. Interior fixed-width
elements (score chips, the voice-interview orb) were not touched — they are
decorative/internal sizing, not page-breaking, and rewriting them was
explicitly out of scope ("don't redesign the product unnecessarily").

## 7. Backend integration

No backend changes. Confirmed via full audit of `backend/`:
- Auth is header-based (`Authorization: Bearer <Firebase ID token>` /
  `X-API-Key`), not cookie-based, so desktop is not subject to CORS.
- `BackendConfig.baseUrl` (`lib/core/net/backend_config.dart`) already
  defaults to `http://localhost:8000` for any non-web, non-Android-emulator
  platform in debug builds — this covers desktop with zero changes. Release
  builds require `--dart-define=BACKEND_BASE_URL=...` at build time, same as
  mobile.
- The Gemini Live voice track's WebSocket goes **directly from the client to
  Google** (`wss://generativelanguage.googleapis.com/...`); the backend only
  mints a short-lived token via `POST /api/rt/gemini-token`. Desktop uses the
  exact same client code path as mobile — nothing backend-side to adapt.

## 8. Authentication

Unchanged. `AuthService`/`AuthGate`/Firebase Auth flow is 100% reused.
Verified `firebase_core`, `firebase_auth`, and `cloud_firestore` all resolve
genuine native plugin implementations for **both** Windows (federated
`_windows` packages, confirmed present in
`windows/flutter/generated_plugin_registrant.cc`) and macOS (bundled via
CocoaPods in the main package, consistent with the pre-existing
`macos/Podfile`) — this was verified, not assumed.

## 9. Interview functionality

- **Chat**: works unmodified — plain Flutter widgets + HTTP, no
  platform-specific code anywhere in this path.
- **Voice**: works unmodified at the Dart level. `record` (mic capture),
  `audioplayers` (playback), `permission_handler` all resolved real
  Windows + macOS plugin implementations. Not physically tested with a real
  microphone in this environment (no audio hardware in this sandbox) — flag
  for manual QA, exactly as the app's own code comments already say is
  required even on mobile (`gemini_live_service.dart`, `voice_stage.dart`).
- **Video**: required and received new code (§5). Not physically tested
  against a live Tavus/Daily.co room in this environment (no camera
  hardware, and this track needs a real interview/conversation URL) — flag
  for manual QA on both Windows and macOS before shipping.

## 10. AI integrations

Gemini and Tavus integrations are 100% backend-proxied and unchanged; no
client-side keys, no new AI code, no mocked AI behavior anywhere in this
work. Confirmed no hardcoded/fabricated scores or AI responses were
introduced.

## 11. Testing

```
flutter analyze (files touched by this work):     0 issues
flutter analyze (whole project):                  164 info-level issues, 0 errors, 0 warnings
                                                   — all pre-existing `withOpacity` deprecation
                                                     notices unrelated to desktop work; left as-is
                                                     (out of scope, not a desktop regression)
flutter test:                                      184/184 passed
                                                   (1 pre-existing failure fixed — see §4, live_token.dart)
flutter build windows:                             Compiles/resolves correctly through the plugin
                                                   pipeline; BLOCKED at the final native-build step —
                                                   requires Windows "Developer Mode" (or an elevated/
                                                   Administrator shell) for symlink support, which
                                                   Flutter's Windows build has required for any project
                                                   with plugins since Flutter 2. This is a one-time local
                                                   machine setting, not a code issue. This sandboxed
                                                   session's safety layer correctly blocks editing that
                                                   system-wide registry setting on your behalf — enable it
                                                   via Settings → Privacy & security → For developers →
                                                   Developer Mode, or run the build from an Administrator
                                                   terminal, then re-run `flutter build windows`.
macOS build:                                       Not attempted — no macOS hardware/Xcode is available
                                                   in this Windows-only environment. Config is prepared
                                                   (entitlements, Info.plist, bundle settings) but
                                                   UNVERIFIED. Requires a real Mac with Xcode installed.
```

Toolchain installed as part of this work: Flutter SDK 3.44.9 (stable),
Visual Studio 2022 Build Tools 17.14.37 with the C++ desktop workload.

## 12. Known issues

1. **Windows build not completed end-to-end** — blocked on Developer Mode
   (see §11). This is the single actionable item standing between "code
   ready" and "verified running .exe."
2. **macOS build entirely unverified** — no Mac available in this session.
   Config changes are best-effort based on reading Apple's documented
   entitlement/Info.plist requirements, not confirmed against a real build.
3. **Voice and video interview tracks not physically exercised** — no
   microphone/camera hardware in this sandboxed environment, and the video
   track additionally needs a live Tavus conversation URL to test against.
4. **`flutter_inappwebview` desktop `onPermissionRequest` behavior on
   Windows/macOS is implemented per the package's documented API but not
   confirmed against a real getUserMedia() prompt from a Daily.co call** —
   needs manual verification; if WebView2's native permission UI still
   surfaces instead of being silently granted, that's an acceptable fallback
   (not a security problem — it's a Windows-native prompt, not a bypass), but
   should be verified either way.
5. **164 pre-existing `withOpacity` deprecation info-notices** across the
   codebase (not introduced by this work) — cosmetic lint debt, no build
   impact, left untouched per "don't rewrite working code" scope discipline.
6. Bundle identifiers (`com.example.talbotiqApp` / `com.example.talbotiq_app`)
   are placeholders on **every** platform, not just desktop — this predates
   this work and is a business/signing decision (needs a real reverse-domain
   ID + Apple Developer Team ID before any store distribution), intentionally
   not changed here.

## 13. Production readiness

| Area | Status |
|---|---|
| Code changes (WebView split, window sizing, sidebar nav, platform config) | **Ready** — analyzed clean, tests pass |
| Chat interview on desktop | **Ready** (architecturally identical to mobile, no new risk) |
| Voice interview on desktop | **Needs verification** — real hardware QA required |
| Video interview on desktop | **Needs verification** — real hardware + live conversation QA required; newest code in this change set |
| Windows executable | **Needs configuration** — one machine setting (Developer Mode) away from a real build |
| macOS executable | **Blocked** — needs a Mac + Xcode; not achievable in this environment |
| Distribution packaging (.msix/.dmg, code signing) | **Needs external credentials** — Apple Developer account/Team ID and (for MSIX) a code-signing certificate; not fabricated or assumed here |
| Backend | **Ready, unchanged** — no backend work was needed or done |
