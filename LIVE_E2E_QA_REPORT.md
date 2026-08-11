# Talbotiq Recruiter Desktop — Live Windows End-to-End QA

Date: 2026-08-12
Builds on [FINAL_HARDENING_REPORT.md](FINAL_HARDENING_REPORT.md). This is a
live test against the real, running Windows `.exe` and the real backend —
not a code-only audit.

## Summary

Real, live evidence was obtained for backend startup, the Windows build,
app launch, authenticated session restoration, Recruiter Home, candidate
list, and the Analytics dashboard — all against real production data. Live
GUI interaction then hit a hard environmental blocker partway through
(detailed below) that stopped further clicks from registering despite
exhausting every standard Windows input-injection technique. Everything
past that point is honestly marked **NOT TESTED**, not fabricated as
passing.

**No password was ever printed, logged, screenshotted, or written to any
file.** It was never used, in fact — see the Login section below.

## Phase 1 — Backend

Started per the project's own documented quick start (`backend/README.md`
"Quick start"), not guessed:

```
cd backend
python -m venv .venv
.venv/Scripts/python.exe -m pip install -r requirements.txt
cp .env.example .env
.venv/Scripts/python.exe -m uvicorn app.main:app --port 8000
```

`GET /health` → `200 {"status":"ok","provider":"dry_run","sending_ready":true,
"firebase_project":"talbotiq-9cc4e","providers":{"gemini":false,"tavus":false,
"deepgram":false,"email":true}}`. Running the whole session; process
confirmed alive at the end (PID 28476).

`gemini`/`tavus`/`deepgram` read `false` because no real API keys exist in
this environment (only `.env.example` was present, no real `.env` or
service-account file was ever in this repo) — this is the backend's own
documented graceful-degradation behavior, not a bug.

**Important finding before launching the app**: `lib/core/net/backend_config.dart`
makes `BackendConfig.baseUrl` **empty in any release build** unless
`--dart-define=BACKEND_BASE_URL=...` was passed at build time — the
dev-default `localhost:8000` fallback only applies in debug builds
(`kReleaseMode` bypasses it entirely). The previously-built `.exe` was never
built with that flag, so it could not have reached the backend at all. Fixed
by rebuilding: `flutter build windows --dart-define=BACKEND_BASE_URL=http://localhost:8000`.
This rebuild succeeded.

## Phase 2 — Launch

Launched `build\windows\x64\runner\Release\talbotiq_app.exe` directly.
Verified live, not assumed:
- Process starts and stays responsive (`Get-Process` → `Responding: True`).
- Window title is **"Talbotiq"**.
- No crash, no error dialog, across the entire session (confirmed alive at
  the end too).
- The window passed through several resize/snap/maximize states during this
  session (windowed 1440×900 → snapped ~1024×960 → maximized) with no crash
  or layout break in any of them — incidental but real evidence of resize
  robustness, though deliberate 1280×720/1920×1080/etc. testing was not
  performed.

## Phase 3 — Login

**The app launched already authenticated** — Firebase Auth's session
persistence (confirmed working on Windows in the prior report) restored a
prior sign-in automatically, routing straight to `RecruiterShell`. This is
itself genuine evidence that session persistence and the recruiter-role
routing work correctly.

Because of this, **the supplied test credentials were never actually
typed or submitted** — there was no login form on screen to use them on,
and by the time I would have logged out to test the form directly, live
GUI interaction had already stopped responding (see below). The password
was never printed, logged, or written anywhere, consistent with the
security rules — it simply went unused.

**This means the login *form* flow — typing credentials, submitting,
Firebase authenticating, Firestore role lookup — is NOT directly verified
this session.** What IS verified is session restoration + role-based
routing, which exercises the same `AuthGate` code path minus the initial
credential submission.

## Phase 4/5 — Recruiter Home & candidate management

**PASS.** Real production data rendered correctly: a list of real tests
("round test", "seniorflutter", "voice interview", "senior manager", "test",
etc.) each with real dates (2026-07-26 through 2026-08-11) and real
candidate/completion counts, search bar present, no overflow, no crash.

Clicked into a test ("seniorflutter") and the candidate list opened
correctly: action bar (Leaderboard / Rounds & schedule / Retry failed
scoring / Publish results / Delete test) with labeled buttons, search field,
one real candidate row with a real completion count ("4 Qs", "1 completed").
Did not get further into that candidate's evaluation/ATS detail page before
GUI interaction stopped responding (see below).

## Phase 7 — Analytics

**PASS.** Navigated to Analytics (via a sidebar click) and it rendered
correctly with real data:
- Funnel Status: Total 9, Assigned 2, In Progress 1, Completed 6, Published 2
- KPIs: Completion Rate 67%, Avg. Score 22.7, Evaluated Candidates 6
- Score Distribution: a real bar chart with actual bars

No overflow, no broken widgets, real Firestore-backed data. Deliberate
testing at each of 1280×720 / 1440×900 / 1920×1080 was not performed
(superseded by the unplanned resize/snap/maximize sequence noted in Phase 2,
which the page survived without visible breakage each time it was
re-screenshotted).

## Phase 16 — Security / role-restriction check

**PASS — verified as instructed, not live-tested.** Per the master prompt's
own instruction not to test this with the real recruiter account as a
candidate: re-confirmed by reading the current `lib/features/auth/auth_gate.dart`
that the recruiter-only desktop gate (`isDesktopPlatform` → `DesktopAccessDeniedPage`
for any non-recruiter role) is unchanged and intact. The recruiter account's
role was not touched.

## What happened to live interaction — a real, diagnosed environment blocker

After the Analytics navigation above, **every further synthetic click and
keystroke stopped registering with the app**, despite the window
demonstrably being the correct, focused, foreground window at the correct
screen coordinates (all re-verified explicitly, not assumed):

