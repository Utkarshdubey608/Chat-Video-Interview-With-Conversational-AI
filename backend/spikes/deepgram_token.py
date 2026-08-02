"""Spike 0.2 — can a browser open Deepgram's streaming socket with a temp token?

Native Dart can set `Authorization: Bearer <jwt>`, but Flutter web is a build target
and WebSocketChannel.connect(uri) cannot set headers there. Deepgram's docs say to use
Sec-WebSocket-Protocol instead but don't give the exact array — so we try each form.

Also verifies the claim that matters most for design: the socket survives token
expiry, meaning a short TTL covers an arbitrarily long interview with no refresh loop.

Run:  .venv/bin/python spikes/deepgram_token.py
Needs: DEEPGRAM_API_KEY in backend/.env
"""

from __future__ import annotations

import asyncio
import json
import math
import os
import struct
import sys

import httpx
import websockets
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("DEEPGRAM_API_KEY", "").strip()

GRANT_URL = "https://api.deepgram.com/v1/auth/grant"
LISTEN_URL = (
    "wss://api.deepgram.com/v1/listen"
    "?model=nova-3&encoding=linear16&sample_rate=16000&channels=1"
)

SAMPLE_RATE = 16000


def pcm16_tone(seconds: float, freq: int = 220) -> bytes:
    """A quiet sine tone. Deepgram won't transcribe words from it — we're testing
    that the socket opens and stays open, not accuracy."""
    frames = int(SAMPLE_RATE * seconds)
    return b"".join(
        struct.pack("<h", int(3000 * math.sin(2 * math.pi * freq * i / SAMPLE_RATE)))
        for i in range(frames)
    )


async def preflight() -> None:
    """Prove the key works at all, so a scope problem doesn't look like a bad key.

    /v1/auth/grant needs a key with Member or higher; a usage-only key returns
    403 FORBIDDEN 'Insufficient permissions.' — which says nothing about whether
    the key is valid.
    """
    async with httpx.AsyncClient(timeout=30) as c:
        r = await c.get(
            "https://api.deepgram.com/v1/projects",
            headers={"Authorization": f"Token {API_KEY}"},
        )

    if r.status_code == 200:
        projects = r.json().get("projects", [])
        print(f"    key OK — {len(projects)} project(s) visible")
        for p in projects[:3]:
            print(f"      · {p.get('name')} ({p.get('project_id')})")
        return

    if r.status_code == 403:
        print(f"    key is VALID but cannot list projects (403) — it is scoped below Member.")
        return

    raise RuntimeError(
        f"the API key itself is not working ({r.status_code}) on GET /v1/projects:\n"
        f"    {r.text[:300]}\n    → fix the key before interpreting anything below."
    )


async def grant(ttl: int | None = None) -> dict:
    body = {} if ttl is None else {"ttl_seconds": ttl}
    async with httpx.AsyncClient(timeout=30) as c:
        r = await c.post(
            GRANT_URL,
            headers={"Authorization": f"Token {API_KEY}", "content-type": "application/json"},
            json=body,
        )
    if r.status_code == 403:
        raise RuntimeError(
            "grant failed 403 'Insufficient permissions' — /v1/auth/grant requires an "
            "API key with the Member role or higher.\n"
            "      This key can call /v1/listen but cannot mint tokens.\n"
            "      → Deepgram console → Settings → API Keys → create a key with role\n"
            "        Member (or above), put it in DEEPGRAM_API_KEY, and re-run.\n"
            "      Note: only the BACKEND ever holds this key — the app receives a\n"
            "      short-lived JWT, never the key itself."
        )
    if r.status_code >= 400:
        raise RuntimeError(f"grant failed {r.status_code}: {r.text[:300]}")
    return r.json()


