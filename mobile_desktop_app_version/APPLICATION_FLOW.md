# TalbotIQ — Application Flow & Firebase Integration Guide

> **Purpose:** a complete map of how the TalbotIQ app works, with emphasis on
> **Firebase** (Auth + Firestore), the login flow, the data model, and how every
> service is wired in. It is written so that a **web implementation** can reuse
> the *exact same* Firebase project, collections, security rules, and flows.
>
> The Flutter app and the website should be **two clients on one backend** — same
> Firebase project, same Firestore documents, same rules. A recruiter can create a
> test on the app and a candidate can take it on the web (or vice-versa) with no
> data migration.

---

## 1. What the app is

TalbotIQ runs **AI-driven interview screenings**. There are two roles:

- **Recruiter** — creates interviews (video or chat), assigns them to candidate
  emails, sets access windows/attempts, and reviews + publishes results.
- **Candidate** — signs in with the email a recruiter assigned, sees their
  assigned interviews, takes them, and (once published) views results.

The interview itself is powered by external AI services (Tavus for the video
avatar, Gemini/Anthropic for scoring, Deepgram for transcription, Hume for voice
sentiment, AWS Rekognition for facial analysis). **Firebase is the backbone that
ties users, roles, assignments, and results together.**

---

## 2. Architecture at a glance

```
          ┌─────────────────────────────────────────────┐
          │              Firebase project                │
          │             (talbotiq-9cc4e)                 │
          │                                              │
          │   Auth (Email/Password)   Cloud Firestore    │
          └───────▲───────────────────────▲──────────────┘
                  │                        │
      ┌───────────┴──────────┐   ┌─────────┴───────────┐
      │   Flutter app         │   │   Website (new)     │
      │  (recruiter+candidate)│   │  (same collections) │
      └───────────┬───────────┘   └─────────┬───────────┘
                  │                          │
                  └──────────┬───────────────┘
                             ▼
        External AI services, called client-side with
        the RECRUITER's API keys pulled from Firestore:
        Tavus · Gemini · Deepgram · Hume · AWS Rekognition proxy
```

**Key idea:** Firebase stores *who you are*, *what you were assigned*, and *your
results*. The heavy AI calls happen **client-side** using API keys that are
themselves stored in Firestore (per recruiter). See §7.

---

## 3. Firebase project & client config

The project is already created and configured. Client config (safe to embed —
this is public client config, **not** a secret):

| Field | Value |
|-------|-------|
| projectId | `talbotiq-9cc4e` |
| authDomain | `talbotiq-9cc4e.firebaseapp.com` |
| storageBucket | `talbotiq-9cc4e.firebasestorage.app` |
| messagingSenderId | `473028554722` |
| **web** apiKey | `AIzaSyAF1O1SoXKv5iZ1RMaXQurVYwRSoT4ynqY` |
| **web** appId | `1:473028554722:web:152baa837fe77c7fb713bb` |
| measurementId | `G-LGFED7318W` |

> The full per-platform config lives in `lib/firebase_options.dart`. For the
> website you only need the **web** block above.

**Enabled services:** Authentication (Email/Password) and Cloud Firestore. No
Cloud Functions or Storage buckets are used by the current flows.

### Web SDK setup (JS/TypeScript)

```ts
// firebase.ts
import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";

const firebaseConfig = {
  apiKey: "AIzaSyAF1O1SoXKv5iZ1RMaXQurVYwRSoT4ynqY",
  authDomain: "talbotiq-9cc4e.firebaseapp.com",
  projectId: "talbotiq-9cc4e",
  storageBucket: "talbotiq-9cc4e.firebasestorage.app",
  messagingSenderId: "473028554722",
  appId: "1:473028554722:web:152baa837fe77c7fb713bb",
  measurementId: "G-LGFED7318W",
};

export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
```

> Before the website goes live, add its domain under **Firebase console → Auth →
> Settings → Authorized domains**.

---

## 4. Login & role flow (the heart of it)

### 4.1 The rule: **role lives in Firestore, not in Auth**

Firebase Auth only knows email/password. The app stores each user's **role**
(`recruiter` | `candidate`) in a Firestore document `users/{uid}`. Everything —
routing, security rules, assignment matching — reads from there.

### 4.2 Sign-up

`AuthService.signUp` (`lib/features/auth/auth_service.dart`):

