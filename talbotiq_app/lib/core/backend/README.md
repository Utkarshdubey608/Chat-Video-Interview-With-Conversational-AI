# `lib/core/backend/` — secure-backend client layer

Additive, production-grade scaffolding for the future secure backend (Firebase
Cloud Functions / Cloud Run). It mirrors the website contract at
`talbotiq-platform/shared/types.ts` so the Flutter app and the web client
interoperate on the same JSON.

**Status: NOT wired into any screen.** Every gateway is guarded behind
`GatewayConfig.useSecureBackend`. Until the backend is deployed, calling a
gateway method throws:

```
StateError('Backend not configured — deploy functions/ and set FUNCTIONS_BASE_URL')
```

## Layout

| File | Responsibility |
| --- | --- |
| `backend_client.dart` | Thin auth+JSON client over `core/net/ApiClient`. Builds the base URL from `GatewayConfig.functionsBaseUrl`, attaches `Authorization: Bearer <Firebase ID token>`, exposes `getJson` / `postJson`, throws `ApiException`. |
| `dtos.dart` | Null-safe DTOs (`fromJson`/`toJson`) mirroring `shared/types.ts` field names. |
| `gateways/*.dart` | One abstract interface + one `Http*` implementation per domain. |

### Gateways & contract methods

- `InviteGateway` — `extractCandidates(fileBytes, fileName) -> ExtractCandidatesResult`, `createInvites(CreateInvitesRequest) -> CreateInvitesResult`
- `SessionGateway` — `createSession`, `getCandidateState`, `submitAnswer`, `saveDraft`, `avatarStart -> AvatarStartResponse`
- `ScoringGateway` — `scoreInterview(interviewId, transcript) -> result map`
- `AnalyticsGateway` — `fetch(AnalyticsFilters) -> AnalyticsSummary`
- `VoiceGateway` — `catalog() -> VoiceCatalog`

## How this wires up once the backend is deployed

1. Deploy `functions/` (Cloud Functions / Cloud Run) exposing the `/api/*` routes.
2. Build with the two dart-defines:
   ```
   flutter build --dart-define=USE_SECURE_BACKEND=true \
                 --dart-define=FUNCTIONS_BASE_URL=https://<region>-<project>.cloudfunctions.net
   ```
3. Construct once (e.g. in a DI/service locator) and inject into repositories:
   ```dart
   final client = BackendClient();                 // uses FirebaseAuth.instance + ApiClient
   final invites = HttpInviteGateway(client);
   final sessions = HttpSessionGateway(client);
   final scoring = HttpScoringGateway(client);
   final analytics = HttpAnalyticsGateway(client);
   final voices = HttpVoiceGateway(client);
   ```
4. Replace the transitional client-direct paths in the existing repositories/
   screens with calls to these gateways (done in a later, separate step).

Errors surface as `ApiException` (transport / non-2xx) — check `isAuthError`
(401/403) and `isTransient` (timeout/429/5xx) to drive UI. When the backend is
still unconfigured you get a `StateError` with the message above.

## `TODO(deploy)` checklist

Grep: `grep -rn "TODO(deploy)" lib/core/backend`

- `backend_client.dart:41` — base URL resolves from `GatewayConfig.functionsBaseUrl` (empty until dart-define is set).
- `backend_client.dart:83` — set `FUNCTIONS_BASE_URL` (guarded `StateError` while empty).
- `gateways/invite_gateway.dart` — confirm extract accepts base64-in-JSON vs. multipart; verify `POST /api/invites` path + recruiter auth; flip `USE_SECURE_BACKEND`.
- `gateways/session_gateway.dart` — confirm `POST /api/sessions`, `GET /api/sessions/:id`, `POST /api/sessions/:id/answer`, `POST /api/sessions/:id/draft`, `POST /api/sessions/:id/avatar/start` paths + response shapes; flip `USE_SECURE_BACKEND`.
- `gateways/scoring_gateway.dart` — confirm the scoring path (`POST /api/sessions/:id/score`) + `ResultReport` shape; flip `USE_SECURE_BACKEND`.
- `gateways/analytics_gateway.dart` — confirm `GET /api/analytics` query params + `AnalyticsSummary`; flip `USE_SECURE_BACKEND`.
- `gateways/voice_gateway.dart` — confirm `GET /api/voices` returns `VoiceCatalog`; flip `USE_SECURE_BACKEND`.

Also update `GatewayConfig` (`useSecureBackend` / `functionsBaseUrl` carry their
own `TODO(backend)` markers) and tighten the `recruiter_keys` Firestore read
rule once no raw keys are read on-device.
