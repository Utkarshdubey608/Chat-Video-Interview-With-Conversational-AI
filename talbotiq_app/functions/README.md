# TalbotIQ secure AI proxy (Cloud Functions)

This backend removes **client-side secrets** (audit C1/C7). Candidate devices no
longer read `recruiter_keys/*` or call Tavus/Gemini directly — they call these
functions, which read keys with the Admin SDK server-side and return only the
result. Keys never leave the backend.

## Endpoints (contract mirrored by `lib/core/security/*`)

| Route | Body | Returns | Auth |
|---|---|---|---|
| `POST /createConversation` | `{ interviewId }` | `{ conversationId, conversationUrl }` | assigned candidate or owning recruiter |
| `POST /scoreInterview` | `{ interviewId, transcript }` | `{ result }` (also written server-side, unpublished) | assigned candidate or owning recruiter |
| `POST /saveRecruiterKeys` | `{ keys: {...} }` | `{ ok: true }` | recruiter (own doc) |

All require header `Authorization: Bearer <firebaseIdToken>`.

## Deploy (the marked TODO)

```bash
cd functions
npm install
firebase deploy --only functions
```

Then, in the Flutter app build:

```bash
flutter run \
  --dart-define=USE_SECURE_BACKEND=true \
  --dart-define=FUNCTIONS_BASE_URL=https://<region>-<project>.cloudfunctions.net
```

Finally, **tighten `firestore.rules`**: change the `recruiter_keys/{recruiterId}`
read rule from `allow read: if isSignedIn();` to owner-only
(`allow read: if isSignedIn() && request.auth.uid == recruiterId;`) — the proxy
no longer needs candidate reads. See the `TARGET STATE` note in `firestore.rules`.

## TODO before production
- Port the exact scoring prompt + response schema from
  `lib/core/services/gemini_service.dart` into `buildScoringPrompt` so scores
  match the client's format.
- Add App Check enforcement and per-user rate limiting.
- Add structured logging without PII/secrets.