1. `createUserWithEmailAndPassword(email, password)` → new Auth user.
2. Optionally set the Auth `displayName`.
3. **Write the role doc** `users/{uid}`:
   ```json
   {
     "email": "person@example.com",
     "emailLower": "person@example.com",
     "role": "recruiter",          // or "candidate"
     "name": "Jane R.",            // optional
     "createdAt": <serverTimestamp>
   }
   ```

Web equivalent:
```ts
import { createUserWithEmailAndPassword, updateProfile } from "firebase/auth";
import { doc, setDoc, serverTimestamp } from "firebase/firestore";

const cred = await createUserWithEmailAndPassword(auth, email.trim(), password);
if (name) await updateProfile(cred.user, { displayName: name });
await setDoc(doc(db, "users", cred.user.uid), {
  email: cred.user.email,
  emailLower: (cred.user.email ?? email).trim().toLowerCase(),
  role,                       // "recruiter" | "candidate"
  ...(name ? { name } : {}),
  createdAt: serverTimestamp(),
});
```

### 4.3 Sign-in & routing (the "AuthGate")

`AuthGate` (`lib/features/auth/auth_gate.dart`) is the root router. It reacts to
two live streams:

```
authStateChanges()  ──►  no user          ──►  Login screen
                    ──►  user signed in    ──►  read users/{uid}.role (live) ──►
                                                   "recruiter" ──► Recruiter home
                                                   "candidate" ──► Candidate home
```

The role is a **live stream** (`onSnapshot` of `users/{uid}`), so if the role doc
is created moments after sign-in, the UI re-routes automatically. If the doc is
missing, the app defaults to **candidate**.

Web equivalent:
```ts
import { onAuthStateChanged } from "firebase/auth";
import { doc, onSnapshot } from "firebase/firestore";

onAuthStateChanged(auth, (user) => {
  if (!user) return showLogin();
  onSnapshot(doc(db, "users", user.uid), (snap) => {
    const role = snap.data()?.role ?? "candidate";
    role === "recruiter" ? showRecruiterHome() : showCandidateHome();
  });
});
```

> **Reuse note:** the website must use the same `users/{uid}` shape and the same
> `role` values (`"recruiter"` / `"candidate"`). Then an account created on the
> app logs into the website with the same role, and vice-versa.

---

## 5. Firestore data model

Three collections. All timestamps are Firestore server timestamps.

### `users/{uid}`
The account + role doc (written at sign-up).
```
email        string
emailLower   string   // trimmed + lowercased, for case-insensitive matching
role         string   // "recruiter" | "candidate"
name         string?  // optional display name
createdAt    timestamp
```

### `interviews/{id}`
A recruiter-created interview assigned to **one** candidate email. (Assigning to
several candidates creates several docs that share a `testId`.)
```
testId               string   // shared by all candidates created in one action
recruiterId          string   // == the creating recruiter's uid
recruiterEmail       string
recruiterName        string?  // shown to the candidate ("from …")
candidateEmail       string
candidateEmailLower  string   // the field candidates query + rules match on
candidateName        string?
type                 string   // "video" | "chat"
title                string
prompt               string   // interviewer instructions (video only)
questions            string[]
avatar               { replicaId: string, personaId?: string }   // video only
durationMinutes      number
status               string   // "assigned" | "in_progress" | "completed"
keyOverrides         map      // per-test API key overrides — see §7.3
availableFrom        timestamp?   // access window start (optional)
expiresAt            timestamp?   // access window end   (optional)
maxAttempts          number?      // null = unlimited
attemptsUsed         number       // incremented each launch
result               map?         // scorecard, written on completion (see §6.3)
resultPublished      bool          // recruiter-controlled visibility to candidate
createdAt            timestamp
updatedAt            timestamp
```
Model + (de)serialization: `lib/features/interviews/models/interview.dart`.
Firestore access: `lib/features/interviews/services/interview_repository.dart`.

### `recruiter_keys/{recruiterId}`
Each recruiter's API keys for the external services (see §7).
```
tavusKey     string
deepgramKey  string
humeKey      string
awsKey       string
anthropicKey string
geminiKey    string
awsProxyUrl  string
webhookUrl   string
updatedAt    timestamp
```

> The app also has an old note referring to `app_config/global`; the **live**
> model is per-recruiter `recruiter_keys/{recruiterId}` — use that.

---

## 6. End-to-end flows

### 6.1 Recruiter creates & assigns an interview

Screen: `lib/features/interviews/recruiter/create_interview_page.dart`.

1. Recruiter fills type (video/chat), title, candidate email(s), questions,
   duration, optional access window, optional attempt limit, avatar (video), and
   optionally **custom per-test keys** (§7.3).