1. `GetForegroundWindow()` confirmed the Talbotiq window was genuinely
   foreground at the moment of each attempt.
2. `GetWindowRect` was re-queried fresh immediately before each click to
   rule out stale coordinates from the window having moved (it did move
   several times during this session — windowed → snapped → maximized —
   consistent with normal desktop use happening on this machine).
3. Escalated through every standard Windows input-injection technique:
   legacy `mouse_event`, `SetForegroundWindow` with `AttachThreadInput` (to
   rule out Windows' foreground-lock protection), direct `PostMessage`/
   `SendMessage` of `WM_LBUTTONDOWN`/`WM_LBUTTONUP` to the window handle
   (bypassing the global input queue entirely), and finally `SendInput`
   (the modern, Microsoft-recommended replacement for `mouse_event`).
   **None of these registered a single further click** — not "sometimes
   worked," genuinely zero for several consecutive, carefully-verified
   attempts, including on multiple different UI targets (a back button, a
   search field, two different sidebar items).
4. The app process itself stayed healthy throughout — never crashed, never
   stopped responding — confirming this is specifically an input-delivery
   problem, not an app freeze.

I flagged this to you mid-session rather than silently either giving up or
fabricating results; you asked me to keep trying more carefully, which is
what the above represents. I could not find a way past it from within this
sandbox. My best explanation is that this is a live, actively-used desktop
session (the window's position kept changing in ways my own actions don't
account for), and something about how input is routed in this specific
setup — possibly session/display redirection — stopped reaching the
target window after an initial window where it did work. **I want to be
direct: I do not have full certainty on the root cause. I'm not fabricating
one.**

## Phases NOT tested, and why

| Phase | Status | Reason |
|---|---|---|
| 6 — Library (Templates/Question Sets/Generate from Résumé/AI Model/Personas/Replicas) | **NOT TESTED** | Could not navigate there after input stopped registering |
| 8 — Interview creation (incl. live voice-default check) | **NOT TESTED live.** Voice-default behavior IS verified — see below | Same |
| 9 — Voice preview | **NOT TESTED** | Same |
| 10 — Video configuration | **NOT TESTED** | Same |
| 11 — Resume upload | **NOT TESTED** | Same |
| 12 — Bulk import (CSV/XLSX/TXT) | **NOT TESTED live.** XLSX off-main-thread fix IS code/test-verified — see below | Same |
| 13 — Evaluation/ATS detail | **NOT TESTED** (only the candidate list row, not the detail page, was reached) | Same |
| 14 — Reports/PDF | **NOT TESTED** | Same |
| 15 — Settings | **NOT TESTED** | Same |
| 17 — Logout/relogin/relaunch | **NOT TESTED live** (see Phase 3 — session restoration is the closest live evidence obtained) | Same |

For the two items with a code-level fallback: the voice-default fix
(`VoiceCatalog.resolveVoiceId`/`resolvePersonaId`) has 8 passing unit tests
verifying it never returns null and falls back to the existing product
default; the XLSX-off-main-thread fix is a byte-for-byte logic extraction
with identical error handling, verified by `flutter analyze`/`flutter test`
passing, not by watching it run live against a real large file. Neither
should be read as "live-verified" — both are exactly what
[FINAL_HARDENING_REPORT.md](FINAL_HARDENING_REPORT.md) already said before
this live session started.

## Phase 19 — Bugs found this session

None. No genuine functional bug was discovered during live interaction —
every screen actually reached (Home, candidate list, Analytics) rendered
correctly with real data and no errors. The one real, significant finding
was the release-build `BACKEND_BASE_URL` configuration gap (Phase 1), which
is an environment/build-configuration issue, not application code — fixed
by rebuilding with the correct `--dart-define`, no source change needed.

## Phase 20 — Final Test Results

```
Backend:                RUNNING
Windows build:           PASS
Windows launch:          PASS
Recruiter login:         PARTIAL — session restore + role routing verified live;
                         credential-submission form flow not exercised (see Phase 3)
Recruiter Home:          PASS
Candidate management:    PARTIAL — candidate list verified live; detail/evaluation
                         page not reached
Library:                 NOT TESTED
Templates:               NOT TESTED
Question Sets:           NOT TESTED
Generate from Resume:    NOT TESTED
AI Model:                NOT TESTED
Personas:                NOT TESTED
Replicas:                NOT TESTED
Analytics:               PASS
Interview Creation:      NOT TESTED
Voice Configuration:     NOT TESTED live (code/test-verified — see above)
Voice Preview:           NOT TESTED
Video Configuration:     NOT TESTED
Resume:                  NOT TESTED
CSV Import:              NOT TESTED
XLSX Import:             NOT TESTED live (code/test-verified — see above)
TXT Import:              NOT TESTED
Evaluation / ATS:        NOT TESTED
Reports / PDF:           NOT TESTED
Settings:                NOT TESTED
Logout:                  NOT TESTED
Relaunch:                NOT TESTED (session-restore on this launch is the closest evidence)

flutter analyze:         PASS (confirmed earlier this session — 0 errors, 0 warnings)
flutter test:            PASS (confirmed earlier this session — 202/202)
```

## Final Status

```
NEEDS FIXES
```

Not because a functional bug was found — none was — but because the
instructions are explicit that Windows recruiter functionality must be
**fully verified** before "READY FOR MACOS QA," and it demonstrably was not:
most interactive phases are genuinely untested live. Calling this
"production ready" or even "ready for macOS QA" would overstate what this
session actually proved. What's true: everything reached live worked
correctly with real data, and the underlying code has been analyze-clean
and test-clean throughout. The concrete next step is either a
non-sandboxed interactive session to finish the click-through, or you
driving the remaining phases directly with me watching backend/logs.
