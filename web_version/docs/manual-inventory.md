# Product Manual Inventory — Mimic / TalbotIQ AI Interview Platform

> **Purpose.** A source-derived inventory of everything a complete end-user manual
> must cover. Every entry cites the file (and line where useful) it was derived
> from. Nothing here is inferred beyond what the code states; anything ambiguous is
> listed under [Open Questions](#open-questions) instead of being guessed.
>
> **Repo root** for all paths: the directory containing `talbotiq-platform/`,
> `render.yaml`, `vercel.json`.
> **Commit context:** branch `feat/mimic-marketing-site`.

---

## Table of contents

1. [Product overview](#1-product-overview)
2. [Roles, permissions and access control](#2-roles-permissions-and-access-control)
3. [Screens and pages](#3-screens-and-pages)
4. [User actions — triggers, inputs, validation, success, failure](#4-user-actions)
5. [Settings and configuration](#5-settings-and-configuration)
6. [Integrations, notifications, exports and files](#6-integrations-notifications-exports-and-files)
7. [Glossary of domain terms](#7-glossary)
8. [Open questions](#open-questions)

---

## 1. Product overview

### 1.1 What the product is

**Mimic** is the product name shown inside the signed-in app (`talbotiq-platform/src/components/layout/Nav.tsx:48`); **TalbotIQ** is the company/brand (`talbotiq-platform/src/features/marketing/content.ts:215`). The public marketing site brands it "Mimic by TalbotIQ" (`talbotiq-platform/src/features/marketing/MimicSite.tsx:115`).

It is a **HireVue-style AI Interview platform**: recruiters configure interviews, invite candidates in bulk by email, candidates take an AI-conducted interview in one of six tracks, and the platform scores answers against a configurable KPI rubric and produces per-candidate reports plus aggregate analytics (`talbotiq-platform/README.md:3-5`).

Two product surfaces exist in one codebase:

| Surface | Description | Entry file |
|---|---|---|
| **AI Interview module** | Templates, question sets, sessions, invites, pipelines, candidate interview flow, per-session report, analytics | `talbotiq-platform/README.md:60-68` |
| **AI Avatar Screening** (originally a separate Tavus app, migrated in) | Recruiter-run live Tavus avatar interview + Deepgram/Hume/Rekognition/Gemini analytics dashboard | `talbotiq-platform/src/App.tsx:80-91`, `talbotiq-platform/server/routes/avatar.ts:9-21` |

A **public marketing site** (`/mimic`) also ships in the same SPA (`talbotiq-platform/src/App.tsx:64-65`).

### 1.2 Who uses it

- **Recruiters** — configure templates/question sets, invite candidates, run pipelines, review reports and analytics, configure the avatar and API keys (`talbotiq-platform/docs/AUTH.md:42-48`).
- **Candidates** — open an invite link (or their assigned-interview list), take the interview, see a completion screen. Candidates never see scores (`talbotiq-platform/src/features/interview/screens/Completion.tsx:24-26`; `talbotiq-platform/README.md:75`).
- **Admins** — a server-only *overlay* on a recruiter (not a role) that grants visibility of unclaimed legacy sessions (`talbotiq-platform/shared/types.ts:12-19`).
- **Website visitors** (pre-login) — browse `/mimic` marketing pages and submit a demo request (`talbotiq-platform/server/routes/leads.ts:6-11`).

### 1.3 Interview tracks (`TrackType`)

Defined at `talbotiq-platform/shared/types.ts:9`. Display labels differ per screen — see the table.

| `TrackType` | Recruiter label(s) | Candidate-facing label | Engine |
|---|---|---|---|
| `chat` | "Timed Q&A" (`server/routes/invites.ts:50`), "Chat — one question at a time (timed slots)" (`TemplateEditorPage.tsx:153`) | "Chat Interview" (`TrackSelect.tsx:15`) | Server-authoritative timed engine (`server/services/timing.ts`) |
| `chatbot` | "Chatbot" / "Conversational" (`invites.ts:50`, `CandidateHome.tsx:9`) | typed chat | Conversational engine (`server/services/conversation.ts`) |
| `voice` | "Voice" | "Voice Interview" (`TrackSelect.tsx:16`) | Gemini Live over WebSocket (`README.md:88-107`) |
| `video_avatar` | "Video Avatar" / "Conversational AI" (`SessionsPage.tsx:245`) | "Video Avatar" (`TrackSelect.tsx:17`) | Tavus conversation + transcript bridge (`server/routes/sessions.ts:274-507`) |
| `video` | "Video Interview" (`invites.ts:50`) | — (format fixed by invite) | Timed engine + live Deepgram transcription (`screens/VideoStage.tsx:21-28`) |
| `two_way` | "Two-way Interview" (`invites.ts:50`) | — (format fixed by invite) | Live Daily call (`docs/TWO_WAY_INTERVIEW.md`) |

### 1.4 Technology (for the manual's "requirements" section)

React 18 · TypeScript · Vite 5 · Express 4 · Tailwind · React Router v6 · Zustand · TanStack Query · Recharts · Framer Motion · @dnd-kit · @google/genai · jsPDF (`talbotiq-platform/README.md:136-138`). Node `20.x` (`talbotiq-platform/package.json:6-8`).

Client dev server: **http://localhost:3001**; API: **http://localhost:8787** (`talbotiq-platform/README.md:16-17`).

npm scripts (`talbotiq-platform/package.json:9-19`): `dev`, `dev:client`, `dev:server`, `server`, `build`, `preview`, `lint`, `test` (runs `scripts/verify-deploy.mjs`), `verify:deploy`.

---

## 2. Roles, permissions and access control

### 2.1 The role model

- Identity: **Firebase Email/Password** on the shared project `talbotiq-9cc4e` (`talbotiq-platform/docs/AUTH.md:16-23`).
- Role source of truth: the Firestore document **`users/{uid}.role`**, chosen by the user at sign-up, read live by the client (`onSnapshot`) and per-request by the server (Admin SDK) (`talbotiq-platform/shared/types.ts:12-19`, `talbotiq-platform/src/features/auth/AuthProvider.tsx:88-104`).
- **No custom claims, no demo mode** (`talbotiq-platform/docs/AUTH.md:23`).
- A missing/unreadable `users/{uid}` doc resolves to **`candidate`** (least privilege) (`talbotiq-platform/server/middleware/auth.ts:17-35`, `AuthProvider.tsx:100`).

### 2.2 Roles

| Role | Value | How assigned |
|---|---|---|
| Recruiter | `recruiter` | Picked at sign-up on `/login` (`LoginPage.tsx:79-97`), written to `users/{uid}.role` (`AuthProvider.tsx:121-127`) |
| Candidate | `candidate` | Picked at sign-up, or the default for a missing role doc |
| Admin (overlay, not a role) | `AuthContext.admin` | Server-only: recruiter **and** email listed in `ADMIN_EMAILS` (`server/middleware/auth.ts:33`, `.env.example:128-131`) |

### 2.3 What each can access

#### Recruiter
Full recruiter app. Route guard `RequireRecruiter` (`src/features/auth/guards.tsx:61-70`); server guard `requireRecruiter` → **403 "Recruiter access required"** (`server/middleware/auth.ts:69-73`).

Recruiter-gated API mounts (`server/index.ts:62-76`): `/api/templates`, `/api/question-sets`, `/api/settings`, `/api/voices`, `/api/analytics`, `/api/invites`, `/api/invite-email-templates`, `/api/pipelines`, `/api/avatar/*`.

Ownership scoping:
- **Sessions** — list is filtered to `recruiterId === auth.uid`; cross-tenant reads return **404 "Session not found"** (never 403) so existence is not leaked (`server/middleware/auth.ts:90-109`, `server/routes/sessions.ts:969-987`).
- **Invite-email templates** — `recruiterId` server-stamped, owner-filtered list, 404 on cross-owner (`server/routes/inviteEmailTemplates.ts:1-33`).
- **Pipelines / pipeline candidates** — same pattern (`server/routes/pipelines.ts:26-32`).
- **Analytics** — scoped to the recruiter's own sessions; admins see the whole tenant (`server/routes/analytics.ts:25-26`, `server/services/analytics.ts:66-74`).
- **Templates and question sets are NOT owner-scoped** — every recruiter sees all of them (`server/routes/templates.ts:19-21`, `server/routes/questionSets.ts:39-41`). See [Open Questions](#open-questions).

#### Candidate
Guard `RequireCandidate` (`src/features/auth/guards.tsx:73-82`). Access is limited to:
- `/candidate` — their own assigned interviews, scoped strictly to their **verified email** (`server/routes/sessions.ts:989-1043`).
- `/take/:sessionId` — only if `session.candidate.email` equals their verified email, else **404 "Session not found"** (`server/middleware/auth.ts:97-119`).
- Candidates **never** receive: future questions, `idealAnswerNotes`, categories, reports, or scores (`shared/types.ts:560-580`, `server/routes/sessions.ts:1045-1047`).

#### Admin overlay
`ownsSession()` returns true for every session when `auth.admin` (`server/middleware/auth.ts:90-95`); admins see unclaimed legacy sessions (`server/routes/sessions.ts:967-968`) and every owner-scoped list.

### 2.4 Redirects and denial screens

| Situation | Result | Source |
|---|---|---|
| Signed out on a guarded route | Redirect to `/login`, remembering `from` | `guards.tsx:66`, `:78` |
| Candidate on a recruiter route | Redirect to `/candidate` | `guards.tsx:68` |
| Recruiter on a candidate route | Redirect to `/sessions` | `guards.tsx:80` |
| `/` or unknown path | `HomeRedirect` → `/sessions` (recruiter) or `/candidate` (candidate); `/login` if signed out | `guards.tsx:85-91` |
| Firebase env missing | "Sign-in isn't configured yet" screen | `guards.tsx:20-35` |
| Role doc unreadable | "We couldn't verify your account" + "Sign out and try again" | `guards.tsx:37-56` |
| `/access-denied` | "Access denied — You don't have permission to view this page." + "Go to my home" / "Sign in" / "Sign out" | `AccessDenied.tsx:14-41` |

### 2.5 Server auth failure codes

| Code | Message | Source |
|---|---|---|
| 401 | `Authentication required` | `server/middleware/auth.ts:61`, `:70`, `:77`, `:86` |
| 401 | `Invalid or expired authentication token` | `server/services/firebaseAdmin.ts:91` |
| 403 | `Recruiter access required` | `server/middleware/auth.ts:71` |
| 403 | `Admin access required` | `server/middleware/auth.ts:78` |
| 404 | `Session not found` (cross-tenant / not assigned) | `server/middleware/auth.ts:108`, `:118` |
| 503 | `Authentication is not configured on the server (<reason>)` | `server/services/firebaseAdmin.ts:81`, `:98` |

### 2.6 Firestore & Storage rules (what a user can touch directly)

- `users/{uid}` — read/create/update only your own doc; delete always denied (`talbotiq-platform/firestore.rules:41-45`).
- `interviews/{id}` — recruiters manage their own; candidates may read + update interviews assigned to their lowercased email but cannot create/delete or flip `resultPublished` (`firestore.rules:51-69`).
- `recruiter_keys/{recruiterId}` — readable by any signed-in user, writable only by that recruiter (`firestore.rules:74-77`).
- Storage `/interviews/{sessionId}/{fileName}` — read+write only by the assigned candidate or the owning recruiter; **max 50 MB**; `contentType` must match `video/*` (`talbotiq-platform/storage.rules:16-25`).

### 2.7 Documented security caveats (must appear in the manual's admin section)

- **Self-assigned role / privilege escalation** — users write their own `users/{uid}` doc at sign-up, so a user can self-select `recruiter`. Intentional, for Flutter-app interop (`docs/AUTH.md:81-89`).
- **No email-verification gate** (`docs/AUTH.md:89-91`).
- **Interview DATA does not interoperate** with the Flutter app (web uses the Express JSON store; Flutter uses Firestore) (`docs/AUTH.md:97-103`).

---

## 3. Screens and pages

Route table from `talbotiq-platform/src/App.tsx:59-108`. Top nav from `src/components/layout/Nav.tsx:17-25`.

### 3.1 Public

| # | Screen | Route | Purpose | What the user can do | Source |
|---|---|---|---|---|---|
| P1 | **Login / Sign-up** | `/login` | Authenticate; pick role at sign-up | Toggle Sign in ⇄ Create account; pick **candidate**/**recruiter**; enter Full name (sign-up only), Email, Password; submit | `src/features/auth/LoginPage.tsx` |
| P2 | **Access denied** | `/access-denied` | Permission failure page | "Go to my home", "Sign in", "Sign out" | `src/features/auth/AccessDenied.tsx` |
| P3 | **Mimic marketing home** | `/mimic` | Public product landing page | Read hero/outcomes/tracks/process/showcase/testimonial/trust/resources/FAQ; **Book a demo** form; jump links `#demo`, `#how`, `#trust`, `#faq` | `src/features/marketing/MimicSite.tsx` |
| P4 | **Mimic content pages** | `/mimic/*` | ~50 generated marketing pages (hubs + detail) driven by a content table | Read; breadcrumb nav; "Book a demo"; on `resources/roi-calculator` use the interactive ROI sliders | `src/features/marketing/MarketingPage.tsx`, `content.ts` |
| P5 | **Marketing 404** | `/mimic/<unknown>` | Not-found state | "Back to home", "Explore solutions" | `MarketingPage.tsx:36-50` |

Marketing IA (nav mega-menu + footer), all under `/mimic` (`content.ts:36-157`):
- **Platform** — Interview tracks (conversational-chat, voice-screening, ai-video-avatar, live-two-way, timed-qa); Workflow (bulk-invitations, interview-templates, question-sets, pipelines, rubrics-scoring); Intelligence (candidate-reports, recruiter-analytics, signal-analysis, mimic-guide)
- **Solutions** — By use case (high-volume-hiring, campus-graduate, technical-screening, sales-customer-facing, frontline-hourly, internal-mobility); By team (talent-acquisition-leaders, recruiters, hiring-managers, rpo-staffing, people-analytics); By industry (bpo-contact-centres, it-services, retail-hospitality, healthcare, financial-services)
- **Trust** — Responsible AI (how-mimic-scores, bias-testing-audits, human-in-the-loop, model-data-transparency, candidate-rights); Compliance (eu-ai-act, nyc-local-law-144, illinois-aivia, gdpr-india-dpdp, eeoc-adverse-impact); Security (trust-center, certifications, data-residency-retention, sub-processors, status)
- **Resources** — Learn (blog, guides, webinars, question-library, rubric-templates, glossary); Proof (customer-stories, roi-calculator, benchmark-report); Build (documentation, api-reference, ats-integrations, changelog, help)
- **Company** — About (about, careers, newsroom, contact); Connect (partners, reseller, events, legal)

> Marketing copy contains explicit `[PLACEHOLDER: …]` strings for anything unverified (certifications, auditors, sub-processor list, customer stories, etc.) — e.g. `content.ts:339`, `:348`, `:397`, `:405`, `:424`. These must **not** be presented as facts in the manual.

### 3.2 Candidate

| # | Screen | Route | Purpose | What the user can do | Source |
|---|---|---|---|---|---|
| C1 | **My interviews** ("Your interviews") | `/candidate` | List of interviews assigned to the signed-in candidate's email | See template name, role, track label, status; **Start interview** / **Continue** (`/take/:id`); Completed badge; Sign out | `src/features/candidate/CandidateHome.tsx` |
| C2 | **Take interview (shell)** | `/take/:sessionId` | Hosts the whole candidate flow | Progress through the pre-steps then the track-specific stage | `src/features/interview/TakeInterviewPage.tsx` |
| C2a | Track select ("Choose your format") | (step) | Only when the track is not fixed by the invite | Choose **Chat Interview** / **Voice Interview** (tag "New") / **Video Avatar** (tag "Preview"); Continue | `screens/TrackSelect.tsx` |
| C2b | Welcome | (step) | Branded rules screen | Read 3 rules (prep/answer seconds, auto-submit, one-at-a-time); **Continue** | `screens/Welcome.tsx` |
| C2c | Résumé + name intake ("Tell us about you") | (step) | Full name + résumé upload | Enter full name; choose PDF/DOCX/TXT (max 8 MB); **Continue** | `screens/ResumeUpload.tsx` |
| C2d | System check | (step) | Readiness confirmation | Tick "I understand the rules and I'm ready to begin"; **I'm ready, begin** | `screens/SystemCheck.tsx` |
| C2e | Video intro / consent | (step, `video` track) | Consent gate | Tick "I understand my responses are recorded and analysed by AI…"; **I consent — begin** | `screens/VideoIntro.tsx` |
| C2f | Camera & microphone check | (step, `video_avatar` / `two_way`) | Device permission + preview | **Enable camera & microphone**; **I'm ready, begin** | `screens/VideoSystemCheck.tsx` |
| C2g | Face-fit pre-flight | (inside `AvatarStage`, and `/interview` via `AvatarScreeningGate`) | On-device face framing aid (MediaPipe) — *not* the scoring facial analysis | Position face; auto-locks after a hold; "Having trouble?" escape appears after a delay | `src/features/avatar-screening/facefit/FaceFitCheck.tsx`, `facefit/config.ts` |
| C2h | Question stage (timed) | (step) | One question at a time, prep → answer | Read question; countdown ring; **Start answering now** (skip prep); type answer; **Submit & continue** | `screens/QuestionStage.tsx` |
| C2i | Chatbot stage | (full screen) | Conversational typed interview | Answer readiness Yes/No dropdown; optional 30/45/60s break; type answers; Enter to send; skip prep sub-timer | `screens/ChatbotStage.tsx` |
| C2j | Voice stage | (full screen) | Live spoken interview | **Start voice interview**; mute/unmute; **End interview**; toggle captions | `screens/VoiceStage.tsx` |
| C2k | Video stage | (full screen within shell) | Webcam answers, live transcription | Camera preview; **Start recording now**; **Submit & continue** | `screens/VideoStage.tsx` |
| C2l | Two-way stage | (full screen) | Live call with the recruiter | Lobby (waiting/knocking); mic/cam toggles; **End interview** | `screens/TwoWayStage.tsx` |
| C2m | Completion | (step) | "All done, thank you!" | Close the window; told scores aren't shown to candidates | `screens/Completion.tsx` |

### 3.3 Recruiter — AI Interview module

| # | Screen | Route | Purpose | What the user can do | Source |
|---|---|---|---|---|---|
| R1 | **Sessions** | `/sessions` | Recruiter home. Table of sessions | Columns: Candidate, Template, Track, Status, Score, Actions. **+ Single link** modal, **Invite candidates** (wizard), **Copy link**, **Join live interview →** (two-way, not finished), **View report →** (completed) | `src/features/recruiter/SessionsPage.tsx` |
| R2 | **Invite wizard** | `/sessions/new` | 5-step bulk invite / pipeline creation | Step 1 Basics, 2 Questions, 3 Candidates, 4 Invite email, 5 Review & send; success table with per-recipient status, Retry, Copy link, Copy all links | `src/features/recruiter/InviteWizard.tsx` |
| R3 | **Templates** | `/templates` | Card grid of interview templates | **+ New template**, Edit, Duplicate, Delete (confirm `Delete “<name>”?`) | `src/features/recruiter/TemplatesPage.tsx` |
| R4 | **Template editor** | `/templates/:id` | Full template configuration + live preview | Sections: Basics, Questions, Conversation, Voice & persona, Per-question timer, Timing, Scoring rubric, Branding, Integrity; **Save template**; **Generate set from résumé** | `src/features/recruiter/TemplateEditorPage.tsx` |
| R5 | **Question sets** | `/question-sets` | Two-pane CRUD editor | **Generate from résumé**, **New set**, rename, drag-to-reorder, add/remove questions, edit category + ideal-answer notes, Duplicate, Delete, Save | `src/features/recruiter/QuestionSetsPage.tsx` |
| R6 | **Report** | `/sessions/:id/report` | Per-candidate scored report | Gauge, recommendation badge, AI summary + strengths/improvements, KPI radar, KPI bars, integrity chips, per-question accordion (with video + transcript), call recording player, Interviewer review (two-way), full transcript, facial analysis (video), Signal analytics; **Export PDF** | `src/features/recruiter/ReportPage.tsx` |
| R7 | **Pipelines** | `/pipelines` | List of multi-round pipelines | Filter by Role, From/To dates, Clear; open a pipeline card | `src/features/recruiter/PipelinesPage.tsx` |
| R8 | **Pipeline board** | `/pipelines/:id` | Kanban progression board | Columns = rounds + **Selected** + **Not advancing**; drag advanceable cards; per-card **Advance →**, **Not advancing**, **Move back**, **History**; per-column quick-advance (Score ≥ / Top N + Apply); **Export CSV** on Selected | `src/features/recruiter/PipelineBoardPage.tsx` |
| R9 | **Live interview (host)** | `/live/:id` | Recruiter's two-way call room (no nav chrome) | **Admit \<name\>**, mic toggle, record toggle, cam toggle, **End interview**; "Go to report" escape hatch | `src/features/recruiter/LiveInterviewPage.tsx` |
| R10 | **Analytics** | `/analytics` | Aggregate dashboard | Filters (Track, Template, Role, From, To, Clear); stat cards; score distribution; average-score trend; KPI averages; By Track; Recommendations; By Role; By Template; Top Candidates (click → report) | `src/pages/AnalyticsPage.tsx` |

### 3.4 Recruiter — AI Avatar Screening (Tavus suite)

| # | Screen | Route | Purpose | What the user can do | Source |
|---|---|---|---|---|---|
| A1 | **Avatar studio / Setup** | `/setup` | Configure the Tavus avatar | Replica picker + manual ID; Persona; AI Interviewer Name; Conversation Name; Conversational Context; Custom Greeting; Callback URL; Language; Pipeline Mode; Max Call Duration; timeouts; toggles (Transcription, Recording, Conversation Override, Virtual Background); S3 recording fields; live JSON request preview; **Apply to Candidate Interviews**, **Launch Test Session**, **Save Draft**; load/delete saved drafts | `src/pages/SetupPage.tsx` |
| A2 | **Interview room** | `/interview` | Live Tavus avatar call (candidate-view chrome) | Face-fit gate first (`AvatarScreeningGate`), then: Full Screen / Exit Full Screen, status line ("Interviewer is speaking" / "Listening — please answer"), question counter, **End Interview** | `src/pages/InterviewPage.tsx`, `src/features/avatar-screening/AvatarScreeningGate.tsx` |
| A3 | **Results** | `/results` | Avatar-screening analytics dashboard | Overall score ring + verdict; KPI row; Dimension scores; Hume emotion dashboard (radar, category panel, timeline, heatmap, per-question cards); Voice & Signal analytics; Strengths / Watch Points; Interview Timeline; AI Recommendation; full transcript; Gemini ATS assessment (+ Re-run analysis); Facial Analysis; Recruiter Actions (Schedule Technical Interview, **Download AI Report**, Share Profile, Generate Offer Rec., New Interview) | `src/pages/ResultsPage.tsx` |
| A4 | **Replicas** | `/replicas` | Manage Tavus replicas | Card grid with status + training progress; click to open details modal (Replica ID, Status, Type, Created); **Rename Replica** → Save Changes; **Delete**; **+ New Replica** (informational toast); "Open Tavus Dashboard ↗" | `src/pages/ReplicasPage.tsx` |
| A5 | **Personas** | `/personas` | Manage Tavus personas | Card grid; **+ New Persona** / Edit / Delete; modal with Identity, LLM layer, TTS layer, STT layer, Perception layer, VQA layer + live API JSON preview | `src/pages/PersonasPage.tsx` |
| A6 | **Settings** | `/settings` | Credentials & platform config | Tavus API key (show/hide, **Test Tavus Connection**); Gemini key card (server-side); read-only status for Deepgram / Hume / AWS Rekognition; Webhook URL; platform toggles; **Save Settings**; **Reset to Defaults** | `src/pages/SettingsPage.tsx`, `src/features/recruiter/GeminiKeyCard.tsx` |

### 3.5 Global overlay — Mimic Guide

Mounted for every signed-in user inside the router (`src/App.tsx:110-112`).

| Element | Behaviour | Source |
|---|---|---|
| Floating launcher (bottom-right) | Opens the Guide panel; pulsing dot | `src/features/guide/MimicGuide.tsx:900-905` |
| Panel header | Title "Mimic Guide", subtitle "Your TalbotIQ AI assistant"; toggles: **Autopilot**, **Voice**, auto-speak (speaker icon), **Clear chat**, close | `MimicGuide.tsx:1002-1085` |
| Voice language selector | Searchable dropdown; **55 guide languages** — verified: `LANGUAGES` has exactly 55 entries (`src/lib/languages.ts:1-3`, `:19+`) | `MimicGuide.tsx:144-237` |
| Suggested prompts | Localised for `en, hi, mr, ta, te, kn, ml`; everything else falls back to English | `MimicGuide.tsx:41-84`, `:139-141` |
| Messages | Markdown answers with in-app deep links; per-message **Listen** / **Stop** | `MimicGuide.tsx:1238-1290` |
| Composer | Mic button, textarea ("Ask anything about TalbotIQ…"), Send; Enter sends, Shift+Enter newline | `MimicGuide.tsx:1188-1231` |
| Autopilot strip | Step tracker text, action log, read-back **Confirm** / **Cancel** card | `MimicGuide.tsx:1088-1120` |
| Hands-free voice pill (panel closed) | Listening state, heard text, mic level bar, **Restart**, **Open**, close | `MimicGuide.tsx:910-976` |

---

## 4. User actions

For each action: **trigger → inputs & validation → success → failure (with exact messages)**.

### 4.1 Authentication

#### 4.1.1 Sign in
- **Trigger:** `/login` → "Sign in" button (`LoginPage.tsx:107-114`).
- **Inputs:** Email (`type=email`, required), Password (`type=password`, required). Email is trimmed (`LoginPage.tsx:111`).
- **Success:** `AuthProvider` role stream re-routes to `from` or `/sessions` (recruiter) / `/candidate` (candidate) (`LoginPage.tsx:38-41`).
- **Failure messages** (`LoginPage.tsx:11-23`):
  - `auth/invalid-credential`, `auth/wrong-password`, `auth/user-not-found` → **"Incorrect email or password."**
  - `auth/email-already-in-use` → **"An account with that email already exists — sign in instead."**
  - `auth/weak-password` → **"Password should be at least 6 characters."**
  - `auth/invalid-email` → **"That doesn't look like a valid email address."**
  - `auth/too-many-requests` → **"Too many attempts — please wait a moment and try again."**
  - default → the raw Firebase message, else **"Something went wrong. Please try again."**

#### 4.1.2 Sign up
- **Trigger:** "New here? Create an account" → "Create \<role\> account" (`LoginPage.tsx:113`, `:117-123`).
- **Inputs:** role toggle (`candidate` default), Full name (optional), Email (required), Password (required, Firebase min 6 chars).
- **Success:** Firebase account created; `updateProfile` sets displayName (non-fatal on failure); `users/{uid}` written with `email`, `emailLower`, `role`, optional `name`, `createdAt` server timestamp (`AuthProvider.tsx:114-130`).
- **Failure:** same message table as sign-in.

#### 4.1.3 Sign out
- **Trigger:** Nav log-out icon (`Nav.tsx:96-103`), CandidateHome "Sign out" (`CandidateHome.tsx:26-31`), AccessDenied, AccountError, TakeInterviewPage "Sign out & switch account" (`TakeInterviewPage.tsx:59-64`).
- **Success:** Firebase `signOut`, role/name cleared (`AuthProvider.tsx:132-135`).

### 4.2 Recruiter — templates

| Action | Trigger | Inputs / validation | Success | Failure |
|---|---|---|---|---|
| Create template | `/templates` → **+ New template** | none (server defaults: name `New template`, role `Software Engineer`) | navigates to `/templates/:id` | toast = error message (`TemplatesPage.tsx:20`) |
| Duplicate template | card → **Duplicate** | copies with `(copy)` suffix | toast **"Template duplicated"** | — |
| Delete template | card → trash | `confirm("Delete “<name>”?")` | toast **"Template deleted"**; server 204 | — |
| Save template | `/templates/:id` → **Save template** | whole template object PUT | toast **"Template saved"** | toast = server error |
| Server: get/update unknown template | — | — | — | 404 **`Template not found`** (`server/routes/templates.ts:25`, `:67`) |

**Template fields, defaults and allowed values** — see §5.2.

### 4.3 Recruiter — question sets

| Action | Trigger | Inputs / validation | Success | Failure |
|---|---|---|---|---|
| New set | **New set** | server default name `Untitled set` (`questionSets.ts:93`) | toast **"Set created"** | — |
| Duplicate | **Duplicate** | name becomes `<name> (copy)`; question ids regenerated | toast **"Set duplicated"** | 404 **`Question set not found`** |
| Delete | trash | `confirm("Delete “<name>”?")` | toast **"Set deleted"** | — |
| Save | **Save** | name (blank keeps existing); questions array order **is** the saved order | toast **"Set saved"** | toast = error |
| Reorder | drag handle | `@dnd-kit` pointer (5px activation) or keyboard | order persisted on Save | — |
| Add question | **Add question** | new blank row (text, category, ideal-answer notes) | — | — |

#### 4.3.1 Generate a question set from a résumé
- **Trigger:** "Generate from résumé" / "Generate set from résumé" / "Generate questions from a résumé instead" (`QuestionSetsPage.tsx:111`, `TemplateEditorPage.tsx:179-181`, `SessionsPage.tsx:209-215`).
- **Inputs & validation** (`GenerateFromResumeModal.tsx`):
  - Résumé file — **PDF only**, **max 10 MB**. Client errors: **"Please choose a PDF file."** (`:69`), **"File is too large (max 10 MB)."** (`:70`).
  - Question style — `technical` / `non_technical` / `mix` (default `mix`).
  - `# Technical` and `# Non-technical` — 0–25 each; total must be **1–25**, else **"Total questions must be between 1 and 25 (currently N)."** (`:191`).
  - Difficulty — `easy` / `medium` / `hard` / `mixed` (default `mixed`).
  - Role (optional), Question set name (optional → auto from role).
  - Model — `gemini-2.5-flash` (default) or `gemini-2.5-pro`.
  - Gemini API key field appears only when no server key is saved.
- **Success:** review step lists generated questions (editable text, type, difficulty; category/skill badges); **Save question set** → toast **"Saved “\<name\>” (N questions)"**.
- **Server validation & failures** (`server/routes/questionSets.ts:51-87`):
  - 400 **`No résumé PDF uploaded`**
  - 400 **`Only PDF résumés are supported`**
  - 400 **`Total questions must be between 1 and 25`**
  - 400 **`No Gemini API key configured. Add one in Settings or enter it in this dialog.`**
  - 502 **`Gemini rejected the API key. Make sure it's a valid Google AI Studio key (they start with "AIza").`**
  - 502 **`Gemini rate limit / quota exceeded. Wait a moment and try again.`**
  - 502 **`Gemini blocked this request for safety reasons. Try a different résumé.`**
  - 502 **`Gemini request failed. Please try again.`**
  - 502 **`Gemini returned no questions. The résumé may be empty/scanned — try another file.`**
  - Client save failure: toast **"Add at least one question"** (`GenerateFromResumeModal.tsx:106`), **"Save failed"**.

### 4.4 Recruiter — create a single session

- **Trigger:** `/sessions` → **+ Single link** (`SessionsPage.tsx:100`).
- **Inputs** (`SessionsPage.tsx:201-274`):
  - **Template** (required — Create button disabled without it).
  - **Candidate name** (optional; defaults to `Candidate`).
  - **Candidate email** — *required by the server*: 400 **`A candidate email is required to assign this interview`** (`server/routes/sessions.ts:141`).
  - **Interview mode (optional override)** — `Use template default`, `chatbot`, `voice`, `chat`, `video_avatar`.
  - **Per-question timer** toggle + **Answer time per question (seconds)** (min 10, default 120). Hint: "Candidates get M:SS per question; auto-submits at 0."
- **Special case:** choosing `video_avatar` without an applied avatar closes the modal, shows toast **"Configure your AI avatar once — it then applies to all Conversational AI candidates."** and navigates to `/setup` (`SessionsPage.tsx:231-236`).
- **Success:** toast **"Session created"**; the modal shows the shareable link with **Copy** and **Open as candidate ↗**.
- **Other server failures:**
  - 400 **`Unknown templateId`** (`sessions.ts:135`)
  - 400 **`Template references an empty or missing question set`** (`sessions.ts:149`)

### 4.5 Recruiter — bulk invite wizard (`/sessions/new`)

Five steps (`InviteWizard.tsx:50-56`): **Basics · Questions · Candidates · Invite email · Review**.

#### Step 1 — Basics
- **Interview type:** `Single Interview` (default) or `Multiple Rounds`.
- **Interview mode** (single only): Chatbot, Voice, Video Avatar, Timed Q&A, Video Interview, Two-way Interview (`:34-41`).
  - Picking **Video Avatar** without an applied avatar → toast **"Configure your AI avatar once — it then applies to every candidate in this batch."** and navigate to `/setup` with `returnTo` (`:566-570`).
- **Candidate role** — required, **≥ 2 characters** (`:434-436`).
- **Next gate:** single ⇒ mode + role; multi ⇒ role only.

#### Step 2 — Questions (single) / Rounds (multi)
- **Single, non-two-way:** choose **Tailor questions to each résumé** or **Your question sets**.
  - Tailor config panel: style (`technical|non_technical|mix`), `# Technical` / `# Non-technical` (0–25) or `Number of questions` (1–25), difficulty (`easy|medium|hard|mixed`), Domains (chips, added by Enter or **Add**), Model (`flash`/`pro`).
  - Validation: total must be **1–25** → inline **"Total questions must be between 1 and 25 (currently N)."** (`:140`).
  - Set picker: select a saved set (required); **+ Create new set** opens the résumé generator. Empty state: "No question sets yet. Click “Create new set” to build one from a sample résumé or manually."
- **Two-way:** panel "No scripted questions to configure" — no source needed (`:629-636`).
- **Multi:** `RoundBuilder` — default rounds **Screening → Technical → Final** (`RoundBuilder.tsx:26-28`). Per round: Round name (required), Mode (Chatbot, Voice, Video Avatar, Timed Q&A, Video Interview — **`two_way` is not offered**), Advance rule (`None` / `Score ≥` / `Top N`) + Value (defaults 60 / 5). Drag to reorder; **Add round**; remove (when >1 round).
- **Next gate:** `rounds.length ≥ 1` and every round has a name + mode (`:443`).

#### Step 3 — Candidates
- **Upload:** drag-drop or click. Accepted: **CSV · Excel · PDF · DOCX · TXT — max 10 MB** (`:750-757`; server limit `invites.ts:29`).
- **Manual add:** "Or type an email: name@company.com" + **Add email**. Duplicate → toast **"That email is already in the list"** (`:291`).
- **Validation:** client regex `^[^\s@]+@[^\s@]+\.[^\s@]{2,}$` (`:16`); invalid rows are flagged `!` and excluded from the valid count.
- **Extraction result:** toast **"Found N email(s)"**; error **"No email addresses found in that file."** (`:277`) or **"Could not read that file."** (`:281`).
- **Extraction warnings** (from the server, `server/services/inviteExtract.ts`):
  - "The spreadsheet had no sheets."
  - "No email/role header row detected — mapped the first email in each row and defaulted roles to the batch role."
  - "Unstructured file — emails were extracted by pattern and roles defaulted to the batch role. Please review carefully."
  - "N duplicate email(s) removed."
  - "No email addresses found in this file."
- **Table actions:** edit email/role inline, **Remove invalid**, **Clear all**, per-row delete.
- **Next gate:** at least one valid email.
- **Server error:** 400 **`No file uploaded`** (`invites.ts:38`).

#### Step 4 — Invite email
Handled by `InviteEmailStep.tsx`. Fields and actions:

| Field / control | Notes | Source |
|---|---|---|
| Saved templates dropdown | "— New (unsaved) —" plus saved templates ("(default)" suffix); **Save** / **Update** / **Duplicate** / **Delete** / **Save as new** | `:168-188` |
| From address | Brevo verified-sender dropdown when `BREVO_API_KEY` is set, else free text; "Use server default (MAIL_FROM)" | `:193-208` |
| From name, Reply-to | text | `:209-212` |
| Subject | supports `{{merge_vars}}` | `:226` |
| Body | TipTap rich-text editor | `:229` |
| Button text, Button colour | colour picker + hex | `:243-244` |
| Company name, Accent colour | | `:247-248` |
| Logo | paste a public direct URL, or **Upload** (hosted in Firebase Storage) | `:250-278` |
| Footer, Deadline text | | `:280-281` |
| **Send test to me** | sends to the recruiter's own address with sample merge values | `:286`, `server/routes/invites.ts:354-393` |

- **Merge variables offered** (`shared/inviteEmail.ts:14-21`): `{{candidate_name}}`, `{{role}}`, `{{recruiter_name}}`, `{{company}}`, `{{interview_link}}` *(locked)*, `{{deadline}}`.
- **Locked token rule:** `{{interview_link}}` **must** appear in subject or body. Warning banner: **"The interview link ({{interview_link}}) is required and can't be removed."** + **Insert link** button (`InviteEmailStep.tsx:231-236`). Next is disabled until satisfied.
- **Always injected server-side and not removable:** the CTA button, the "**Important:** this invitation is linked to \<email\>. Sign in — or create your candidate account — using this exact email address to open it." note, and the "Or paste this link into your browser" fallback (`shared/inviteEmail.ts:136-197`).
- **Test-send outcomes:**
  - sent → toast **"Test sent to \<email\>"**
  - dry-run → toast **"Dry-run: mailer not configured (would send to \<email\>)"**
  - missing token → toast **"Add the {{interview_link}} token before testing"**
  - error → **"Test failed"** or the server message; server 400 **`Your account has no email address to send a test to`** (`invites.ts:358`)
- **Logo upload validation** (`invites.ts:304-326`): 400 **`No image uploaded`**, 400 **`Logo must be an image (PNG, JPG, SVG, …)`**, 400 **`Logo must be under 2 MB`**.

#### Step 5 — Review & send
- **Trigger:** **Send N invite(s)** (`InviteWizard.tsx:880-882`).
- **Guard:** ≥1 valid candidate and a valid locked token; otherwise toast **"The invite email is missing the interview link ({{interview_link}})"** (`:299`, `:326`).
- **Single-interview path** → `POST /api/invites`. Server validation (`server/routes/invites.ts:143-171`):
  - 400 **`A valid interview mode is required`**
  - 400 **`A candidate role is required`**
  - 400 **`source must be "tailor" or "set"`** (not required for `two_way`)
  - 400 **`No valid candidate emails to invite`**
  - 400 **`A question set must be selected`**
  - 404 **`Question set not found`**
  - 400 **`Invite email is missing required token(s): …`**
- **Multi-round path** → `POST /api/pipelines` then `POST /api/pipelines/:id/invite`. Server validation (`server/routes/pipelines.ts:35-65`, `:208-247`):
  - 400 **`Round N: name is required`**
  - 400 **`Round N: mode "<mode>" is not allowed (two_way deferred)`**
  - 400 **`role is required`**
  - 400 **`at least one round is required`**
  - 400 **`no candidates`**
- **Success:** result panel — "N invite(s) created", batch id (first 8 chars), and either "M invitation email(s) sent" or "emails are in dry-run (not sent yet — add the SMTP login + verified sender to send for real)". Toasts: **"Created N invite(s)"** / **"Pipeline created — invited N to Round 1"**.
- **Per-recipient row:** status badge (`delivered` = success, `accepted` = info, failed = danger), **Retry**, copy-link icon; **Copy all links**; **Done**.
- **Retry:** `POST /api/invites/:interviewId/retry` → toast **"Resent to \<email\>"** or **"Retry failed"**; server 404 **`Interview not found`** (`invites.ts:404`, `:406`).

### 4.6 Recruiter — pipelines and the board

| Action | Trigger | Rules / validation | Success | Failure |
|---|---|---|---|---|
| Filter pipelines | `/pipelines` Role / From / To | client-side | filtered grid | empty state "No pipelines match these filters" |
| Open board | click card | — | `/pipelines/:id` | error card "Couldn't load this pipeline" + **Try again** |
| Drag to advance | drag an **advanceable** card | Only valid targets: the **immediate next round**; **Selected** only from the last round; **Not advancing** from anywhere | opens the confirm modal | toast **"Can only advance to the next round"** (`PipelineBoardPage.tsx:487`) |
| Quick advance | column bar: `Score ≥` / `Top N` + value + **Apply** | Null scores are never selected (`pipelines.ts:144-148`) | opens the confirm modal pre-filled | toast **"No candidates in this round meet that criteria"** (`:494`) |
| Advance one | card **Advance →** | requires `advanceable` (round completed **and** scored) | opens confirm modal | — |
| Not advancing | card **Not advancing** | rejection email OFF by default | opens confirm modal | — |
| Move back | card **Move back** | Only while `status === in_round`, `currentRoundIndex > 0`, and the current round is not completed | `confirm("Move this candidate back to the previous round? This deletes their next-round link; the email can't be unsent.")` → toast **"Moved back to the previous round"** | 400 **`Nothing to move back`**, 400 **`Current round already completed; cannot move back`**, 404 **`Candidate not found`** (`pipelines.ts:388-397`) |
| View history | card **History** | read-only audit list | rows like `Advanced Screening → Technical · <timestamp> · <basis> · email accepted` (`PipelineBoardPage.tsx:57-70`) | — |
| Export CSV | Selected column → **Export CSV** | header `Name, Email, Final score`; filename `<role>-selected.csv` | file downloads | toast **"No selected candidates to export yet"** (Autopilot path) |

#### The advance / reject confirm modal (`AdvanceModal.tsx`)
- **Titles:** "Advance N candidate(s) to \<round\>", "Select N candidate(s)", "Move N candidate(s) to Not advancing" (`:28-32`).
- Loads the recruiter's default email template for the kind (`invite | advance | selected | rejection`).
- **Rejection** shows a toggle **"Send a rejection email"** — *off by default*; the confirm button reads **"Move without emailing"** until enabled, then **"Confirm & send"** (`:93-95`).
- Editable Subject + Body (rich text) + live preview rendered with the same renderer the server uses.
- Advance requires `{{interview_link}}`; warning badge: **"Missing required link — insert {{interview_link}} so the candidate can reach their next round"** (`:203-207`).
- **Results panel:** per recipient — **Email sent** / **Moved · email failed** / **Moved**, plus the error text. Explanatory line: "Candidates were moved successfully. Some emails didn't send — the reason is shown per recipient (this is a mail-server/Brevo delivery issue, not the advancement)." (`:146-148`).
- **Toasts:** "Advanced to \<round\>", "Marked as selected", "Moved to Not advancing", or "N of M email(s) failed to send" (`:120-125`).

#### Server-side advancement rules (`server/routes/pipelines.ts:151-156`)
- 400 **`Candidate is not in an active round`**
- 400 **`Candidate has not completed and been scored in the current round`**
- 400 **`Can only advance to the next round`**
- 400 **`Target round out of range`**
- 400 **`candidateIds and targetRoundIndex required`** / **`candidateIds required`**
- Each candidate is processed independently; a per-candidate failure becomes a row in `results`, never an aborted batch (`:269-328`).
- `targetRoundIndex >= rounds.length` ⇒ terminal **`selected`** status (email only, no new interview doc).

### 4.7 Recruiter — reports

| Action | Trigger | Behaviour | Source |
|---|---|---|---|
| Open report | Sessions **View report →**, Analytics **Top Candidates** | polls every 2.5 s while `report` is null; shows "Scoring in progress… This updates automatically when the analysis is ready." | `ReportPage.tsx:132-140`, `:193-201` |
| Export PDF | **Export PDF** | filename `TalbotIQ-<Candidate-Name>-report.pdf` | `ReportPage.tsx:169-179` |
| Expand a question | accordion row | shows answer/transcript, video player, per-KPI chips, Feedback | `ReportPage.tsx:325-377` |
| Save interviewer review (two-way only) | 0–5 stars + notes → **Save review** | rating clamped 0–5; notes truncated to 4000 chars server-side | `ReportPage.tsx:44-105`, `server/routes/sessions.ts:673-692` |
| Play call recording | video element | two-way only, when `recordingUrl` exists | `ReportPage.tsx:387-396` |

**Report banners and empty states (exact copy):**
- Not evaluated — "**Not evaluated.** No candidate answers were captured for this interview, so there are no real scores — the values below are placeholders, not a judgment of the candidate. The interview may need to be retaken." (`ReportPage.tsx:211-220`)
- Degraded — "Heuristic scoring (no `GEMINI_API_KEY`). Add a key for content-aware analysis." (`:221-226`)
- Load failure — "Couldn't load this report" + reason + **Try again** / "Back to sessions" (`:147-164`)
- No questions — "No questions were recorded for this interview." (`:378-382`)
- No transcript — "No transcript was captured for this interview." (`:409-412`)
- Signal analytics unavailable — "Delivery metrics and sentiment are available for voice and conversational interviews with a transcript. This interview type doesn't produce one." (`:491-498`)
- No sentiment — "Sentiment analysis needs a Gemini API key. Add one in Settings to enable it." (`:555-558`)
- PDF failure — toast **"PDF export failed"** (`:175`)
- Review save failure — toast **"Could not save the review"** (`:68`)

**Server report errors:** 404 `Session not found` (non-owner), 404 `Template for session not found` (`server/routes/sessions.ts:95-102`, `:1045-1047`).

### 4.8 Recruiter — analytics

- **Filters** (`AnalyticsPage.tsx:178-200`): Track (All tracks + 6 tracks), Template (All templates + names), Role (All roles + template roles), From (date), To (date), **Clear**.
- **Gating rule:** Average Score, Score Distribution, KPI Averages and Top Candidates only render once a **Role or Template** is selected — "These are only meaningful within a single position." (`:246-257`).
- **Empty states:** "No scored interviews yet" / "No scored interviews match these filters"; error state "Couldn't load analytics — The analytics service returned an error. Try again in a moment." (`:217-232`).
- **Score buckets:** `0-20`, `21-40`, `41-60`, `61-80`, `81-100` (`server/services/analytics.ts:24-31`).
- **Recommendation labels:** Strong Yes, Yes, Maybe, No, Unscored (`AnalyticsPage.tsx:19-21`).
- **Footnote:** "Aggregated \<timestamp\> · scored interviews only" (`:429`).

### 4.9 Recruiter — Avatar studio (`/setup`)

| Action | Trigger | Validation | Success | Failure |
|---|---|---|---|---|
| Apply to candidate interviews | **Apply to Candidate Interviews** | replica required; a Tavus key must exist locally or server-side | toast **"Applied — every Conversational AI candidate interview now uses this avatar."**; returns to `returnTo` if present | toast **"Pick a replica — candidates need a live avatar."**, **"Add your Tavus API key in Settings first."**, **"Could not apply the avatar settings"**; server 400 **`A replica is required — pick one on the Setup page before applying.`** (`server/routes/settings.ts:27`) |
| Launch test session | **Launch Test Session** → modal → **Launch Interview** | Candidate Name required | toast **"Session created!"** → `/interview` | toast **"Enter a display name"**; Tavus error modal with the raw message + credit guidance + **Continue in Demo Mode (no avatar)** / **Try Again** / **Dismiss** |
| Demo mode | no replica selected, or the error modal's demo button | — | toast **"Running in Demo Mode — no avatar video"** → `/interview` | — |
| Save draft | **Save Draft** → modal | Draft Name required | toast **"Draft "\<name\>" saved"** | toast **"Enter a draft name"** |
| Load / delete draft | click a saved draft card / its × | — | toast **"Loaded "\<name\>""** / **"Draft deleted"** | — |

**Status line under the buttons:** "✓ An avatar is applied to candidate interviews · replica \<id\> · updated \<relative time\>", or "No avatar applied yet — candidate Conversational AI interviews won't start until you apply one." (`SetupPage.tsx:250-260`).

**Questions are NOT configured here** — the page states: "Interview questions are set when you invite candidates … chosen in Sessions → Invite candidates." (`SetupPage.tsx:360-370`).

### 4.10 Recruiter — replicas & personas

| Action | Trigger | Result | Source |
|---|---|---|---|
| Rename replica | details modal → **Save Changes** | toast **"Replica renamed"** | `ReplicasPage.tsx:111` |
| Delete replica | card → **Delete** | `confirm("Delete "<name>"?")` → toast **"Replica deleted"** | `:45` |
| New replica | **+ New Replica** | informational toast: "Create replicas at platform.tavus.io → Replicas → Create. They appear here automatically once training completes (~15 min)." | `:67` |
| Empty state | no replicas | "No replicas yet … Training takes approximately 15 minutes." + **Open Tavus Dashboard ↗** | `:78-87` |
| Create/edit persona | **+ New Persona** / **Edit** → **Create Persona** / **Save Changes** | toast **"Persona created"** / **"Persona updated"** | `PersonasPage.tsx:54` |
| Delete persona | **Delete** | toast **"Deleted"** | `:92` |

### 4.11 Recruiter — settings

| Action | Trigger | Validation | Success | Failure |
|---|---|---|---|---|
| Test Tavus connection | **Test Tavus Connection** | key must be present | toast **"Connected — N replica(s) found"**; badge "Connected" | toast **"Enter your Tavus API key first"** / **"Connection failed"**; badge "✕ Failed" |
| Save settings | **Save Settings** | — | toast **"Settings saved — Tavus key applied everywhere"** | toast **"Saved locally, but the server sync failed: \<msg\>"** |
| Reset to defaults | **Reset to Defaults** | `confirm("Reset Tavus key and local preferences?")` | clears `localStorage['talbotiq-store']` and reloads | — |
| Save Gemini key | GeminiKeyCard → **Save key** | non-empty | toast **"Gemini key saved"** | toast **"Enter a Gemini API key"** / **"Save failed"** |
| Remove Gemini key | **Remove** (only when `source === 'saved'`) | — | toast **"Saved Gemini key removed"** | toast **"Failed"** |

Gemini status line: "Set (\<source\>) · \<masked\> · \<model\>" or "Not configured — using heuristic fallback" (`GeminiKeyCard.tsx:60-66`).

### 4.12 Recruiter — live two-way interview (`/live/:id`)

| Action | Trigger | Behaviour | Source |
|---|---|---|---|
| Join as host | opening `/live/:id` | `POST /sessions/:id/twoway/host` → Daily room `room-{sessionId}` + owner token | `LiveInterviewPage.tsx:55-74` |
| Admit candidate | **Admit \<name\>** | admits the knocking participant | `:213-221` |
| Record | record button | pauses/resumes ONE continuous recorder | `:79-88` |
| End interview | **End interview** | `confirm("End the interview now? The recording will be uploaded and the session will be marked complete.")` → upload → complete → `/sessions/:id/report` | `:126-130` |
| Mic / camera | circular buttons | toggle | `:255-289` |

**Screens/messages:** "Starting the interview room…", "We couldn't start the interview room" + **Try again**, "The interview has ended — finalizing…" + **Go to report**, "Waiting for the candidate to join…", "The candidate is waiting — admit them above.", overlay "Uploading recording…" / "Finalizing…" (`:151-296`).
**Toasts:** "Could not upload the recording — finishing without it", "Could not finalize the session — check Sessions and try again" (`:111`, `:119`).

**Server errors:**
- 409 **`The candidate must open their interview link before you can join.`** (`server/routes/sessions.ts:533`)
- 400 **`Not a two-way interview`** (`:543`)
- 409 **`This interview has already ended`** (`:545`)
- 503 **`The two-way interview is not configured — set DAILY_API_KEY on the server.`** (`server/services/dailyServer.ts:19`)
- 502 **`Daily error (HTTP <status>)`** (`dailyServer.ts:29`, `:52`)

### 4.13 Candidate — the interview flow

#### 4.13.1 Opening the link
- **Trigger:** `/take/:sessionId` from the invite email or `/candidate`.
- **Behaviour:** `GET /sessions/:id/state`; on 404 it attempts `POST /sessions/:id/claim` to materialise a bulk invite (`useInterviewClock.ts:35-59`).
- **Failure screens** (`TakeInterviewPage.tsx:45-68`):
  - "Signed in with a different account" (when the error mentions a different email) + **Sign out & switch account**
  - "Interview not found … Please double-check your invite link."
- **Server claim errors** (`server/services/inviteBridge.ts:98-127`):
  - 404 **`Interview not found`**
  - 403 **`This invitation was sent to a different email address. You are signed in as <email> — sign out, then sign in (or create your candidate account) with the email address that received the invitation.`**
  - 409 **`This interview has already been completed`**

#### 4.13.2 Choose format
- **Trigger:** track-select screen (skipped when the track is fixed by the invite — `chatbot`, `video_avatar`, `voice`, `two_way`, `video`).
- **Options:** Chat Interview, Voice Interview (New), Video Avatar (Preview). Copy: "Both formats ask the same questions and are timed identically."
- **Server validation** (`server/routes/sessions.ts:200-210`): 409 **`Track can only be chosen before the interview begins`**; 400 **`Invalid track`**.

#### 4.13.3 Résumé + name intake
- **Inputs:** Full name — **≥ 2 characters** (`ResumeUpload.tsx:23`; hint "Enter your full name above to continue."); résumé file — `.pdf`, `.docx`, `.txt`, **max 8 MB** (`ResumeUpload.tsx:72-84`; server limit `sessions.ts:40`).
- **Busy state:** "Preparing your questions…"
- **Server failures** (`server/routes/sessions.ts:225-272`, `server/services/resume.ts:28`):
  - 400 **`This interview does not use résumé-based questions`**
  - 409 **`The interview has already started`**
  - 400 **`No résumé file uploaded`**
  - 400 **`Could not read meaningful text from that file`**
  - 400 **`Unsupported file type — upload a PDF, DOCX, or TXT résumé.`**
- Full name is stored (truncated to 80 chars) as `session.candidate.name` and used by the AI interviewer.
- Résumé text is truncated to 20 000 characters.

#### 4.13.4 System check / consent
- Generic: three checks (internet, quiet space, ready to focus) + required checkbox "I understand the rules and I'm ready to begin." → **I'm ready, begin**.
- Video track: consent checkbox "I understand my responses are recorded and analysed by AI, and reviewed by a human recruiter." → **I consent — begin**.
- Avatar/two-way: **Enable camera & microphone**; denial message "Permission was blocked. Enable camera & mic access in your browser, then retry."; success chips "Camera ready" / "Mic ready".

#### 4.13.5 Timed question loop (`chat`, `video`)
- **Phases:** prep (default 30 s) → answer (default 120 s) → auto-submit → next question (`server/services/timing.ts:42-101`).
- **Controls:** **Start answering now** (only if `allowSkipPrep`), **Submit & continue** (only if `allowEarlySubmit`).
- **UI copy:** "Preparation" / "Answering"; STAR tip "Tip: structure your answer with **STAR** — Situation, Task, Action, Result."; warning "\<n\>s left — your answer will auto-submit at zero."; footer "You can't return to this question once you continue."; word counter.
- **Drafts:** auto-saved (debounced ~900 ms) and flushed on unmount (`QuestionStage.tsx:38-43`).
- **Server failures:**
  - 403 **`Skipping preparation is disabled`** (`sessions.ts:722`)
  - 409 **`Not in a preparation phase`** (`:725`)
  - 409 **`Stale question — refresh state`** (draft) (`:737`)
  - 409 **`No active question`** (`:750`)
  - 409 **`Not the current question`** (`:752`)
  - 400 **`Cannot submit during preparation`** (`:754`)
  - 403 **`Early submission is disabled`** (`:759`)
  - 409 **`Interview already finished`** (`:700`)
  - 400 **`A résumé is required before starting`** / **`No questions could be generated`** (`:707`)

#### 4.13.6 Chatbot (conversational) track
- **Opening turn** is a greeting that ends by asking readiness — *not* a question (`server/services/conversation.ts:211-216`, `:434-452`).
- **Readiness composer** is a dropdown: "Yes, I'm ready" / "No, not yet" (`ChatbotStage.tsx:266-290`).
- Choosing "No" offers a timed break: **30 seconds / 45 seconds / 1 minute**, or "Actually, I'm ready now"; auto-starts at 0 (`:230-265`).
- **Thinking indicator** shown while the interviewer generates; ≥3 s minimum enforced by the session hook (`:15-43`).
- **Timer ring** appears only on timed question/follow-up turns — never during greeting, readiness, the Thinking pause, or wrap-up (`:166-177`).
- **Prep sub-timer banner:** "Preparation time — read the question and structure your answer (Situation, Task, Action, Result)." + **Start answering now** (`:220-228`).
- **Composer placeholders:** "Your interviewer is thinking…", "Answering unlocks when preparation ends…", "Type your answer…  (Enter to send · Shift+Enter for a new line)".
- **Auto-submit at 0** sends whatever is typed and advances (`:100-111`).
- **Completion:** "All done, thank you! — Your responses were submitted to \<company\>. You can close this window; the hiring team will be in touch."
- **Server failures** (`server/routes/sessions.ts:880-963`):
  - 400 **`Not a conversational session`**
  - 409 **`Interview already finished`**
  - 400 **`A résumé is required before starting`**
  - 409 **`Interview is not in progress`**
  - 409 **`No question is awaiting an answer`**
  - 409 **`Stale turn — refresh`**
  - 400 **`Still in thinking time`**
  - 403 **`Early submission is disabled`**
  - 409 **`Cannot skip thinking right now`**

#### 4.13.7 Voice track
- **Start gate:** "Voice interview with \<company\> — You'll have a spoken conversation with \<persona\>. Find a quiet spot — when you're ready, we'll ask for your microphone and begin." → **Start voice interview** (`VoiceStage.tsx:59-81`).
- **Phase labels** (`VoiceStage.tsx:13-21`): Connecting…, Interviewer is speaking, Listening…, One moment…, Interview complete, Something went wrong.
- **Controls:** mute/unmute, **End interview**, captions toggle ("Captions will appear here as you talk.").
- **Reconnect banner:** "Reconnecting…" + "Connection hiccup — your interview is saved and will resume in a moment."
- **End states:** graceful → "All done, thank you!"; non-graceful → "Interview interrupted — The connection dropped before the interview finished, so it ended early. Please reach out to the \<company\> hiring team and we'll help you complete it."
- **Errors:** "Microphone blocked" (with "Allow microphone access in your browser's address bar, then reload this page.") or "Connection problem"; messages **"Microphone access is required for a voice interview."** / **"Could not start the microphone."** (`useVoiceSession.ts:61-66`).

#### 4.13.8 Video Avatar track
- Face-framing pre-flight runs on first entry; a refresh mid-call skips it (`TakeInterviewPage.tsx:85-98`).
- **Server failures** (`server/routes/sessions.ts:316-343`, `server/services/tavusServer.ts:128-142`):
  - 400 **`This interview does not use the video avatar`**
  - 409 **`The interview has already finished`**
  - 400 **`A résumé is required before starting`**
  - 400 **`No questions are configured for this interview`**
  - 503 **`The video avatar is not configured yet — the recruiter must apply avatar settings on the Setup page.`**
  - 502 **`Tavus returned no conversation URL`**
- **Transcript recovery:** if the live capture bridge produced no candidate answers, the server pulls the authoritative transcript from Tavus (5 attempts, 6 s apart) before scoring (`sessions.ts:448-480`).

#### 4.13.9 Video Interview track
- 30 s prep with live camera preview → answer phase starts live Deepgram transcription off the shared stream → the transcript **is** the answer (no video upload for the answer itself) (`VideoStage.tsx:21-28`).
- Client pre-emptively submits ~3 s before the server deadline (`:85-88`).
- **Copy:** "Recording answer" / "Preparation"; overlay "Read the question and get ready. Answer aloud — the timer starts your response."; "Saving your answer…"; badges "Rec" / "Preview" / "Starting camera…"; warning "\<n\>s left — your answer submits automatically."
- **Failure banner:** "Your answer may not have been submitted. If the interview advanced, that question could be missing its transcript." (`:142-146`).
- **Facial capture:** per-frame Rekognition through `POST /sessions/:id/facial-frame`; aggregate summary uploaded on the last question via `POST /sessions/:id/facial` (`sessions.ts:791-820`).
  - 400 **`This interview does not capture facial analysis`**
  - `{ success:false, reason:'frame_too_small' }` for frames under ~5 KB

#### 4.13.10 Two-way track (candidate side)
- **Lobby copy** (`TwoWayStage.tsx:236-248`): "Waiting for the interviewer to start the interview…", "Waiting for the interviewer to admit you…", "Reconnecting…", "Your camera and mic are ready — you'll be connected the moment the interviewer lets you in.", "We briefly lost the connection to the interview server — reconnecting automatically. No need to do anything."
- **Retry policy:** waiting-for-host retries indefinitely every 4 s; transient backend failures retry at most 10 times (~40 s) before showing a hard error (`:16-22`, `:112-125`).
- **End:** `confirm("End the interview now? You can't rejoin afterwards.")`.
- **Error screens:** "We couldn't join your interview" + **Try again** + "If this keeps happening, contact your recruiter."; "Connection problem" + **Try again**.
- **Server:** 409 **`The interviewer has not started this interview yet.`** (`sessions.ts:567`).

#### 4.13.11 Integrity monitoring (all tracks)
- Warnings are toasts with a ⚠️ icon and a counter (`useIntegrityMonitor.ts:19-34`):
  - Tab/window switch → **"Please stay on this tab — switching away is recorded (n/max)"**
  - Fullscreen exit → **"Please return to fullscreen for the interview (n/max)"**
- Paste/copy in the answer box are blocked and logged when configured (`QuestionStage.tsx:99-100`, `ChatbotStage.tsx:297-298`).
- Event types recorded: `tab_switch`, `window_blur`, `paste_blocked`, `copy_blocked`, `fullscreen_exit` (`shared/types.ts:415-424`).
- Server counts `tab_switch` + `window_blur` toward `tabSwitchCount` (`sessions.ts:823-835`); when `logEvents` is off it returns `{ ok:true, ignored:true }`.

### 4.14 Mimic Guide (both roles)

| Action | Trigger | Behaviour / validation | Source |
|---|---|---|---|
| Ask a question | type + Enter/Send | `POST /api/help/chat`; body validated: 1–20 messages, each 1–8000 chars | `server/routes/help.ts:23-47` |
| Any error | — | Always returns **200** with reply **"Something went wrong. Please try again."** so the chat stays usable | `help.ts:35`, `:45` |
| Out-of-scope question | — | Exact refusal: **"I'm here to help with the TalbotIQ AI Interview Platform only. Try asking about interviews, templates, question sets, sessions, AI Avatar Screening, or results!"** | `server/services/mimicGuidePrompt.ts:12-13` |
| Multilingual answer | user writes in another language | Answers in that language **and** appends the full English version in a `<details><summary>English</summary>` block | `mimicGuidePrompt.ts:27-32` |
| Listen to an answer | per-message **Listen** | Browser TTS when a voice exists for the language, else server Gemini Live synthesis via `POST /api/help/tts` | `.env.example:10-16`, `server/routes/help.ts:96-123` |
| TTS failure | — | 400 `Invalid TTS request`; 503 **`Voice output needs a Gemini API key (see Settings)`**; 400 `Nothing to speak`; 502 **`Voice synthesis failed — try again`**; client toast **"Couldn't play the voice for this language right now — please try again."** | `server/services/mimicGuideTts.ts:89-115`, `MimicGuide.tsx:95` |
| Voice input | mic button | Web Speech API; hands-free "Voice mode" auto-submits after a pause and can answer a confirm with "yes"/"no" | `MimicGuide.tsx:261-284` |
| Autopilot | **Autopilot** toggle | The agent may run ONE registered action per turn; **side-effect actions require an explicit read-back Confirm** | `src/features/guide/autopilot/executor.ts:16-24` |
| Autopilot refusal | unknown action / bad args | `Unknown action "<name>"` or the joined validation errors (`Missing required "<param>"`, `"<param>" must be text/a number`, `"<param>" must be one of: …`) | `executor.ts:19-21`, `shared/autopilot.ts:44-79` |
| No/invalid Gemini key (chat) | — | "I can't reach the AI model right now — the Gemini API key looks invalid, expired, or missing. …" | `server/services/mimicGuide.ts:135` |
| No/invalid Gemini key (Autopilot) | — | "I can't reach the AI model — the Gemini API key looks invalid, expired, or missing. Add a valid Gemini API key in Settings → Gemini, or set GEMINI_API_KEY on the server, then try again." | `server/services/autopilotAgent.ts:90` |
| Autopilot agent error | — | Always 200 with `{ say: 'Something went wrong. Please try again.', awaitingUser: true }` | `server/routes/help.ts:80-83` |

**Registered Autopilot actions** (all RBAC-gated client- and server-side):

| Screen | Action | Side-effect? | Source |
|---|---|---|---|
| `global` | `navigate(path)` | no | `MimicGuide.tsx:290-306` |
| `setup` (invite wizard) | `setInterviewType`, `selectMode`, `setRole`, `setQuestionSource`, `selectQuestionSet`, `addCandidate`, `nextStep`, `backStep`, `createInvites` | only `createInvites` | `InviteWizard.tsx:400-411` |
| `analytics` | `filterByTrack`, `filterByRole`, `filterByTemplate`, `setDateRange`, `clearFilters`, `openCandidateReport` | none | `AnalyticsPage.tsx:71-144` |
| `pipelines` | `openByRole`, `filterByRole`, `setDateRange`, `clearFilters` | none | `PipelinesPage.tsx:31-71` |
| `pipeline` (board) | `advanceByScore`, `advanceTopN`, `advanceCandidate`, `notAdvancing`, `moveBack`, `exportSelected` | all except `exportSelected` | `PipelineBoardPage.tsx:302-387` |

### 4.15 Marketing — book a demo

- **Trigger:** `/mimic#demo` form → **Book a demo** (`MimicSite.tsx:359-368`).
- **Inputs & client validation:** First name, Last name, Work email (regex `^[^@\s]+@[^@\s]+\.[^@\s]+$`), Hires per year — all required.
- **Inline errors:** "Enter your first name.", "Enter your last name.", "Enter a valid work email.", "Roughly how many people do you hire a year?"
- **Success:** panel "Thanks — you're on the list. We'll be in touch within one business day to set up your walkthrough."
- **Failure:** "Something went wrong sending that. Please try again, or email sales@talbotiq.com."
- **Server validation** (`server/routes/leads.ts:14-50`): firstName/lastName 1–120 chars, email valid ≤200, hiresPerYear 1–120, optional source ≤120 (default `mimic-site`). Rejection message: **"Please fill in your name, a valid work email, and hires per year."** Stored server-side only (never Firestore).

### 4.16 Complete API surface (for the manual's reference appendix)

**Public**
| Method | Path | Notes |
|---|---|---|
| GET | `/api/health` | `{ ok, ts, gemini, auth, authMode }` (`server/index.ts:38-46`) |
| POST | `/api/leads` | marketing demo request |
| POST | `/api/invites/brevo-webhook` | shared-secret `?token=` or `x-webhook-token`; 401 `Invalid webhook token` (`brevoWebhook.ts:59-65`) |

**Authenticated (any role)**
`GET /api/auth/me` · `POST /api/help/chat` · `POST /api/help/agent` · `POST /api/help/tts`

**Sessions** (`/api/sessions`, authenticated; per-handler authorization)
`POST /` (recruiter) · `POST /:id/claim` · `GET /:id/state` · `POST /:id/track` · `POST /:id/system-check` · `POST /:id/resume` · `POST /:id/avatar/start` · `POST /:id/avatar/transcript` · `POST /:id/avatar/complete` · `POST /:id/twoway/host` (recruiter) · `POST /:id/twoway/join` · `POST /:id/twoway/complete` · `POST /:id/twoway/review` (recruiter) · `POST /:id/begin` · `POST /:id/skip-prep` · `POST /:id/draft` · `POST /:id/answers` · `POST /:id/facial-frame` · `POST /:id/facial` · `POST /:id/integrity-event` · `POST /:id/complete` · `POST /:id/chat/begin` · `GET /:id/chat/state` · `POST /:id/chat/answer` · `POST /:id/chat/draft` · `POST /:id/chat/question-presented` · `POST /:id/chat/skip-thinking` · `GET /` (recruiter) · `GET /mine` (candidate) · `GET /:id/report` (owner)

**Recruiter-only**
- `/api/templates` — `GET`, `GET /:id`, `POST`, `PUT /:id`, `DELETE /:id`
- `/api/question-sets` — `GET`, `GET /:id`, `POST /generate`, `POST`, `PUT /:id`, `POST /:id/duplicate`, `DELETE /:id`
- `/api/settings` — `GET`, `GET /avatar`, `PUT /avatar`, `DELETE /avatar`, `PUT /tavus-key`, `DELETE /tavus-key`, `PUT /gemini-key`, `DELETE /gemini-key`
- `/api/voices` — `GET`, `POST /:id/sample`
- `/api/analytics` — `GET` (query: `track`, `templateId`, `role`, `dateFrom`, `dateTo`)
- `/api/invites` — `POST /extract`, `POST /`, `POST /logo`, `GET /senders`, `POST /test`, `POST /:interviewId/retry`
- `/api/invite-email-templates` — `GET` (`?kind=`), `GET /:id`, `POST`, `PUT /:id`, `POST /:id/duplicate`, `DELETE /:id`
- `/api/pipelines` — `GET` (`?role=`), `GET /:id`, `GET /:id/board`, `POST`, `PUT /:id`, `DELETE /:id`, `POST /:id/invite`, `POST /:id/advance`, `POST /:id/not-advancing`, `POST /:id/move-back`
- `/api/avatar` — `GET /status`, `POST /deepgram/token`, `POST /hume/jobs`, `GET /hume/jobs/:id`, `GET /hume/jobs/:id/predictions`, `POST /gemini-generate`, `POST /analyze-face`
- `/api/avatar/face-cache` — `GET` (accepts `?token=` because `<video>` cannot send headers)

**WebSockets** (`server/index.ts:108-116`)
- `/api/voice/:sessionId` — Voice track relay to Gemini Live
- `/api/avatar/deepgram` — recruiter avatar-screening live transcription
- `/api/interview/deepgram` — candidate Video Interview live transcription

All WS handshakes authenticate via `?token=` / `?access_token=` (`server/middleware/auth.ts:37-52`).

---

## 5. Settings and configuration

### 5.1 Interview template — full field reference

Source of truth: `shared/types.ts:368-389`; defaults `server/store/defaults.ts`; UI `TemplateEditorPage.tsx`.

#### Basics
| Field | Default | Allowed values |
|---|---|---|
| Template name | `Untitled template` (API) / `New template` (UI) | free text |
| Role | `''` / `Software Engineer` (UI create) | free text |
| Seniority | — | free text (placeholder "e.g. Mid, Senior") |
| Track | `chat` | `chat`, `chatbot`, `voice`, `video_avatar` *(the editor's Track dropdown offers only these four)* |

#### Questions
| Field | Default | Allowed values |
|---|---|---|
| Question source | `fixed` | `fixed` (saved set) / `adaptive` (Gemini from résumé) |
| Question set | — | any saved set; warning "⚠ No question set selected — sessions can't start." |
| Number of questions (non-conversational adaptive) | 5 | integer |

#### Conversation (chatbot / voice / video_avatar)
| Field | Default | Allowed values |
|---|---|---|
| Mode | `conversational` | `conversational` / `timed` (hidden for voice) |
| Question style | `mix` | `technical`, `non_technical`, `mix` |
| Difficulty | `mixed` | `easy`, `medium`, `hard`, `mixed` |
| # Technical / # Non-technical | 3 / 2 | integers; sum sets `numberOfQuestions` |
| Number of questions | 5 | integer |
| Focus topics | `[]` | comma-separated list |
| Interviewer tone | `friendly and professional` | free text |
| Language | `English` | free text |
| Allow follow-up questions | **off** | boolean |
| Max follow-ups per question | 1 | integer |
| Allow follow-ups on the fixed set | off | boolean |
| Timed mode: Thinking (s) | 30 | integer |
| Timed mode: Answer (s) | 120 | integer |
| Timed mode: Warning at (s) | 15 | integer |
| Timed mode: Allow skipping thinking | true | boolean |
| Timed mode: Allow early submit | true | boolean |

#### Voice & persona (voice track only)
| Field | Default | Allowed values |
|---|---|---|
| Engine | `gemini_live` | `gemini_live` / `pipeline` ("coming soon" — typed flag only) |
| Persona | `friendly_hr` | `friendly_hr`, `rigorous_tech`, `warm_behavioral`, `exec_panel` (`defaults.ts:96-129`) |
| Voice | `Aoede` | 16 voices — female: Aoede, Kore, Leda, Zephyr, Callirrhoe, Erinome, Despina, Laomedeia; male: Charon, Orus, Puck, Fenrir, Iapetus, Umbriel, Enceladus, Algieba (`defaults.ts:76-93`) |
| Allow barge-in | true | boolean |
| Language | `en-US` | free text |
| Model | `GEMINI_LIVE_MODEL` env or `gemini-3.1-flash-live-preview` | string |

Voice preview: ▶ button per voice → `POST /api/voices/:id/sample`. Errors: 404 `Unknown voice`, 400 **`A Gemini API key is required to preview voices`**, 502 **`Voice preview failed — try again`** (`server/routes/voices.ts:21-66`).

#### Per-question timer (conversational, not voice) — `ChatbotTimerConfig`
| Field | Default | Notes |
|---|---|---|
| Enable a per-question countdown | **true** for new chatbot/video_avatar templates | product decision 2026-07 (`defaults.ts:31-44`) |
| Answer time per question (s) | 120 | |
| Warning at (s) | 15 | |
| Allow early submit | true | |
| Auto-submit at 0 | true | |
| Time follow-up questions too | true | |
| Follow-up time (s) | 90 | blank = same as questions |
| Add a short prep sub-timer | false | |
| Prep time (s) | 20 | only when the sub-timer is on |
| Per-question overrides | — | fixed sets only; keyed by question id; blank clears |

The clock runs **only while answering** — never during the greeting, "are you ready?", the Thinking pause, or wrap-up (`TemplateEditorPage.tsx:366`).

#### Timing (chat track) — `TimingConfig`
| Field | Default | Source |
|---|---|---|
| Prep (s) | 30 | `defaults.ts:14-20` |
| Answer (s) | 120 | |
| Warning at (s) | 15 | |
| Allow skipping preparation | true | |
| Allow early submit | true | |
| Overall time cap (s) | none | optional |

#### Scoring rubric — `KpiRubric`
Scale is fixed at **100** (`shared/types.ts:61-64`). Default KPIs, all enabled, weight 1 (`defaults.ts:160-172`):

| id | Label | Description |
|---|---|---|
| `communication` | Communication Clarity | Clear, articulate, easy to follow. |
| `relevance` | Relevance to Question | Directly answers what was asked. |
| `depth` | Technical / Domain Depth | Demonstrates real expertise and substance. |
| `structure` | Structure & Conciseness | Well-organized (e.g. STAR); concise, no rambling. |
| `problem_solving` | Problem-Solving | Logical reasoning and a sound approach to problems. |
| `professionalism` | Professionalism / Confidence | Composed, confident, professional tone. |

Editable: toggle on/off, relabel, edit description, set weight (weights auto-normalise to a % shown live), **Add custom KPI**, remove.

#### Branding — `BrandingConfig`
| Field | Default |
|---|---|
| Company name | `TalbotIQ` |
| Accent colour | `#0d5c3a` |
| Logo URL | — |
| Welcome message | "Welcome to your interview. Find a quiet spot, take a breath, and answer naturally — there are no trick questions." (`defaults.ts:149-154`) |

#### Integrity — `IntegrityConfig` (`defaults.ts:140-147`)
| Field | Default |
|---|---|
| Enforce fullscreen | false |
| Detect tab switching | true |
| Disable paste in answers | true |
| Disable copy | false |
| Max tab-switch warnings | 3 |
| Log integrity events | true |

### 5.2 Invite-email template (`InviteEmailTemplate`)

Kinds: `invite` (default), `advance`, `selected`, `rejection` (`shared/types.ts:86`).

Default seeds (`shared/inviteEmail.ts:258-320`):

| Kind | Default name | Default subject | Required token |
|---|---|---|---|
| invite | Default invite | `Interview invitation — {{role}}` | `{{interview_link}}` |
| advance | Default advance | `You've advanced — {{role}} ({{round_name}})` | `{{interview_link}}` |
| selected | Default selection | `You've been selected — {{role}}` | none |
| rejection | Default rejection | `Update on your {{role}} application` | none |

Common defaults: sender `{ verifiedSenderEmail:'', fromName:'TalbotIQ', replyTo:'' }`; CTA `{ text:'Start your interview', color:'#0d5c3a' }`; branding `{ companyName:'TalbotIQ', accentColor:'#0d5c3a', footer:'Sent via TalbotIQ.' }`.

Merge variables by kind (`shared/inviteEmail.ts:77-109`):
- invite: `candidate_name`, `role`, `recruiter_name`, `company`, `interview_link`, `deadline`
- advance: + `round_name`, `previous_round_name`, `score`
- selected: `candidate_name`, `role`, `recruiter_name`, `company`, `score`
- rejection: `candidate_name`, `role`, `recruiter_name`, `company`

Colours must match `^#[0-9a-f]{3,8}$` or fall back to `#0d5c3a` (`shared/inviteEmail.ts:116`, `:130-134`).

The first time a recruiter lists templates of a kind with none saved, a default is **auto-seeded** (`server/routes/inviteEmailTemplates.ts:85-91`).

### 5.3 Video-avatar settings (`AvatarInterviewSettings`)

Saved server-side by "Apply to Candidate Interviews" (`shared/types.ts:746-758`, `server/routes/settings.ts:24-51`).

| Field | Default / constraint |
|---|---|
| `replicaId` | **required** |
| `personaId` | optional |
| `aiName` | default "Alex"; truncated to 60 chars |
| `conversationName` | truncated to 120 chars |
| `conversationalContext` | optional |
| `customGreeting` | optional |
| `language` | full language name (Tavus format), default English |
| `maxCallDuration` | seconds; accepted only if ≥ 60, clamped to ≤ 7200; default 1800 |
| `enableRecording` | boolean |
| `callbackUrl` | optional |
| `fallbackQuestions` | max 30 strings |
| Tavus key | kept from the previous save when not supplied |

Status responses are always masked — the key is never returned (`shared/types.ts:760-768`).

### 5.4 Setup-page (Tavus conversation) form defaults

`SetupPage.tsx:36-42`: `max_call_duration` 900 s, `participant_left_timeout` 60 s, `participant_absent_timeout` 300 s, `enable_recording` false, `enable_transcription` true, `apply_conversation_override` false, `apply_greenscreen` false, `language` English, `pipeline_mode` `full`.

- Languages offered: English, Spanish, French, German, Italian, Portuguese, Japanese, Korean, Chinese, Hindi, Arabic (`SetupPage.tsx:17-29`).
- Pipeline modes: `full` (audio + video), `echo` (test mode), `no_audio`, `video_only` (`:30-33`).
- Max Call Duration slider: 60–7200 s, step 60.

### 5.5 Persona layers (Tavus)

`PersonasPage.tsx:18-23` defaults: LLM `gpt-4o`, max_tokens 1024, temperature 0.7; TTS engine `tavus`, speed 1.0, emotion `['positivity']`; STT engine `tavus`, pause sensitivity 0.5, smart turn detection on; perception queries `[]`; VQA camera off.

Allowed values: LLM `gpt-4o | gpt-4o-mini | claude-3-5-sonnet | gemini-1.5-pro | custom`; TTS `tavus | cartesia | eleven_labs`; STT `tavus | deepgram | custom`; emotions `anger, positivity, surprise, sadness, curiosity`. Temperature 0–2 step 0.05; speed 0.5–2×; pause sensitivity 0–1; max_tokens 1–4096; system prompt char limit 4096.

### 5.6 Platform toggles (Settings page)

`SettingsPage.tsx:178-180` — **White-label Mode**, **GDPR Auto-Purge** (default on), **Multi-language Avatar**. See [Open Questions](#open-questions) regarding persistence.

### 5.7 Environment variables

Full list from `talbotiq-platform/.env.example` and `docs/DEPLOY-VERCEL-RENDER.md:58-107`.

**Server-only**
| Var | Default | Purpose / effect when absent |
|---|---|---|
| `GEMINI_API_KEY` | — | Question generation, scoring, Voice Live, Mimic Guide. Blank ⇒ heuristic fallback; voice disabled |
| `GEMINI_MODEL` | `gemini-2.5-flash` | Text/scoring model |
| `GEMINI_LIVE_MODEL` | `gemini-3.1-flash-live-preview` | Voice-track native-audio model |
| `PORT` | 8787 | API port |
| `SMTP_HOST` | `smtp-relay.brevo.com` | Invite email |
| `SMTP_PORT` | 587 | 465 ⇒ implicit TLS, else STARTTLS |
| `SMTP_USER` / `SMTP_PASS` | — | Brevo SMTP login + key. Missing ⇒ **dry-run** |
| `MAIL_FROM` | — | Verified sender. Missing ⇒ dry-run |
| `BREVO_API_KEY` | — | Only used to LIST verified senders; blank ⇒ manual sender entry |
| `BREVO_WEBHOOK_SECRET` | — | Guards the public delivery webhook (**fails closed** when unset) |
| `FIREBASE_STORAGE_BUCKET` | falls back to `VITE_FIREBASE_STORAGE_BUCKET` | Invite-logo hosting |
| `USE_VERTEX` | `false` | Vertex AI instead of an API key |
| `GOOGLE_CLOUD_PROJECT`, `VERTEX_LOCATION` | — / `us-central1` | Vertex config |
| `DEEPGRAM_API_KEY` | — | Live STT + recording transcription |
| `HUME_API_KEY` | — | Voice prosody (batch) |
| `FACE_CACHE_HOSTS` | — | Extra allowed hosts for the replica-preview cache |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | — | Rekognition |
| `AWS_REGION` | `us-east-2` | Rekognition region |
| `TAVUS_API_KEY` | — | Deployment-wide fallback only |
| `DAILY_API_KEY` | — | Two-way interview; blank ⇒ 503 |
| `DAILY_SUBDOMAIN` | — | Optional display convenience |
| `FIREBASE_PROJECT_ID` | `talbotiq-9cc4e` | Admin SDK |
| `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` | — | Admin SDK; blank ⇒ auth-guarded endpoints return **503** |
| `GOOGLE_APPLICATION_CREDENTIALS` | — | Alternative ADC path |
| `ADMIN_EMAILS` | — | Admin overlay allowlist |
| `DATA_DIR` | `server/data` | JSON store location (Render: `/var/data`) |
| `CORS_ORIGINS` | blank ⇒ all origins | Comma-separated allowlist |

**Client (public, compiled into the bundle)**
`VITE_API_BASE`, `VITE_FIREBASE_API_KEY`, `VITE_FIREBASE_AUTH_DOMAIN`, `VITE_FIREBASE_PROJECT_ID`, `VITE_FIREBASE_STORAGE_BUCKET`, `VITE_FIREBASE_MESSAGING_SENDER_ID`, `VITE_FIREBASE_APP_ID` (`.env.example:142-149`).
Face-fit overrides: `VITE_FACEFIT_WASM_BASE`, `VITE_FACEFIT_MODEL_URL` (`facefit/config.ts`).

**Console warnings on boot** (`server/index.ts:100-106`):
- "GEMINI_API_KEY not set — adaptive questions & scoring use heuristic fallback."
- "[auth] Firebase Admin is NOT configured — auth-guarded /api endpoints will return 503. Set FIREBASE_PROJECT_ID/CLIENT_EMAIL/PRIVATE_KEY (see docs/AUTH.md)."
- CORS: "restricted to: …" or "all origins allowed (set CORS_ORIGINS to restrict)".

### 5.8 Client-persisted (browser) settings

Zustand `persist` under `localStorage['talbotiq-store']` (`src/store/useAppStore.ts`; cleared by Settings → Reset to Defaults). Holds the Tavus key, webhook URL, default replica/persona, saved Setup drafts, current conversation, questions, metrics, Hume state and Deepgram transcript.

Mimic Guide keys (`MimicGuide.tsx:34-37`): `mimic-guide-history` (last 20 turns), `mimic-guide-voice-lang`, `mimic-guide-autospeak`.

### 5.9 Deployment configuration

- **Vercel** (SPA): build `cd talbotiq-platform && npm run build`, output `talbotiq-platform/dist`, SPA rewrite, immutable asset caching, security headers `X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options` (`vercel.json`).
- **Render** (API): Docker blueprint `talbotiq-api`, plan `starter`, region `oregon`, health check `/api/health`, `autoDeploy: false`, 1 GB persistent disk mounted at `/var/data` (`render.yaml`).
- **Operational constraints** (`docs/DEPLOY-VERCEL-RENDER.md:126-137`): the disk pins the API to **one instance** — do not scale horizontally; back up `/var/data/db.json`; WebSocket origin is not CORS-filtered (it authenticates by ID token in the query string).
- Firebase **Authorized domains** must include the Vercel domain or every login fails with `auth/unauthorized-domain` (`:48-52`).

---

## 6. Integrations, notifications, exports and files

### 6.1 Third-party integrations

| Integration | Used for | Where the key lives | Failure behaviour |
|---|---|---|---|
| **Firebase Auth** | Sign-in/sign-up | Public web config in the bundle; Admin SDK server-side | 503 on auth-guarded endpoints when Admin isn't configured |
| **Firebase Firestore** | `users/{uid}` role; `interviews/{id}` invite docs | as above | `sessions/mine` degrades gracefully (`sessions.ts:1037-1039`) |
| **Firebase Storage** | Video answers, two-way recordings, invite-email logos | Admin SDK | 500 `Storage bucket not configured (set FIREBASE_STORAGE_BUCKET or VITE_FIREBASE_STORAGE_BUCKET)` |
| **Google Gemini** | Question generation, scoring, sentiment, Mimic Guide, Guide TTS, avatar voice-prosody fallback | server (`GEMINI_API_KEY`) or a runtime key saved via Settings | heuristic fallback; explicit "degraded" banner |
| **Gemini Live** | Voice-track audio + voice previews + Guide TTS | server | voice disabled without a key |
| **Tavus** | Video-avatar replicas, personas, conversations | Runtime key entered in Settings (never bundled); optional `TAVUS_API_KEY` fallback | 503 "not configured yet…"; Setup surfaces a Tavus error modal with a demo-mode fallback |
| **Daily** | Two-way live video (rooms, tokens, knocking lobby) | `DAILY_API_KEY` server-side | 503 |
| **Deepgram Nova-3** | Live transcription (avatar + video tracks), recording transcription | `DEEPGRAM_API_KEY` server-side; browser gets a 30 s token | 400 "Deepgram is not configured on the server"; 502 token-grant failure |
| **Hume AI** | Voice prosody/emotion (batch) | `HUME_API_KEY` server-side | Falls back to a Gemini audio-prosody analysis wrapped in Hume's wire shape (`server/routes/avatar.ts:67-219`); 502 when neither is available |
| **AWS Rekognition** | Facial analysis (DetectFaces) | `AWS_*` server-side | graceful "not captured" state |
| **Brevo (SMTP + REST)** | Invite/advance/selected/rejection emails; verified-sender list; delivery webhooks | `SMTP_*`, `MAIL_FROM`, `BREVO_API_KEY`, `BREVO_WEBHOOK_SECRET` | Dry-run logging when SMTP is incomplete |
| **MediaPipe Tasks-Vision** | Face-fit framing aid (on-device only) | none | Falls back to a guide-only oval + manual "I'm ready"; never hard-blocks |

### 6.2 Emails the candidate receives

| Email | When | Rendered by |
|---|---|---|
| **Invite** | Bulk invite send / retry / pipeline round-1 invite | `shared/inviteEmail.ts:205-222`; legacy built-in fallback at `server/routes/invites.ts:53-69` |
| **Advance** | Candidate advanced to the next round | `renderTransitionEmail(kind:'advance')` — carries the link + exact-email note |
| **Selected** | Advanced past the final round | `renderTransitionEmail(kind:'selected')` — no link |
| **Rejection** | "Not advancing" **and** the recruiter opted in | `renderTransitionEmail(kind:'rejection')` — no link |
| **Test invite** | Step 4 "Send test to me" | subject prefixed `[TEST] ` (`invites.ts:386`) |

Email shell: branded header (logo or company name on the accent colour), body, CTA button, locked "exact email" note, plain-link fallback, footer (`shared/inviteEmail.ts:181-194`). Every send carries the header `X-Mailin-custom: {"interviewId": …}` for webhook correlation (`invites.ts:129`).

### 6.3 Delivery status tracking

`InviteSendStatusValue` = `accepted | delivered | bounced | spam | failed | opened | clicked` (`shared/types.ts:108-109`).

Brevo event → status mapping (`server/routes/brevoWebhook.ts:24-44`):
`delivered`→delivered · `hardbounce|hard_bounce|softbounce|soft_bounce`→bounced · `spam`→spam · `blocked|invalid|error|deferred`→failed · `opened|uniqueopened|unique_opened|open`→opened · `click|clicked`→clicked · anything else → ignored (still ack'd 200).

Webhook URL to configure in Brevo: `https://<host>/api/invites/brevo-webhook?token=<BREVO_WEBHOOK_SECRET>` (`brevoWebhook.ts:12-15`). Localhost needs a tunnel.

### 6.4 In-app notifications

- **Toasts** — bottom-right, 4 s default, purple (`#6B2BE0`) success/loading icons, red error (`src/App.tsx:115-136`). Full inventory in §4.
- **Integrity warnings** — ⚠️ toasts with a counter (§4.13.11).
- **Live badge** in the nav while an avatar interview is active; **"Add API Key →"** chip when no Tavus key is set (`Nav.tsx:73-87`).

### 6.5 Files the user touches

| Direction | File | Constraints | Source |
|---|---|---|---|
| Upload | Candidate résumé | PDF / DOCX / TXT, **8 MB** | `sessions.ts:40`, `ResumeUpload.tsx:72-84` |
| Upload | Résumé for question generation | **PDF only**, **10 MB** | `questionSets.ts:11`, `:54` |
| Upload | Candidate list | CSV / TSV / XLSX / XLS / PDF / DOCX / TXT, **10 MB** | `invites.ts:29`, `InviteWizard.tsx:750-757` |
| Upload | Invite-email logo | any `image/*`, **2 MB** | `invites.ts:307-309` |
| Upload | Hume audio job | **25 MB** | `avatar.ts:24` |
| Upload (implicit) | Video answers / two-way recording → Firebase Storage | **< 50 MB**, `video/*` | `storage.rules:23-24` |
| Download | Candidate report PDF | `TalbotIQ-<Name>-report.pdf` | `ReportPage.tsx:173` |
| Download | Selected-candidates CSV | `<role>-selected.csv`, header `Name, Email, Final score` | `PipelineBoardPage.tsx:506-510` |
| Download | Avatar-screening HTML report | `TalbotIQ-Report-<conversationId>.html` | `ResultsPage.tsx:228-236` |
| Copy | Candidate invite link | `<origin>/take/<id>` | `SessionsPage.tsx:151` |
| Copy | All invite links | `email: link` per line | `InviteWizard.tsx:521` |
| Copy | Profile summary / offer recommendation | clipboard text | `ResultsPage.tsx:619-623`, `:669` |
| Server-side | JSON store `db.json` | under `DATA_DIR` | `server/store/db.ts:22-25` |
| Server-side | Replica preview cache | `server/data/face-cache/*.mp4`, max 150 MB per file, https + host allowlist | `server/routes/faceCache.ts:26-39` |

### 6.6 Scoring & background processing (what the user sees happen "later")

- Scoring is triggered automatically when a session reaches `completed`, guarded against duplicates (`server/routes/sessions.ts:112-126`).
- Conversation tracks use `scoreConversation`; others use `scoreWithGemini` with a deterministic heuristic fallback (`server/services/scoring.ts:57-73`).
- **Overall score is computed in application code, never by the model** — weighted average of enabled KPIs with weights normalised (`scoring.ts:28-35`).
- **Recommendation thresholds** (`scoring.ts:48-53`): ≥80 `strong_yes`, ≥65 `yes`, ≥50 `maybe`, else `no`.
- Heuristic fallback summary text: "Generated by the heuristic fallback (no Gemini key configured). Scores reflect answer length only, not content quality." (`scoring.ts:243-245`).
- Not-evaluated summary: "No candidate answers were captured for this interview, so it was not evaluated. This usually means the interview audio or transcript was not recorded (the call may have ended early, or capture failed). Please ask the candidate to retake the interview, or check the avatar/voice configuration in Settings." (`scoring.ts:162-166`).
- **Speech metrics** are transcript-derived only — words, answers, avg words/answer, filler count, fillers per 100, vocabulary %, avg response seconds, spoken flag (`server/services/signals.ts:47-81`). Filler set: `um, umm, uh, uhh, er, erm, ah, hmm, mmm, you know, i mean, kind of, sort of, you see`.
- **Sentiment** is a *text* read (overall tone + confidence/clarity/positivity 0–100 + summary), explicitly labelled "From the transcript — reflects what the words convey, not audio tone." (`signals.ts:103-142`, `ReportPage.tsx:550-552`).
- Completed invite sessions sync their result back to Firestore with `resultPublished: false` — "the recruiter publishes to the candidate separately" (`server/services/inviteBridge.ts:171-191`).

---

## 7. Glossary

| Term | Meaning | Source |
|---|---|---|
| **Mimic** | The product name used in the signed-in app and on the marketing site | `Nav.tsx:48`, `content.ts:215` |
| **TalbotIQ** | The company that builds Mimic; also the default branding company name | `content.ts:215`, `defaults.ts:150` |
| **Track** (`TrackType`) | The format an interview runs in: `chat`, `chatbot`, `voice`, `video_avatar`, `video`, `two_way` | `shared/types.ts:9` |
| **Timed Q&A** | The `chat` track — prep + answer countdown per question, auto-submit at 0 | `invites.ts:50` |
| **Chatbot / Conversational** | The `chatbot` track — typed back-and-forth with optional adaptive follow-ups | `conversation.ts` |
| **Voice track** | Live spoken interview over a WebSocket relay to Gemini Live | `README.md:88-107` |
| **Video Avatar / Conversational AI** | A Tavus AI avatar conducts the interview on video | `sessions.ts:274-279` |
| **Video Interview** | Candidate answers on camera; the live transcript is the answer | `docs/VIDEO_INTERVIEW.md` |
| **Two-way Interview** | Live recruiter↔candidate video call over Daily | `docs/TWO_WAY_INTERVIEW.md` |
| **Template** (`InterviewTemplate`) | Reusable configuration: track, question source, timing, rubric, branding, integrity, voice | `shared/types.ts:368-389` |
| **Question set** (`QuestionSet`) | A reusable ordered list of fixed questions | `shared/types.ts:72-78` |
| **Fixed question** | One saved question: text, optional category, optional ideal-answer notes | `shared/types.ts:66-71` |
| **Ideal-answer notes** | Scoring hints attached to a question — **server-only, never sent to the candidate** | `shared/types.ts:405` |
| **Question source** | `adaptive` (Gemini generates from the résumé) or `fixed` (a saved set) | `shared/types.ts:10` |
| **Tailor** | The invite-wizard name for the adaptive/per-résumé question source | `InviteWizard.tsx:646` |
| **Session** (`InterviewSession`) | One candidate's interview instance; server-held, never sent in full to the client | `shared/types.ts:450-492` |
| **Session status** | `created`, `system_check`, `in_progress`, `completed`, `expired` | `shared/types.ts:394-399` |
| **Phase** | `prep` or `answer` within a timed question | `shared/types.ts:393` |
| **Turn** | One conversational message (interviewer or candidate) | `shared/types.ts:434-448` |
| **Turn type** | `greeting`, `readiness`, `question`, `follow_up`, `acknowledgment`, `wrap_up` — only `question`/`follow_up` are ever timed | `shared/types.ts:426-431` |
| **Readiness gate** | The opening greeting ends by asking "Are you ready to begin?"; the reply is not scored | `conversation.ts:211-216`, `:466-504` |
| **Draft** (candidate) | Auto-saved in-progress answer text, restored after a refresh | `shared/types.ts:412` |
| **Draft** (Setup page) | A saved Tavus configuration + question list in browser storage | `useAppStore.ts:21-27` |
| **KPI** (`KpiDefinition`) | One scoring dimension: id, label, description, weight, enabled | `shared/types.ts:54-60` |
| **Rubric** (`KpiRubric`) | The set of KPIs plus a fixed 100-point scale | `shared/types.ts:61-64` |
| **Weight normalisation** | Enabled KPI weights are rescaled to sum to 100 % at scoring time | `scoring.ts:28-35` |
| **Overall score** | Weighted mean of KPI averages, 0–100, computed server-side | `scoring.ts:28-35` |
| **Recommendation** | `strong_yes` (≥80), `yes` (≥65), `maybe` (≥50), `no` | `shared/types.ts:499`, `scoring.ts:48-53` |
| **Degraded report** | Scored by the heuristic fallback because Gemini was unavailable | `shared/types.ts:539` |
| **Not evaluated** | No candidate answers captured; the zeros are placeholders, not a judgment | `shared/types.ts:540-542` |
| **Speech metrics** | Transcript-derived delivery stats (words, fillers, vocabulary %, …) | `shared/types.ts:506-517` |
| **Sentiment signals** | Text-based communication read: overall tone + confidence/clarity/positivity + summary | `shared/types.ts:519-527` |
| **Signal analysis** | The report section combining speech metrics + sentiment | `ReportPage.tsx:472-562` |
| **Integrity events** | `tab_switch`, `window_blur`, `paste_blocked`, `copy_blocked`, `fullscreen_exit` | `shared/types.ts:415-424` |
| **Integrity flag rate** | Fraction of scored sessions with ≥1 logged event | `shared/types.ts:706` |
| **Invite / interview doc** | A Firestore `interviews/{id}` record created per candidate at bulk-invite time | `invites.ts:202-241` |
| **testId** | The shared batch id stamped on every invite in one send | `invites.ts:179` |
| **Materialise (claim)** | Turning a Firestore invite into a local session + synthesised template on first open | `inviteBridge.ts:14-25` |
| **Dry run** | The mailer logs instead of sending because SMTP config is incomplete | `server/services/email.ts:12-16` |
| **Verified sender** | A Brevo-verified From address; required to send | `.env.example:39-43` |
| **Locked token** | `{{interview_link}}` — cannot be removed from an invite/advance email | `shared/inviteEmail.ts:26-30` |
| **Pipeline** | An ordered set of rounds for one role | `shared/types.ts:146-155` |
| **Round** (`RoundDef`) | One stage of a pipeline: name, mode, question source/config, optional advance rule | `shared/types.ts:129-144` |
| **Advance rule** | `threshold` (score ≥ value) or `topN` (top N by score) | `shared/types.ts:125-127` |
| **Pipeline candidate status** | `in_round`, `advanced`, `selected`, `not_advancing` | `shared/types.ts:163` |
| **Advanceable** | In an active round **and** completed **and** genuinely scored (`notEvaluated !== true`) | `pipelines.ts:105-110` |
| **Round status** (board card) | `invited`, `in_progress`, `completed` (shown as "Scored"), `expired`, `none` | `PipelineBoardPage.tsx:29-35` |
| **Move back** | Undo the most recent advance while the new round is not yet completed; deletes that round's interview doc | `pipelines.ts:382-414` |
| **Audit entry** | Timestamped record of `invited / advanced / selected / not_advancing / moved_back` with actor, rounds, basis and email result | `shared/types.ts:171-179` |
| **Replica** | A Tavus avatar face/voice (custom or stock); trains in ~15 min | `ReplicasPage.tsx:67` |
| **Persona** (Tavus) | The avatar's system prompt/context + LLM/TTS/STT/perception/VQA layers | `PersonasPage.tsx` |
| **Persona** (Voice track) | An interviewer character: style prompt + default voice | `shared/types.ts:347-356` |
| **Conversational context** | The system prompt sent to the Tavus LLM | `SetupPage.tsx:350` |
| **Custom greeting** | The avatar's first spoken words | `SetupPage.tsx:351` |
| **Pipeline mode** (Tavus) | `full`, `echo`, `no_audio`, `video_only` | `SetupPage.tsx:30-33` |
| **Barge-in** | The candidate may interrupt the AI interviewer by speaking | `shared/types.ts:363` |
| **Voice phase** | `connecting`, `greeting`, `listening`, `thinking`, `speaking`, `ended`, `error` | `shared/types.ts:929-936` |
| **Face-fit pre-flight** | On-device framing aid before video/avatar interviews; **not** the scoring facial analysis | `facefit/config.ts:8-10` |
| **Demo mode** | Setup/Interview run with no Tavus replica — no avatar video | `SetupPage.tsx:144-158` |
| **Mimic Guide** | The in-app AI assistant (chat + voice + navigation links) | `mimicGuidePrompt.ts:15` |
| **Autopilot** | Guide mode where the assistant operates the real UI, one action per turn, with confirmation before side effects | `executor.ts:9-15` |
| **Side-effect action** | An Autopilot action requiring an explicit read-back confirm before it runs | `shared/autopilot.ts:22` |
| **Voice mode** | Hands-free Guide listening that auto-submits after a pause, even with the panel closed | `MimicGuide.tsx:261-266` |
| **Lead** | A marketing demo request stored server-side (never Firestore) | `server/store/db.ts:27-38` |
| **Admin overlay** | A recruiter listed in `ADMIN_EMAILS` who additionally sees unclaimed legacy sessions | `shared/types.ts:12-19` |
| **Legacy session** | A session created before ownership existed (`recruiterId` absent) — admin-only until claimed | `shared/types.ts:453-455` |

---

## Open Questions

Behaviours the code does not settle. **Do not document these as facts** until confirmed.

1. **Templates and question sets are not owner-scoped.** `GET /api/templates` and `GET /api/question-sets` return *every* record to *any* recruiter (`server/routes/templates.ts:19-21`, `server/routes/questionSets.ts:39-41`), unlike sessions, pipelines and invite-email templates. Is a shared library intended, or is this a gap? The manual's permissions section depends on the answer.

2. **Track dropdown vs. supported tracks.** The template editor offers only `chat`, `chatbot`, `voice`, `video_avatar` (`TemplateEditorPage.tsx:152-157`), and the candidate "Choose your format" screen offers only three (`TrackSelect.tsx:14-18`), while `video` and `two_way` exist and are selectable in the invite wizard. Are `video`/`two_way` invite-only by design?

3. **`video_avatar` labelled "(scaffold)" / "Preview".** The editor says "Video Avatar (scaffold)" and the candidate picker tags it "Preview", yet the README describes a complete server-side Tavus flow. What is the supported status for end users?

4. **`pipeline` voice engine.** `VoiceEngine = 'pipeline'` is offered in the editor as "STT → Gemini → TTS (coming soon)" and documented as "a typed flag, not yet built" (`shared/types.ts:331-333`, `README.md:95-96`). Should it be shown to users at all?

5. **Settings page platform toggles.** *White-label Mode*, *GDPR Auto-Purge* and *Multi-language Avatar* are local `useState` only — they are not persisted or read anywhere (`SettingsPage.tsx:35-37`, `:178-180`). Do they do anything?

6. **Settings page Webhook URL.** Stored in browser state (`store.setWebhookUrl`) but no code was found that sends it to Tavus or the server. Is it purely informational?

7. **Results-page recruiter actions.** "Schedule Technical Interview" shows a form and toasts "Interview scheduled" without persisting anything; "Generate Offer Rec." renders a text block; "Share Profile" copies a one-line summary (`ResultsPage.tsx:628-673`). Are these mock/demo affordances?

8. **`/results` vs `/sessions/:id/report`.** Both are "results" screens with different data models and scoring (`App.tsx:84-87`). How should the manual frame the relationship for a recruiter?

9. **`/interview` and `/results` are not in the top nav** (`Nav.tsx:12-16` says candidate results live under Sessions → View report and the avatar room launches from Avatar studio). How do recruiters reach `/interview` and `/results` in normal use?

10. **Session `expired` status** exists in the type union (`shared/types.ts:399`) and is rendered as a status badge and a board `roundStatus`, but a repo-wide search found only *reads* of it — no code path ever assigns `status = 'expired'`. What expires a session, and after how long?

11. **`maxTabSwitchWarnings`** is surfaced to the candidate in the warning counter, but no enforcement (termination, lockout, flagging) on exceeding it was found. What is meant to happen at the limit?

12. **`InterviewSession.questions[].videoUrl`** and `SessionReportQuestion.videoUrl` render a `<video>` on the report, but the Video Interview track submits a transcript rather than a clip (`VideoStage.tsx:21-28`). Which flow populates `videoUrl`?

13. **Candidate result publication.** Invite results sync to Firestore with `resultPublished: false` and the comment "the recruiter publishes to the candidate separately" (`inviteBridge.ts:187`). No publish UI was found in this repo. Where does publication happen?

14. **Marketing statistics.** Figures such as "1.3 days", "62%", "340k", "8,400", "-71%", "4.6/5" and the compliance badges (SOC 2 Type II, ISO 27001, ISO 42001, GDPR ready, WCAG 2.2 AA, EEOC-aligned) are described in-code as "illustrative and to be replaced with real data before public launch" (`MimicSite.tsx:6-10`, `:55-96`). The Trust pages simultaneously mark certifications as `[PLACEHOLDER]` (`content.ts:397`). Which, if any, may appear in a manual?

15. **Mimic Guide knowledge base drift.** The Guide's system prompt tells users roles are "decided on the server by your verified email … Recruiter access is granted to allowed email domains/addresses (by default the talbotiq.com domain)" (`mimicGuidePrompt.ts:94`), which contradicts the implemented model (self-selected `users/{uid}.role`, `docs/AUTH.md:16-23`). It also lists only four tracks and omits Pipelines. Which is authoritative for the manual?

16. **Two-way scheduling.** v1 is strictly candidate-first: the candidate must open their link before the recruiter can host, and the recruiter must open `/live/:id` before the candidate's knock succeeds (`docs/TWO_WAY_INTERVIEW.md:14-22`, `:161`). Is this the shipped user-facing procedure, or is a scheduled-start flow expected before release?

17. **Data retention / GDPR purge.** `docs/VIDEO_INTERVIEW.md:175-177` states Video Interview has **no** automatic media cleanup yet, while marketing and the Settings toggle assert configurable retention and GDPR purge. What is actually in place?

18. **Recruiter self-service for `/sessions` created without an email.** The single-link modal shows candidate email as an ordinary field, but the server rejects a blank one with `A candidate email is required to assign this interview`; the UI does not mark it required or validate the format client-side (`SessionsPage.tsx:219`). Intended?

19. **`GET /api/health`'s `authMode`** returns `'firebase' | 'none'` (`server/index.ts:44`) — is this surfaced to any user, or purely operational?
