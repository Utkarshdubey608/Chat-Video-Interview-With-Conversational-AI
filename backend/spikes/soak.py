"""Phase 5 soak — exercise every route against the real vendors.

Run:  .venv/bin/python spikes/soak.py

Auth is bypassed (there is no signed-in user in a script), but everything below
that runs for real: real keys, real upstreams, real responses.

Deliberately NOT covered: `POST /api/tavus/conversations`. Creating a
conversation starts a billable avatar session that then has to be torn down —
not something a smoke test should do unattended. Its provider code is covered by
unit tests, and the Tavus credential is proven by the replica/persona calls.
"""

from __future__ import annotations

import io
import math
import struct
import sys
import time
import wave

from fastapi.testclient import TestClient

from app import interviews
from app.config import get_settings
from app.interviews import Interview
from app.main import create_app
from app.security import AuthedUser, require_firebase_user

PASS, FAIL, SKIP = "PASS", "FAIL", "SKIP"
results: list[tuple[str, str, str]] = []


def record(name: str, ok: bool | None, detail: str = "") -> None:
    status = SKIP if ok is None else (PASS if ok else FAIL)
    results.append((status, name, detail))
    print(f"  [{status}] {name}" + (f" — {detail}" if detail else ""))


def speech_like_wav(seconds: float = 2.0, rate: int = 16000) -> bytes:
    """A short tone as a real WAV.

    Deepgram will find no words in it — that is fine. What is under test is the
    plumbing: that raw bytes and the content type reach Deepgram with our key
    and come back as a valid response.
    """
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        frames = bytearray()
        for i in range(int(rate * seconds)):
            value = int(6000 * math.sin(2 * math.pi * 180 * i / rate))
            frames += struct.pack("<h", value)
        wav.writeframes(bytes(frames))
    return buffer.getvalue()


def build_client() -> TestClient:
    app = create_app()
    app.state.settings = get_settings()

    interview = Interview(
        id="soak-1",
        recruiter_id="rec-1",
        candidate_email_lower="candidate@example.com",
        candidate_name="Casey",
        recruiter_name="Acme",
        title="Backend Engineer",
        prompt="Keep it brief.",
        questions=["Tell me about a system you designed."],
        duration_minutes=5,
    )
    interviews.fetch = lambda _s, _id: interview
    app.dependency_overrides[require_firebase_user] = lambda: AuthedUser(
        uid="soak-user", email="candidate@example.com", claims={}
    )
    return TestClient(app)


def main() -> int:
    settings = get_settings()
    client = build_client()

    print("\n── health ───────────────────────────────────────────────")
    health = client.get("/health").json()
    record("GET /health", health.get("status") == "ok", str(health.get("providers")))

    print("\n── Tavus ────────────────────────────────────────────────")
    response = client.get("/api/tavus/replicas")
    replicas = response.json().get("data", []) if response.status_code == 200 else []
    record(
        "GET /api/tavus/replicas",
        response.status_code == 200,
        f"{len(replicas)} replica(s)" if response.status_code == 200 else response.text[:120],
    )

    response = client.get("/api/tavus/personas")
    record(
        "GET /api/tavus/personas",
        response.status_code == 200,
        f"{len(response.json().get('data', []))} persona(s)"
        if response.status_code == 200
        else response.text[:120],
    )
    record("POST /api/tavus/conversations", None, "skipped — starts a billable session")

    print("\n── Gemini ───────────────────────────────────────────────")
    response = client.post(
        "/api/gemini/generate",
        json={
            "contents": [{"parts": [{"text": 'Reply with exactly: {"ok": true}'}]}],
            "generationConfig": {
                "maxOutputTokens": 60,
                "responseMimeType": "application/json",
            },
        },
    )
    if response.status_code == 200:
        text = response.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
        leaked = settings.gemini_api_key in response.text
        record("POST /api/gemini/generate", not leaked, f"replied {text[:40]}")
    else:
        record("POST /api/gemini/generate", False, response.text[:160])

    response = client.post("/api/rt/gemini-token", json={"interview_id": "soak-1"})
    record(
        "POST /api/rt/gemini-token",
        response.status_code == 200,
        f"expires {response.json()['expiresAt']}" if response.status_code == 200 else response.text[:160],
    )

    print("\n── Deepgram ─────────────────────────────────────────────")
    audio = speech_like_wav()
    response = client.post(
        "/api/deepgram/transcribe",
        content=audio,
        headers={"Content-Type": "audio/wav"},
    )
    if response.status_code == 200:
        payload = response.json()
        channels = payload.get("results", {}).get("channels", [])
        record(
            "POST /api/deepgram/transcribe",
            True,
            f"{len(audio)} bytes accepted, {len(channels)} channel(s) returned",
        )
    else:
        record("POST /api/deepgram/transcribe", False, response.text[:160])

    print("\n── rate limiting ────────────────────────────────────────")
    limited = False
    for _ in range(settings.rate_limit_live_token + 3):
        if client.post("/api/rt/gemini-token", json={"interview_id": "soak-1"}).status_code == 429:
            limited = True
            break
    record("429 after the live-token limit", limited)

    print("\n" + "─" * 60)
    failed = [r for r in results if r[0] == FAIL]
    skipped = [r for r in results if r[0] == SKIP]
    print(f"{len(results) - len(failed) - len(skipped)} passed, {len(failed)} failed, {len(skipped)} skipped")
    for _, name, detail in failed:
        print(f"  FAILED: {name} — {detail}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
