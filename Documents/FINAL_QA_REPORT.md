# Talbotiq Recruiter Desktop — Final QA & Production Verification

Date: 2026-08-11
Builds on [DESKTOP_MIGRATION_REPORT.md](DESKTOP_MIGRATION_REPORT.md) and
[RECRUITER_DESKTOP_REPORT.md](RECRUITER_DESKTOP_REPORT.md). Read against the
actual code, not assumed from those reports.

## What changed in this pass

Two genuine, pre-existing bugs were found and fixed (both are contained,
non-business-logic fixes — no redesign, no interview-engine changes):

1. **`test/interview_round_test.dart`** — `willAutoClose` reads the real wall
   clock, but the test computed its "future" deadline relative to a hardcoded
   `DateTime.utc(2026, 8, 10, 12)` instead of `DateTime.now()`. Real time has
   now passed that point, so the test failed deterministically (not
   flakily — it will keep failing, worse, every day going forward). Fixed by
   anchoring that one assertion's future/past to the real clock. Confirmed
   unrelated to any desktop change — nothing in this session touches round
   timing.
2. **`lib/features/interviews/recruiter/create_interview_page.dart`** —
   `_requiredSkillsController`/`_niceToHaveController` were created but never
   disposed (`dispose()` covers every other controller in the file). Fixed by
   adding the two missing `.dispose()` calls. Relevant to a desktop app
   specifically because recruiters keep it open far longer per session than a
   mobile app that's frequently killed/restarted.
3. **`lib/features/recruiter/views/management/generate_from_resume_page.dart`**
   — a successful Gemini call that yields zero questions (e.g. the requested
   technical/non-technical split has nothing to match) left the screen idle
   with no message — indistinguishable from the button silently doing
   nothing. Added a user-visible explanation in that case.