2. On **Save & assign**, a confirmation dialog states *"candidates run this test
   on your API keys"* (or the custom keys, if set).
3. One `interviews/{id}` doc is created **per candidate email**; all share a
   generated `testId`. Status starts at `assigned`.

Repository call: `InterviewRepository.create(interview)` →
`_col.add(interview.toCreateMap())`.

### 6.2 Candidate takes an interview

Screen: `lib/features/interviews/candidate/candidate_home.dart`.

1. Candidate signs in with the assigned email. The home lists interviews where
   `candidateEmailLower == myEmail` (live query).
2. Access is gated client-side by the window (`availableFrom`/`expiresAt`) and
   `attemptsUsed < maxAttempts`.
3. On **Launch**, the app pulls the **recruiter's keys** (see §7.2) and applies
   them in-memory, then:
   - **video** → creates a Tavus conversation and opens the video shell,
   - **chat** → runs the chat interview engine (scored with Gemini).
4. `attemptsUsed` is incremented; `status` moves `assigned → in_progress →
   completed`.

### 6.3 Results

- On completion the client writes an **unpublished** `result` map onto the
  interview doc (`InterviewRepository.completeWithResult`). Shape:
  ```
  result: {
    overallScore: number,
    summary: string,
    recommendation: string,
    strengths: string[],
    improvements: string[],
    evaluatedBy: "ai" | "manual",
    detail: { ...raw }
  }
  ```
- The recruiter reviews/edits it
  (`recruiter/evaluate_interview_page.dart`) and **publishes** by setting
  `resultPublished = true` (per candidate, or a whole test via
  `publishTest(testId, recruiterId)`).
- The candidate only sees a result when `resultPublished == true`. Security rules
  forbid the candidate from flipping that flag themselves.

---

## 7. API keys model (important — read before wiring services)

### 7.1 Where keys live

- A **recruiter** enters their keys in **Settings → API Credentials**
  (`lib/views/settings/api_credentials_section.dart`), stored on-device, then
  taps **"sync keys to cloud"** which writes them to
  `recruiter_keys/{recruiterId}` (`AppConfigService.pushForRecruiter`).
- A **candidate never stores org keys**. They are never shown in the candidate UI
  and never written to the candidate's device.

### 7.2 How keys reach the candidate at launch

`AppConfigService.applyForRecruiter(recruiterId, store, {overrides})`
(`lib/features/app_config/app_config_service.dart`):

1. Reads `recruiter_keys/{interview.recruiterId}`.
2. Applies the keys to the **in-memory service singletons only** for the duration
   of the session — not persisted, not shown anywhere.
3. Each launch fully re-establishes that org's keys, so an interview from Org A
   never consumes Org B's credentials.

Because each `interviews` doc carries its `recruiterId`, the candidate client
always knows *whose* keys to fetch.

### 7.3 Per-test key overrides (recent feature)

An interview can carry a `keyOverrides` map. When a candidate launches, any
non-empty entry there is used **instead of** the recruiter's Settings key; blank
entries fall back to the recruiter's keys.

```
keyOverrides: {
  tavusKey?: string,      // video
  geminiKey?: string,     // chat scoring / ATS
  humeKey?: string,       // voice sentiment
  deepgramKey?: string,   // transcription
}
```

