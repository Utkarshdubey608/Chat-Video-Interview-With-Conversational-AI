# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

**Primary (marketing site audience — confirmed 2026-08):** mid-market recruiters and small talent-acquisition teams. They buy quickly, often self-serve, and are hands-on operators rather than governance-led enterprise buyers. Narrative priority is time saved and speed to first interview, not procurement and compliance depth.

**Primary (product users):**
- **Recruiters** — configure interview templates and question sets, invite candidates in bulk, run multi-round pipelines, review scored reports and analytics, manage API keys and the AI avatar.
- **Candidates** — receive an emailed invitation, take an interview in one of six formats, reach a completion screen. They never see scores, reports, feedback, upcoming questions, or any other candidate's data.

**Secondary:**
- **Administrators** — a server-only elevated-visibility overlay on a recruiter account (from an email allowlist). Not a separate role.
- **Website visitors** — pre-login readers of the public `/mimic` site who can submit a demo request.

## Product Purpose

Mimic conducts the first round of hiring. It invites candidates by email, interviews them asynchronously (or live), and scores their answers against a recruiter-defined rubric, returning a ranked shortlist with the evidence attached instead of a queue of applications.

Success = the recruiter stops being the first-round bottleneck, every applicant gets a real structured interview, and every score can be traced back to a specific answer.

## Positioning

Six genuinely different interview formats — timed Q&A, typed conversational, live voice, AI video avatar, recorded video, and live two-way call — all scored against **one** rubric, so results from different formats compare directly. Résumé-adaptive by default: each interview reads the candidate's own résumé and writes its follow-ups around what that résumé claims.

Human-in-the-loop is structural, not a policy statement: the system produces a recommendation, and advancing / rejecting / overriding are recruiter actions, each written to a per-candidate audit history.

## Operating Context

- Recruiters work in a browser, in a workspace with seven top-level areas: Sessions, Templates, Question sets, Pipelines, Analytics, Avatar studio, Settings.
- Candidates interview on their own schedule, frequently on a phone, without installing anything.
- Invitations are delivered by email; each link is bound to one email address and opens only for that address.
- Candidate volume arrives in bursts (a req opening, a campus cohort), so interviews must run unattended and around the clock.

## Capabilities and Constraints

**Interview formats (tracks):** `chat` (Timed Q&A), `chatbot` (conversational), `voice`, `video_avatar`, `video`, `two_way`.

**Confirmed capabilities:** reusable templates; reusable question sets with drag-ordering; résumé-adaptive or fixed question sources; AI question generation from a PDF résumé (1–25 questions); a weighted, editable KPI rubric (six defaults, custom criteria supported, weights auto-normalised to 100%); per-question timers with per-question overrides; integrity monitoring (tab-switch, fullscreen, paste/copy) with candidate warnings; bulk invitation from CSV/Excel/PDF/DOCX/TXT; a customisable invitation email with locked interview-link token; four transition email kinds (invite, advance, selected, rejection); multi-round pipelines with a drag-to-advance board, score-threshold and top-N quick-advance, move-back, and a per-candidate audit history; scored per-candidate reports with PDF export; aggregate analytics; a 55-language in-app assistant with an Autopilot mode that operates the UI behind confirmation gates.

**Technical constraints:**
- The API runs as a **single instance** backed by a JSON file store; it cannot be scaled horizontally without migrating the data layer.
- Live voice sessions cap at roughly 15 minutes.
- Video uploads cap at 50 MB; résumés at 8 MB; candidate lists at 10 MB.
- Without an AI key the product still runs, but question generation and scoring degrade to a length-based heuristic that is explicitly labelled as approximate in the UI.

**Degradation is a product principle, not an accident:** every dependent feature has a defined behaviour when its key is absent (email dry-run, heuristic scoring, avatar 503, guide canned answers).

## Brand Commitments

- **Product name:** Mimic. **Company:** TalbotIQ.
- **Parent company:** Eightfold AI (`https://eightfold.ai/`). *Confirmed by the user 2026-08.* The marketing site is to inherit the parent brand's design language.
- **Existing assets:** `public/talbotiq-logo.png`, `public/talbotiq-logo-full.png`, client logos at `public/mimic-logos/total-it-global.png` and `public/mimic-logos/aisling.webp`.
- **Existing wordmark:** the "M" chevron mark used in the app nav and marketing header.
- **Resolved 2026-08-12:** the violet system inherited from the parent brand is
  the identity **everywhere** — marketing site, recruiter workspace, candidate
  interview, and the dark avatar/live-call surfaces. Confirmed by the user.
  Consequences already applied: the green-tinted app ground (`#eff5f0`) and
  border (`#dde8e0`) became lavender neutrals; the default candidate branding
  accent moved from dark green (`#0d5c3a`) to violet (`#6B2BE0`), which also
  changes the default CTA colour in every invite, advance, selected and
  rejection email; the gold-on-black avatar tokens became a violet-dark world;
  and the intro film's accent moved off gold onto the brand violet.
- **Recruiter-set branding is unaffected.** `BrandingConfig.accentColor` is still
  per-template and still honoured on candidate screens and emails. Only the
  *default* moved — recruiters who chose their own accent keep it.

## Evidence on Hand

**Real and cleared for public use (confirmed 2026-08):**
- Client logos: **Total IT Global**, **Aisling**. (TalbotIQ's own logo is also present in the marquee.)

**NOT real — must not be published (confirmed 2026-08):**
- Every performance statistic currently on the marketing site: "1.3 days median time to shortlist", "62% recruiter hours returned", "340k interviews scored", "33% faster time-to-fill", "500+ candidates per req", "4 min to configure", "8,400 applicants screened", "-71% recruiter hours per hire", "4.6/5 candidate experience".
- The testimonial attributed to "Dana Whitfield, VP Talent Acquisition, Meridian Health" and the customer "Meridian Health".
- Every compliance badge currently displayed: SOC 2 Type II, ISO 27001, ISO 42001, GDPR ready, WCAG 2.2 AA, EEOC-aligned.
- The "340,000 scored interviews" benchmark report premise.

**Consequence for all future work:** the site must earn credibility through product demonstration, mechanism clarity and real screenshots — never through borrowed or invented proof. Where a proof slot is structurally warranted, it must be left visibly empty or omitted, not filled with a placeholder figure. Existing `[PLACEHOLDER: …]` markers in the marketing content table mark other unverified claims and carry the same rule.

## Product Principles

1. **Never fabricate proof.** No statistic, customer, certification or quotation appears unless it is real and cleared. An empty proof slot is acceptable; an invented one is not.
2. **A score is a recommendation with its evidence attached.** Every number traces to a specific answer, and a human makes every decision that affects a candidate.
3. **One rubric, applied identically.** Comparability across candidates and across interview formats is the core value; anything that breaks it breaks the product.
4. **Degrade honestly and visibly.** When a dependency is missing, the product keeps working and says plainly that it is operating in a reduced mode.
5. **The candidate is a user, not a subject.** Disclosure and consent are explicit, the experience works on a phone, progress is never lost, and scores are never shown to them.

## Accessibility & Inclusion

- Candidates interview on whatever device they have; mobile-first behaviour is a functional requirement, not an enhancement.
- Reduced-motion preference is already honoured across the marketing site and interview UI and must remain so.
- The in-app assistant supports 55 languages for both speech input and spoken output; interview language is configurable per template.
- No formal accessibility standard has been confirmed as a contractual commitment. The "WCAG 2.2 AA" badge currently shown on the marketing site is **not** verified and must not be republished.