A dedicated code-audit pass (read every recruiter file listed in the master
prompt's test sections, not just spot-checked) surfaced two further genuine
gaps that were **deliberately not fixed**, because fixing them properly would
cross into business-logic/architecture decisions the brief explicitly warns
against:

- **Voice interviews have no required-field validation** for
  `voiceName`/`voicePersonaId` (`create_interview_page.dart`), unlike Video's
  mandatory replica-ID check. A recruiter who never opens the collapsed
  "Advanced settings" section can save a Voice interview/round with both
  null. Fixing this means deciding what "required" should mean for voice
  (is there a valid default persona, or must a recruiter always pick one?) —
  a product decision, not an obvious bug fix, so it's reported rather than
  silently decided.
- **`RecruiterStore._saveToPrefs()` swallows persistence failures**
  (`debugPrint` only) — every Library editor (Templates, Question sets) shows
  an unconditional "Saved"/"Deleted" confirmation regardless of whether the
  on-disk write actually succeeded. Fixing this correctly means threading a
  failure signal back through `RecruiterStore` and four editor screens —
  more surface than a QA pass should touch without confirming the fix
  direction first. Reported, not fixed.
- **`_extractXlsxText` (bulk import) parses XLSX synchronously on the UI
  thread** — a very large workbook will visibly freeze the app during import.
  No `compute()`/isolate offload exists today. Not fixed here: moving Excel
  parsing off the main isolate is a real (if contained) architectural change,
  and the excel package's decoded objects would need to be confirmed
  isolate-safe first.

Everything else audited (résumé upload error handling, recruiter voice
preview, video/persona/replica configuration, analytics responsiveness,
report/PDF export, ATS evaluation page, settings role-gating, and every
`create_interview_page.dart` validation path not mentioned above) was
**confirmed clean** by reading the actual code — not assumed.

## Test Results

```
flutter analyze:              0 errors, 0 warnings, 160 pre-existing
                               info-level notices (all `withOpacity`
                               deprecation hints predating this work;
                               none on lines this or prior sessions touched
                               beyond what's already reported)

flutter test:                 184/184 passed
                               (1 genuine pre-existing failure found and
                               fixed this pass — see above; re-ran the full
                               suite after every code change in this
                               session, including after the two bug fixes)

Windows build:                NOT COMPLETED. `flutter build windows` and
                               `flutter run -d windows` both fail at the
                               identical point, freshly re-verified this
                               session: "Building with plugins requires
                               symlink support. Please enable Developer
                               Mode." The Developer Mode registry key is
                               confirmed still unset and this shell is
                               confirmed still unelevated. This is an
                               unresolved environment blocker, not a code
                               issue — everything up to that final native
                               link step (dependency resolution, plugin
                               registration, analyze, test) succeeds.
Windows launch:                NOT PERFORMED (build did not complete)
Windows recruiter login:       NOT VERIFIED (no running build to test against)
Windows recruiter workflows:   NOT VERIFIED (no running build to test against)

macOS build:                   NOT ATTEMPTED. No Mac or Xcode is available in
                               this Windows-only sandboxed environment.
macOS launch:                  NOT PERFORMED
macOS recruiter login:         NOT VERIFIED
macOS recruiter workflows:     NOT VERIFIED
```

Everything reported above as "confirmed" or "verified" elsewhere in this
document was verified by reading the actual source files and their existing
automated test coverage, or by running `flutter analyze`/`flutter test`
directly — never by running the compiled desktop app, which was not possible
in this session.

## Remaining Issues

| Issue | Classification | Notes |
|---|---|---|
| `flutter build windows` blocked at the plugin-symlink step | **Windows configuration issue** | One-time local setting: enable Developer Mode (Settings → Privacy & security → For developers), or run the build from an elevated/Administrator shell. Not fixable from within this sandbox — the safety layer here correctly refuses to flip a machine-wide registry setting on the user's behalf. |
| macOS build/launch never attempted | **Hardware issue** | Requires a physical Mac with Xcode. Config (entitlements, Info.plist, bundle settings) is prepared but genuinely unverified. |
| No live-hardware QA of any recruiter workflow (login, dashboard, candidates, resume, bulk import, interview creation, library, analytics, reports, settings, window resize/multi-monitor/DPI) | **Environment issue** | Blocked by the same two items above — there is no running desktop build to click through in this session. Everything reported clean above is code-level verification, not interactive QA. |
| Voice interview save has no required-field check for voice/persona, unlike Video | **Code issue (unresolved by design)** | Reported, not fixed — see rationale above. Needs a product decision on whether a default voice/persona should apply, or the field should be mandatory like Video's replica ID. |
| `RecruiterStore` persistence failures are silently swallowed; Library editors show "Saved" unconditionally | **Code issue (unresolved by design)** | Reported, not fixed — the correct fix touches `RecruiterStore` plus four editor screens; flagging for a deliberate follow-up rather than making that change under a QA-pass mandate. |
| Bulk XLSX import parses synchronously on the UI thread | **Code issue (unresolved by design)** | Only manifests on very large workbooks (freezes the UI during import, does not crash or corrupt data). Needs isolate-safety confirmation for the `excel` package before offloading. |
| Distribution packaging (code signing, MSIX, notarization) | **Credential issue / Apple signing issue** | No Apple Developer Team ID or Windows code-signing certificate available in this environment — not fabricated or assumed. |

## Final Status

```
READY FOR FINAL HARDWARE QA
```

Rationale: the code is analyze-clean (0 errors, 0 warnings), the full test
suite passes (184/184, including a genuine pre-existing bug fixed during
this pass), the recruiter-only entry flow and navigation were re-verified
directly against the current source, zero backend changes exist, and every
recruiter workflow file was read end-to-end with only two low-risk issues
found and fixed and three more explicitly reported rather than guessed at.

It is **not** marked PRODUCTION READY because neither Windows nor macOS has
actually been built and launched — both are blocked by this session's
environment (a local Windows setting, and the absence of a Mac), not by
anything in the code. It is **not** BLOCKED because there is no code-side
obstacle left: the moment Developer Mode is enabled on a Windows machine, or
this is handed to a Mac with Xcode, the remaining verification (Phases 15–16
of the brief — real build, real launch, real click-through) can proceed
immediately with no further code changes expected.