The recruiter sets these on the Create-interview page ("Use custom keys for this
test"). Merge precedence in `applyForRecruiter`: **override → recruiter key →
empty**.

### 7.4 ⚠️ Security caveat (matters for the website)

Because the AI calls are made **client-side** and the rules allow any signed-in
user to *read* `recruiter_keys`, a technically-skilled candidate can extract the
keys. This is **UI-hiding, not cryptographic secrecy**. The web client inherits
the exact same exposure.

> **Recommended hardening (do this once, benefits both clients):** move the
> Tavus/Gemini/etc. calls behind a **Cloud Function / server proxy** that holds
> the keys server-side and returns only the results (e.g. the Tavus conversation
> URL, or a scorecard). Then neither client ever sees a raw key, and
> `recruiter_keys` reads can be locked down. Until then, keep the current model
> and be aware of the trade-off.

---

## 8. External services reference

All are called client-side; keys come from the recruiter (§7). Service wrappers
live in `lib/core/services/`.

| Service | Used for | Key field | Notes |
|---------|----------|-----------|-------|
| **Tavus** | Real-time video avatar interviewer | `tavusKey` | Creates a "conversation" from a replica/persona; returns a join URL. Required for video. |
| **Google Gemini** | Chat-interview scoring + ATS scorecard | `geminiKey` | 2.5 Flash. |
| **Deepgram** | Transcription & speaking-pace analysis | `deepgramKey` | Nova-3. Optional. |
| **Hume AI** | Voice prosody / sentiment scoring | `humeKey` | Optional. Header `X-Hume-Api-Key`. |
| **AWS Rekognition** | Facial analysis | via `awsProxyUrl` | Called through a **proxy URL** (Lambda/local); the AWS secret stays server-side. |
| **Anthropic / Claude** | AI scorecard synthesis | `anthropicKey` | Optional. |
| **Webhook** | Outbound result notifications | `webhookUrl` | Optional. |

For the website, you can reuse the same REST endpoints these wrappers call — open
each file in `lib/core/services/` to see the exact request shape (endpoint,
headers, body) and mirror it in JS.

---

## 9. Security rules (deployed)

Source: `firestore.rules`. Summary of what they enforce:

- **`users/{uid}`** — a user may read/write **only their own** doc. No deletes.
- **`interviews/{id}`**
  - *read:* the owning recruiter (`recruiterId == uid`) **or** the assigned
    candidate (`candidateEmailLower == myEmail`).
  - *create:* recruiters only, and only with their own `recruiterId`.
  - *update:* the owning recruiter (anything, incl. `resultPublished`) **or** the
    assigned candidate (their submission/status/attempts) — but a candidate
    **cannot** change `resultPublished`.
  - *delete:* owning recruiter only.
- **`recruiter_keys/{recruiterId}`** — any signed-in user may **read** (needed so
  the candidate client can fetch keys at launch); only that recruiter may
  **write**. (See the §7.4 caveat.)

Helper functions in the rules: `isSignedIn()`, `myRole()` (reads
`users/{uid}.role`), `isRecruiter()`, `myEmailLower()` (from the auth token
email).

> The website is bound by these same rules automatically — they are server-side.
> No per-client configuration needed.

---

## 10. Checklist for the website implementation

1. **Init the Firebase web SDK** with the config in §3.
2. **Auth:** email/password sign-up (write `users/{uid}` with `role`) + sign-in.
   Add the website domain to Auth → Authorized domains.
3. **Routing:** after sign-in, read `users/{uid}.role` (live) and route to
   recruiter vs candidate UI (§4.3).
4. **Recruiter UI:** create `interviews/{id}` docs (one per candidate email,
   shared `testId`); a Settings page that writes `recruiter_keys/{uid}`.
5. **Candidate UI:** query `interviews` where `candidateEmailLower == myEmail`;
   enforce access window + attempts; on launch, fetch
   `recruiter_keys/{recruiterId}` (+ apply `keyOverrides`) and call the AI
   services; write back `status`, `attemptsUsed`, and the (unpublished) `result`.
6. **Results:** recruiter edits + sets `resultPublished`; candidate reads only
   when published.
7. **Match the field names exactly** (especially `role`, `candidateEmailLower`,
   `recruiterId`, `resultPublished`) so both clients interoperate on the same
   documents.
8. **Strongly consider** the server-proxy hardening in §7.4 before public launch.

---

## 11. File map (where to look in the Flutter code)

| Concern | File |
|---------|------|
| Firebase init | `lib/main.dart`, `lib/firebase_options.dart` |
| Auth + role read/write | `lib/features/auth/auth_service.dart` |
| Role enum + wire values | `lib/features/auth/app_role.dart` |
| Root router by auth+role | `lib/features/auth/auth_gate.dart` |
| Login/sign-up UI | `lib/features/auth/login_page.dart` |
| Interview model | `lib/features/interviews/models/interview.dart` |
| Interview Firestore access | `lib/features/interviews/services/interview_repository.dart` |
| Recruiter home + key sync | `lib/features/interviews/recruiter/recruiter_home.dart` |
| Create/assign interview | `lib/features/interviews/recruiter/create_interview_page.dart` |
| Candidate home + launch | `lib/features/interviews/candidate/candidate_home.dart` |
| Per-recruiter keys (fetch/apply) | `lib/features/app_config/app_config_service.dart` |
| Recruiter Settings (keys UI) | `lib/views/settings/api_credentials_section.dart` |
| External service wrappers | `lib/core/services/*.dart` |
| Security rules | `firestore.rules` |
| One-time Firebase setup | `FIREBASE_SETUP.md` |
```
