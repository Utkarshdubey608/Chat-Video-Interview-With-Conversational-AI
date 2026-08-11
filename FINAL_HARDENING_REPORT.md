# Talbotiq Recruiter Desktop — Final Code Hardening

Date: 2026-08-11
Builds on [DESKTOP_MIGRATION_REPORT.md](DESKTOP_MIGRATION_REPORT.md),
[RECRUITER_DESKTOP_REPORT.md](RECRUITER_DESKTOP_REPORT.md), and
[FINAL_QA_REPORT.md](FINAL_QA_REPORT.md). This pass fixes the three specific
issues raised against that QA report, then — because the environment changed
mid-session — went further and achieved a real, launched Windows build.

## Final Changes

### 1. Voice interview validation

Investigated first, per instruction, rather than assuming a fix was needed:
`VoiceCatalog.defaultVoiceConfig` (persona `friendly_hr`, voice `Aoede`)
already exists as the product's established default, and
`create_interview_page.dart`'s `_buildVoiceConfigSection` already *displays*
it as selected before a recruiter touches anything. The actual bug was that
the underlying state field stayed `null` unless the recruiter explicitly
interacted with the picker, so what was saved could diverge from what was
shown as selected.

Fix: added `VoiceCatalog.resolveVoiceId`/`resolvePersonaId` (`lib/features/recruiter/voice/voice_catalog.dart`)
— an explicit, recognized selection is used as-is; anything else falls back
to the existing default. **No new validation error was added** — per the
instruction, an existing default was used instead of inventing a new
required-field rule. `create_interview_page.dart`'s three save sites (single
interview, multi-round shared config, per-round config) now persist the
resolved value instead of the possibly-null raw selection. New test:
`test/voice_catalog_test.dart` (8 cases, no Firestore/widget dependencies —
pure logic).

### 2. RecruiterStore persistence errors

`_saveToPrefs()` now returns `Future<bool>` — and, importantly, it now
actually returns what `SharedPreferences.setString()` reports. **This
surfaced a second, more fundamental bug while fixing the first**:
`setString()` resolves to `false` on a real write failure — it does not
always throw — and the original code (and my own first pass at this fix)
discarded that boolean and returned unconditional success. Fixed to return
`await prefs.setString(...)` directly.

`upsertTemplate`, `deleteTemplate`, `upsertQuestionSet`, `deleteQuestionSet`,
and `duplicateQuestionSet` all now return `Future<bool>` (the in-memory
change + `notifyListeners()` still happen immediately and unconditionally,
matching prior UX — only the *durability* is now honestly reported). Updated
all 5 call sites across the 4 Library editors plus
`generate_from_resume_page.dart`'s "save as set" flow to await the result and
show a distinct message on failure (without exposing raw exception text, per
instruction) instead of an unconditional "Saved". `RecruiterStore` was not
rewritten — `setSlot0Feature`, `upsertSession`, `deleteSession`, `putReport`
are untouched fire-and-forget, exactly as scoped.

New test: `test/recruiter_store_test.dart` (10 cases) — a fake
`SharedPreferencesStorePlatform` whose writes can be told to fail on demand,
covering successful/failed save and delete for both templates and question
sets, plus duplicate. This required adding
`shared_preferences_platform_interface` as an explicit `dev_dependency` (it
was already present transitively; declaring it directly is what the fake
needs to import it, and clears a real analyzer notice about undeclared
transitive-package usage).

### 3. XLSX import performance

Investigated isolate-safety first, per instruction. `_extractXlsxText`
touches no instance state — only `List<int>` bytes in, `String` out — and
every `excel` package object (`book`/`table`/`row`/`cell`) is created and
consumed entirely inside the function, never crossing an isolate boundary
itself. This is exactly the safe shape for `compute()`.

Fix: extracted it as a top-level function (`_extractXlsxTextInBackground` in
`create_interview_page.dart`, `compute()` requires a top-level/static
function, not a bound instance method) with byte-for-byte identical logic
and error handling, and the import flow now calls
`await compute(_extractXlsxTextInBackground, bytes)` instead of a direct
synchronous call. CSV/TXT decoding and the rest of the import flow
(deduplication, error messages, cancellation) are untouched.

## Regression protection

```
flutter analyze:   0 errors, 0 warnings, 160 pre-existing info-level notices
                    (all `withOpacity` deprecation hints predating this and
                    prior sessions' work)
flutter test:       202/202 passed (184 pre-existing + 8 new voice_catalog
                    tests + 10 new recruiter_store tests)
```

