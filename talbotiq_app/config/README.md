# Build configuration

The backend URL is a **build-time** value, not a Settings field. A URL a user can
retype is a URL an attacker can point at their own server — and that server would
receive the Firebase ID token the app attaches to every request.

Pass it with `--dart-define-from-file` so nobody has to remember the flags:

```bash
flutter run   --dart-define-from-file=config/dev.json
flutter build apk --dart-define-from-file=config/prod.json
```

| File | Committed? | Use |
| --- | --- | --- |
| `dev.json` | yes | local backend, safe defaults |
| `prod.json` | **no** (gitignored) | your real deployed URL |

Copy `prod.example.json` to `prod.json` and fill in the URL when you deploy.

## Running against a local backend

```bash
cd backend && .venv/bin/uvicorn app.main:app --reload   # → :8000
```

`dev.json` omits `BACKEND_BASE_URL` entirely, which makes the app fall back to a
per-platform localhost default:

| Target | Resolves to | Why |
| --- | --- | --- |
| Desktop, iOS simulator, web | `http://localhost:8000` | shares the host's loopback |
| Android **emulator** | `http://10.0.2.2:8000` | `localhost` on an emulator is the emulated device, not your machine |
| Physical device | — **needs an explicit URL** | it can reach neither of the above |

For a phone on the same Wi-Fi, pass your machine's LAN address and bind uvicorn
to all interfaces:

```bash
cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
flutter run --dart-define=BACKEND_BASE_URL=http://192.168.1.42:8000
```

> Android and iOS block plaintext HTTP by default. `http://` works to
> `localhost`/`10.0.2.2` in a debug build, but a LAN IP may need a
> network-security exception — or just use HTTPS via a tunnel (`ngrok`, `cloudflared`).

## Release builds

A release build with no `BACKEND_BASE_URL` does **not** silently fall back to
localhost. `BackendConfig.isConfigured` is false and calls fail with instructions,
so a misconfigured build is obvious immediately rather than at the first
interview.