async def try_connect(*, headers=None, subprotocols=None, hold: float = 2.0) -> str:
    """Open the socket, stream a little audio, return 'OK' or a failure reason."""
    kwargs: dict = {"open_timeout": 20, "max_size": None}
    if headers:
        kwargs["additional_headers"] = headers
    if subprotocols:
        kwargs["subprotocols"] = subprotocols

    try:
        async with websockets.connect(LISTEN_URL, **kwargs) as ws:
            chunk = pcm16_tone(0.1)
            end = asyncio.get_event_loop().time() + hold
            while asyncio.get_event_loop().time() < end:
                await ws.send(chunk)
                await asyncio.sleep(0.1)
            await ws.send(json.dumps({"type": "CloseStream"}))
            return "OK"
    except Exception as e:
        return f"FAIL — {type(e).__name__}: {str(e)[:140]}"


async def expiry_survival(ttl: int = 10, hold: float = 40.0) -> str:
    """Mint a deliberately short token, connect, then keep streaming well past
    expiry. If the stream survives, no refresh loop is ever needed."""
    tok = (await grant(ttl))["access_token"]
    try:
        async with websockets.connect(
            LISTEN_URL,
            additional_headers={"Authorization": f"Bearer {tok}"},
            open_timeout=20,
            max_size=None,
        ) as ws:
            chunk = pcm16_tone(0.1)
            end = asyncio.get_event_loop().time() + hold
            while asyncio.get_event_loop().time() < end:
                await ws.send(chunk)
                await asyncio.sleep(0.1)
            # Still writable this far past a 10s TTL?
            await ws.send(json.dumps({"type": "CloseStream"}))
            return f"OK — alive {hold:.0f}s on a {ttl}s token"
    except Exception as e:
        return f"FAIL — {type(e).__name__}: {str(e)[:140]}"


async def main() -> int:
    if not API_KEY:
        print("DEEPGRAM_API_KEY is not set in backend/.env — cannot run.")
        return 2

    print("[0] preflight — is the API key itself valid?")
    try:
        await preflight()
        print()
    except Exception as e:
        print(f"    {e}\n")
        return 2

    print("[1] mint — POST /v1/auth/grant")
    try:
        default = await grant()
        print(f"    default ttl → expires_in={default.get('expires_in')}")
        long_tok = await grant(3600)
        print(f"    ttl_seconds=3600 → expires_in={long_tok.get('expires_in')}")
        token = long_tok["access_token"]
        print(f"    token: {token[:24]}…\n")
    except Exception as e:
        print(f"    ERROR: {e}")
        return 2

    results: dict[str, str] = {}

    print("[2] header auth (native path) — Authorization: Bearer <jwt>")
    results["header"] = await try_connect(headers={"Authorization": f"Bearer {token}"})
    print(f"    → {results['header']}\n")

    print("[3] subprotocol auth (web path) — which array does Deepgram accept?")
    for label, protos in (
        ("['bearer', jwt]", ["bearer", token]),
        ("['token', jwt]", ["token", token]),
    ):
        # A token is single-use-ish per connection attempt in some configs; mint
        # a fresh one per variant so a failure is about the FORM, not reuse.
        fresh = (await grant(3600))["access_token"]
        protos = [protos[0], fresh]
        results[label] = await try_connect(subprotocols=protos)
        print(f"    {label:18} → {results[label]}")
    print()

    print("[4] expiry survival — 10s token, stream for 40s")
    results["expiry"] = await expiry_survival()
    print(f"    → {results['expiry']}\n")

    print("─" * 68)
    for k, v in results.items():
        print(f"  {k}: {v}")
    print("─" * 68)

    web_ok = [k for k in ("['bearer', jwt]", "['token', jwt]") if results.get(k) == "OK"]
    if web_ok:
        print(f"WEB PATH: use subprotocols {web_ok[0]} in deepgram_service.dart")
    else:
        print("WEB PATH: no subprotocol form worked — Flutter WEB needs a relay for")
        print("          Deepgram (native/mobile can still go direct via the header).")
        print("          Confirm in a real browser with serve_web_spike.py before")
        print("          committing to that — Python and browsers negotiate differently.")

    if results.get("expiry", "").startswith("OK"):
        print("TTL: socket survives expiry — a 60s token covers any interview length.")

    return 0 if results.get("header") == "OK" else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