Run after every one of the three fixes individually, and once more at the
end after the dependency/pubspec change.

## Desktop scope protection — re-confirmed

- No file was deleted (`git status` shows only `M`/`??`, zero `D`, across the
  whole session).
- `AuthGate`'s routing is unchanged by this pass: recruiter → `RecruiterShell`
  everywhere; candidate → `DesktopAccessDeniedPage` on desktop,
  `CandidateShell` on mobile/web.
- The recruiter desktop sidebar (Home / Library / Analytics / Settings) was
  not touched in this pass.
- Zero backend changes (confirmed via `git status backend/` — clean).
- No stray debug prints, TODOs, or secrets in any file touched this pass.

## Windows build — this changed mid-session

The prior report left Windows blocked on a disabled "Developer Mode" setting.
**That setting is now enabled** (re-checked the registry directly — it was
flipped outside this session, most likely by you after reading the earlier
reports; I did not and could not do this myself). Re-running
`flutter build windows` got past that point and hit a *new*, different
blocker:

```
Nuget is not installed! The flutter_inappwebview_windows plugin requires it.
```

This is an ordinary missing CLI tool (like the earlier Flutter SDK/VS Build
Tools installs), not a security-sensitive machine setting, so I installed it
(`winget install Microsoft.NuGet`) and re-ran the build.

**Result: the build succeeded.**

```
√ Built build\windows\x64\runner\Release\talbotiq_app.exe
```

I then actually launched it and verified, for real, not by inference:

- The process starts, stays running, and reports `Responding: True`.
- The window title is **"Talbotiq"** (confirms the earlier branding fix).
- A screenshot shows the login screen rendering correctly: Talbotiq wordmark,
  email/password fields, Login button, "Sign up" link — no layout errors, no
  crash dialog. Firebase's Windows plugin initialized successfully (if it
  hadn't, `main()`'s `await Firebase.initializeApp(...)` would have thrown
  before the UI ever painted).
- Window sizing was verified by actually forcing a resize via the Win32 API,
  not just reading the config: default size measured at **1440×900**; an
  attempted resize to 600×400 was clamped to exactly **1024×700** — the
  configured minimum, enforced for real by `window_manager`.

**What I could not verify, and did not fabricate:** the authenticated
recruiter workflow (login → dashboard → navigation → backend calls →
logout). I have no valid recruiter credentials for this Firebase project and
won't invent or guess any, and the backend isn't running in this
environment. One more thing worth flagging honestly: the email field
auto-populated with what appeared to be a previously-used real account
address (almost certainly OS-level autofill of locally cached credential
state, not something this session created) — I did not interact with it or
attempt to log in, and I'm not repeating that address here. If this machine
is shared or the screen is ever shared/recorded, that's worth being aware of
independently of anything in this report.

## macOS build

Not attempted — still no Mac or Xcode available in this Windows-only
environment. Config (entitlements, Info.plist, bundle settings) remains
prepared but genuinely unverified.

## Remaining Issues

| Issue | Classification |
|---|---|
| Authenticated recruiter workflow (login → dashboard → navigation → backend → logout) not exercised on the real Windows build | **Credential issue** — needs a real recruiter test account and the backend running; not achievable here without fabricating credentials |
| macOS build/launch never attempted | **Hardware issue** — needs a physical Mac with Xcode |
| Distribution packaging (code signing, MSIX, notarization) | **Credential issue / Apple signing issue** — no Apple Developer Team ID or Windows signing certificate available |
| Backend not running in this environment, so AI/resume/analytics calls from a live build are untested | **Environment issue** — the Python backend was never started this session (out of scope for a Flutter-client hardening pass) |

## Hardware QA Status

- **Windows**: code builds, and the resulting executable actually launches
  and renders correctly — verified with a real process check, a real
  screenshot, and a real forced-resize test, not assumed. The remaining gap
  is exclusively the authenticated in-app workflow, which needs real
  credentials this session does not have.
- **macOS**: still requires actual verification on a real Mac with Xcode —
  nothing here should be read as macOS being tested.

## Final Status

```
READY FOR FINAL HARDWARE QA
```

Upgraded from the prior report's status: Windows now has a real, launched,
correctly-branded, correctly-sized executable with a working login screen —
this is no longer purely code-level verification. It is not
**PRODUCTION READY** because the authenticated recruiter workflow on Windows
is unverified (no test credentials) and macOS has not been touched at all.
