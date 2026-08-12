# Authentication & Access Control

This document describes the login + role layer. It **matches the Flutter app's model
exactly** so the web app and the Flutter app are two clients on **one** Firebase
project (`talbotiq-9cc4e`): an account created on either client logs into the other
with the same role, backed by the same `users/{uid}` document.

> **Stack note.** This web app runs on **Express + a JSON-file store**
> (`server/store/db.ts`) for its interview DATA — it is *not* a pure Firestore
> client. Firebase provides **identity** (Email/Password) and the **role**
> (`users/{uid}.role`); the backend still verifies the ID token and enforces
> access on every request. See "Interop limits" below for what this means.

---

## The model in one paragraph

Sign in with **Firebase Email/Password**. At **sign-up** the client writes
`users/{uid}` in Firestore with the role the user picked. The client reads that
role **live** (`onSnapshot`) and routes recruiter → recruiter app, candidate →
candidate home; a **missing doc defaults to candidate**. The server reads the
**same** `users/{uid}.role` (Admin SDK) when verifying each request, so client and
server never disagree. **No custom claims, no demo mode.**

## The `users/{uid}` document (exact shape — shared with Flutter)

Written by `signUpWithEmail` in `src/features/auth/AuthProvider.tsx`, identical to
the Flutter `AuthService.signUp`:

```jsonc
{
  "email":      "person@example.com",
  "emailLower": "person@example.com",   // trimmed + lowercased
  "role":       "recruiter",             // or "candidate"
  "name":       "Jane R.",               // optional
  "createdAt":  "<serverTimestamp>"
}
```

## Roles

- Two roles: `recruiter` and `candidate` (`UserRole` in `shared/types.ts`).
- The role is the value of `users/{uid}.role`. It is chosen at sign-up and can be
  read/written by the user (see the security caveat).
- **`admin`** is an optional, **server-only** overlay (a recruiter who also sees
  unclaimed legacy sessions), derived from the `ADMIN_EMAILS` allowlist + the
  token's verified email. It is **never** taken from the client and is **not** a
  role. Leave `ADMIN_EMAILS` blank to disable it.

## Flows

1. **Login / Sign up** on `/login` (email/password). Sign-up shows a
   **recruiter / candidate** picker that sets `users/{uid}.role`.
2. **Routing (AuthGate):** `onAuthStateChanged` → signed out → Login; signed in →
   live `onSnapshot(users/{uid})` → recruiter → `/sessions`, candidate →
   `/candidate`; missing doc → candidate. Re-routes automatically if the role doc
   is created just after sign-in.
3. **Candidate:** `GET /api/sessions/mine` returns sessions assigned to the
   candidate's verified email; none → an empty "no interviews" state.
4. **Recruiter:** the dashboard lists only sessions the recruiter owns
   (`recruiterId == uid`); admins additionally see unclaimed legacy sessions.

## Enforcement — defense in depth

1. **Client route guards (UX only):** `src/features/auth/guards.tsx` redirect by
   auth state + role. Not a security boundary.
2. **Backend authorization (the real boundary):** every `/api` request carries the
   Firebase ID token; `server/middleware/auth.ts` verifies it (Admin SDK), reads
   the role from `users/{uid}.role`, and attaches `req.auth` (`uid`, `email`,
   `role`, `admin`). Recruiter routes require the recruiter role; candidate session
   access is scoped to the caller's verified email; recruiter reads are scoped to
   owned sessions. WebSocket handshakes are authorized too (token in `?token=`).
3. **Firestore rules (`firestore.rules`):** mirror the rules deployed on
   `talbotiq-9cc4e` — a user may read/write only their own `users/{uid}` doc.

The client attaches the token to every `/api` call via a global `fetch`
interceptor in `AuthProvider` (covers `src/lib/api.ts` and the raw `fetch` calls in
the ported avatar UI).

## ⚠️ Security caveats

- **Self-assigned role (privilege escalation).** In this model the user writes
  their own `users/{uid}` doc at sign-up (rules allow writing your own doc) and the
  server trusts it. So a user can self-select `recruiter`. This is intentional for
  **interop with the Flutter app**, which works the same way. To harden later:
  assign the role server-side (Admin SDK) and tighten the Firestore rules so a
  client can't set/elevate its own role. (`server/services/users.ts` documents the
  seam.)
- **No email verification.** Matching the Flutter app, sign-up routes immediately —
  there is no verify-email gate. Add one if you need it.
- **Client-side keys (Flutter app).** `recruiter_keys` is readable by any signed-in
  user in the Flutter flow; the recommended fix is a server proxy. Not used by this
  web app (its keys stay server-side), but noted for the shared project.

## Interop limits (important)

- **Accounts + roles interoperate.** Same `talbotiq-9cc4e` project, same
  `users/{uid}` doc → an account/role created on either client works on the other.
- **Interview DATA does NOT interoperate.** This web app stores sessions/templates
  in the Express JSON store; the Flutter app stores `interviews` in Firestore. A
  test created in the Flutter app will **not** appear in this web app's candidate
  list (and vice-versa) unless the data layer is migrated to Firestore — a separate,
  larger project, intentionally out of scope here.

---

## Setup

### 1. Firebase console (`talbotiq-9cc4e`)
- **Authentication → Sign-in method:** enable **Email/Password**.
- **Authentication → Settings → Authorized domains:** add the website's domain.
- **Project settings → Service accounts → "Generate new private key"** (for the
  server Admin SDK below).

### 2. Configure env (`.env`, see `.env.example`)
Client (public web config — already filled with the `talbotiq-9cc4e` values):
```
VITE_FIREBASE_API_KEY=…
VITE_FIREBASE_AUTH_DOMAIN=talbotiq-9cc4e.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=talbotiq-9cc4e
VITE_FIREBASE_STORAGE_BUCKET=talbotiq-9cc4e.firebasestorage.app
VITE_FIREBASE_MESSAGING_SENDER_ID=473028554722
VITE_FIREBASE_APP_ID=…
```
Server (identity verification + Firestore role read):
```
FIREBASE_PROJECT_ID=talbotiq-9cc4e
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxx@talbotiq-9cc4e.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----\n"
ADMIN_EMAILS=you@talbotiq.com   # optional admin overlay
```
Keep `FIREBASE_PRIVATE_KEY` on one line with `\n` for newlines. If the server vars
are missing the app boots, but auth-guarded APIs return 503.

### 3. Firestore rules
`firestore.rules` mirrors what's deployed on `talbotiq-9cc4e`. Deploy with
`firebase deploy --only firestore:rules`. **Never** deploy a deny-all ruleset — it
would break both clients' role reads.

---

## Files

| File | Purpose |
| --- | --- |
| `src/lib/firebase.ts` | Firebase Web SDK init (Auth + Firestore) |
| `src/features/auth/AuthProvider.tsx` | Auth context: email/pw sign-in/up, users/{uid} role stream, fetch interceptor |
| `src/features/auth/guards.tsx` | Route guards + redirects |
| `src/features/auth/LoginPage.tsx` | Email/password login + sign-up role picker |
| `src/features/candidate/CandidateHome.tsx` | Candidate's assigned-interview list |
| `server/services/firebaseAdmin.ts` | Admin SDK init; verify tokens; `getUserRole` (Firestore) |
| `server/services/users.ts` | `getUser` mirror + `isAdminEmail` overlay |
| `server/middleware/auth.ts` | `authenticate`, `requireRecruiter`, ownership/email helpers, WS auth |
| `server/routes/auth.ts` | `GET /api/auth/me` |
| `firestore.rules` | Mirror of the deployed `talbotiq-9cc4e` rules |
