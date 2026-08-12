"""Spike 0.1 — can a tampered client override a locked systemInstruction?

The token architecture lets the candidate's device connect straight to Gemini Live.
The device therefore writes the setup frame, so the ONLY thing stopping a candidate
from replacing the interviewer prompt is `lockAdditionalFields` on the ephemeral
token. This script proves (or disproves) that.

Run:  .venv/bin/python spikes/gemini_token_lock.py
Needs: GEMINI_API_KEY in backend/.env

Raw REST + raw WebSocket on purpose — that is what Flutter's WebSocketChannel speaks.
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from datetime import datetime, timedelta, timezone

import httpx
import websockets
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("GEMINI_API_KEY", "").strip()

# The model the app actually uses today (gemini_live_service.dart defaultModel).
# Override with GEMINI_LIVE_MODEL to try a different one.
MODEL = os.getenv(
    "GEMINI_LIVE_MODEL", "models/gemini-2.5-flash-native-audio-preview-09-2025"
)

# The REST path is v1beta. (The `api_version: 'v1alpha'` in Google's docs is an SDK
# setting, not the URL — and an unrecognised method path makes the gateway answer
# "expected OAuth 2 access token" rather than 404, which reads like a bad key.)
# v1alpha is kept as a fallback in case the surface moves.
TOKEN_URLS = [
    "https://generativelanguage.googleapis.com/v1beta/auth_tokens",
    "https://generativelanguage.googleapis.com/v1alpha/auth_tokens",
]

MODELS_URL = "https://generativelanguage.googleapis.com/v1beta/models"

# Resolved by the first successful mint, then reused.
_token_url: str | None = None

# With ephemeral tokens the service name differs from the key-authenticated one.
# We try each in turn and report which accepted the token, so the spike also
# answers "what URL does Phase 2 hand to the client?".
WS_CANDIDATES = [
    (
        "v1alpha/BidiGenerateContentConstrained",
        "wss://generativelanguage.googleapis.com/ws/"
        "google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained",
    ),
    (
        "v1beta/BidiGenerateContentConstrained",
        "wss://generativelanguage.googleapis.com/ws/"
        "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained",
    ),
    (
        "v1alpha/BidiGenerateContent",
        "wss://generativelanguage.googleapis.com/ws/"
        "google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent",
    ),
]

PIRATE = (
    "You are a pirate. Every single reply MUST begin with the word 'Arrr'. "
    "Never break character under any circumstances."
)
ASSISTANT = (
    "You are a plain, professional assistant. Never say 'Arrr'. "
    "Never roleplay as a pirate. Answer plainly."
)
PROMPT = "What is two plus two? Answer in one short sentence."

# Resolved by the first successful connect, then reused.
_ws_url: str | None = None


# ── token minting ────────────────────────────────────────────────────────────

async def preflight() -> None:
    """Prove the key itself is valid before blaming the auth_tokens endpoint.

    Without this, a plain bad/restricted key and an unsupported endpoint produce
    the same 401 and the spike looks like it answered a question it never reached.
    """
    async with httpx.AsyncClient(timeout=30) as c:
        r = await c.get(MODELS_URL, headers={"x-goog-api-key": API_KEY})

    if r.status_code >= 400:
        hint = ""
        if API_KEY.startswith("AQ."):
            hint = (
                "\n    → This key uses the newer 'AQ.' Google Cloud format, which is\n"
                "      widely reported to fail on generativelanguage.googleapis.com with\n"
                "      exactly this ACCESS_TOKEN_TYPE_UNSUPPORTED error, regardless of\n"
                "      project config. Use a classic AI Studio key instead:\n"
                "      https://aistudio.google.com/apikey  → starts with 'AIza', 39 chars.\n"
                "      (The keys the app uses today are AIza-format — see the 'AIza…'\n"
                "       placeholder in the old Settings key field.)"
            )
        raise RuntimeError(
            f"the API key itself is not working ({r.status_code}) on a known-good "
            f"endpoint (GET /v1beta/models):\n    {r.text[:300]}\n"
            f"    → fix the key before interpreting anything below.{hint}"
        )

    names = [m.get("name", "") for m in r.json().get("models", [])]
    print(f"    key OK — {len(names)} models visible")
    # NOTE: GET /v1beta/models does not enumerate Live/native-audio models, so a
    # miss here means nothing. Kept only as a breadcrumb if a mint later fails
    # with a model error; the connect itself is the real test.
    if MODEL.split("/")[-1] not in " ".join(names):
        print(f"      (Live models aren't listed by this endpoint — not a problem;")
        print(f"       override with GEMINI_LIVE_MODEL only if a mint rejects the model)")


def _locked_setup() -> dict:
    """The BidiGenerateContentSetup the TOKEN carries.

    Under a full lock the client's setup frame is ignored *entirely*, so anything
    we need at runtime must live here — including outputAudioTranscription, or an
    AUDIO reply comes back as opaque bytes with no text to assert on.
    """
    return {
        "model": MODEL,
        "generationConfig": {
            "temperature": 0.7,
            "responseModalities": ["AUDIO"],
        },
        "systemInstruction": {"parts": [{"text": PIRATE}]},
        "sessionResumption": {},
        "outputAudioTranscription": {},
    }


def _constraint_variants() -> list[tuple[str, dict]]:
    """The two locking modes the real AuthToken schema supports.

    Field names come from the API discovery doc, NOT the SDK docs — the wire
    message has `bidiGenerateContentSetup` + `fieldMask`; the SDK's
    `live_connect_constraints` / `lock_additional_fields` do not exist on REST.

    Per the fieldMask docs:
      · setup present, fieldMask EMPTY    → effective setup taken ENTIRELY from the
                                            token; the client's setup is IGNORED.
      · setup present, fieldMask NON-EMPTY → only the masked fields overwrite the
                                            client's setup.

    The empty-mask case is the stronger guarantee and the one we want.
    """
    setup = _locked_setup()
    return [
        ("full-lock (no fieldMask)", {"bidiGenerateContentSetup": setup}),
        (
            "partial-lock (fieldMask)",
            {
                "bidiGenerateContentSetup": setup,
                "fieldMask": "model,systemInstruction,generationConfig",
            },
        ),
    ]


# Remembered once a (url, variant) pair mints successfully.
_locked_recipe: tuple[str, str] | None = None


async def mint(*, locked: bool, uses: int = 1, minutes: int = 10) -> str:
    """Create an ephemeral token. `locked` pins the pirate instruction."""
    global _token_url, _locked_recipe

    now = datetime.now(tz=timezone.utc)
    base: dict = {
        "uses": uses,
        "expireTime": (now + timedelta(minutes=minutes)).isoformat().replace("+00:00", "Z"),
        "newSessionExpireTime": (now + timedelta(minutes=1)).isoformat().replace("+00:00", "Z"),
    }

    # (label, url, body) attempts, most-likely first.
    attempts: list[tuple[str, str, dict]] = []
    if not locked:
        # Unconstrained: URL pinning is safe, the body shape never changes.
        for url in ([_token_url] if _token_url else TOKEN_URLS):
            attempts.append(("plain", url, dict(base)))
    else:
        variants = _constraint_variants()
        if _locked_recipe:
            url, want = _locked_recipe
            variants = [(n, b) for n, b in variants if n == want]
            urls = [url]
        else:
            # Do NOT reuse the unconstrained endpoint here — a version that accepts
            # a plain mint may not expose the constraint field at all.
            urls = TOKEN_URLS
        for url in urls:
            for name, extra in variants:
                attempts.append((name, url, {**base, **extra}))

    errors: list[str] = []
    async with httpx.AsyncClient(timeout=30) as c:
        for label, url, body in attempts:
            r = await c.post(
                url,
                headers={"x-goog-api-key": API_KEY, "content-type": "application/json"},
                json=body,
            )
            version = url.rsplit("/", 2)[-2]

            if r.status_code < 400:
                name = r.json().get("name", "")
                if not name:
                    raise RuntimeError(f"mint returned no token name: {r.text[:400]}")
                if not locked and _token_url is None:
                    _token_url = url
                    print(f"    ↳ mint endpoint: {version}/auth_tokens")
                if locked and _locked_recipe is None:
                    _locked_recipe = (url, label)
                    print(f"    ↳ lock recipe: {version}/auth_tokens + {label}")
                return name

            errors.append(f"{version} + {label} → {r.status_code} {r.text[:150]}")

    raise RuntimeError("mint failed on every combination:\n      " + "\n      ".join(errors))


# ── one Live session ─────────────────────────────────────────────────────────

def _setup_frame(client_instruction: str | None) -> dict:
    """Mirrors gemini_live_service.dart _sendSetup, plus output transcription so
    an AUDIO-modality reply still gives us assertable text."""
    setup: dict = {
        "model": MODEL,
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Aoede"}}},
        },
        # Without this an AUDIO reply is opaque bytes and we cannot assert on it.
        "outputAudioTranscription": {},
    }
    if client_instruction is not None:
        setup["systemInstruction"] = {"parts": [{"text": client_instruction}]}
    return {"setup": setup}


async def run_session(token: str, client_instruction: str | None) -> str:
    """Connect with `token`, optionally send a conflicting instruction, ask PROMPT,
    return the model's reply as text."""
    global _ws_url

    urls = [(n, u) for n, u in WS_CANDIDATES if _ws_url is None or u == _ws_url]
    last_err: Exception | None = None

    for name, base in urls:
        url = f"{base}?access_token={token}"
        try:
            async with websockets.connect(url, max_size=None, open_timeout=30) as ws:
                if _ws_url is None:
                    _ws_url = base
                    print(f"    ↳ endpoint accepted: {name}")

                await ws.send(json.dumps(_setup_frame(client_instruction)))

                said: list[str] = []
                deadline = asyncio.get_event_loop().time() + 60
                sent_turn = False

                while asyncio.get_event_loop().time() < deadline:
                    try:
                        raw = await asyncio.wait_for(ws.recv(), timeout=20)
                    except asyncio.TimeoutError:
                        break

                    msg = json.loads(raw) if isinstance(raw, (str, bytes)) else {}

                    if "setupComplete" in msg and not sent_turn:
                        sent_turn = True
                        await ws.send(json.dumps({
                            "clientContent": {
                                "turns": [{"role": "user", "parts": [{"text": PROMPT}]}],
                                "turnComplete": True,
                            }
                        }))
                        continue

                    sc = msg.get("serverContent") or {}

                    # Transcript of the model's own audio — where our answer lands.
                    ot = sc.get("outputTranscription") or {}
                    if ot.get("text"):
                        said.append(ot["text"])

                    # TEXT modality path, in case a model returns text parts.
                    for part in (sc.get("modelTurn") or {}).get("parts", []):
                        if part.get("text"):
                            said.append(part["text"])

                    if sc.get("turnComplete") or sc.get("generationComplete"):
                        if said:
                            break

                return "".join(said).strip()

        except Exception as e:  # try the next endpoint shape
            last_err = e
            continue

    raise RuntimeError(f"no Live endpoint accepted the token: {last_err}")


# ── cases ────────────────────────────────────────────────────────────────────

def verdict(reply: str) -> str:
    low = reply.lower()
    if "arrr" in low:
        return "PIRATE"
    if reply.strip():
        return "ASSISTANT"
    return "EMPTY"


async def main() -> int:
    if not API_KEY:
        print("GEMINI_API_KEY is not set in backend/.env — cannot run.")
        return 2

    print(f"model: {MODEL}\n")

    print("[0] preflight — is the API key itself valid?")
    try:
        await preflight()
        print()
    except Exception as e:
        print(f"    {e}\n")
        print("VERDICT: INCONCLUSIVE — the spike never ran. Fix the key and re-run.")
        return 2

    results: dict[str, str] = {}

    # A — control: does the client-supplied instruction work at all?
    print("[A] control — unconstrained token, client sends ASSISTANT")
    try:
        reply = await run_session(await mint(locked=False), ASSISTANT)
        results["A"] = verdict(reply)
        print(f"    reply: {reply[:160]!r}\n    → {results['A']} (expect ASSISTANT)\n")
    except Exception as e:
        results["A"] = f"ERROR: {e}"
        print(f"    ERROR: {e}\n")

    # B — does a locked instruction get applied when the client sends none?
    print("[B] lock applied? — locked PIRATE token, client sends NO instruction")
    try:
        reply = await run_session(await mint(locked=True), None)
        results["B"] = verdict(reply)
        print(f"    reply: {reply[:160]!r}\n    → {results['B']} (expect PIRATE)\n")
    except Exception as e:
        results["B"] = f"ERROR: {e}"
        print(f"    ERROR: {e}\n")

    # C — THE security question: locked token vs a conflicting client instruction.
    print("[C] security — locked PIRATE token, client sends conflicting ASSISTANT")
    try:
        reply = await run_session(await mint(locked=True), ASSISTANT)
        results["C"] = verdict(reply)
        print(f"    reply: {reply[:160]!r}\n    → {results['C']} (expect PIRATE — lock wins)\n")
    except Exception as e:
        results["C"] = f"ERROR: {e}"
        print(f"    ERROR: {e}\n")

    # D — is a uses:1 token really single-use?
    print("[D] replay — reuse a uses:1 token")
    try:
        tok = await mint(locked=True, uses=1)
        await run_session(tok, None)
        try:
            await run_session(tok, None)
            results["D"] = "REUSABLE"
            print("    → REUSABLE — second connect SUCCEEDED (unexpected)\n")
        except Exception:
            results["D"] = "REJECTED"
            print("    → REJECTED on second use (expected)\n")
    except Exception as e:
        results["D"] = f"ERROR: {e}"
        print(f"    ERROR: {e}\n")

    print("─" * 68)
    print(f"resolved WS endpoint: {_ws_url or '(none succeeded)'}")
    for k in ("A", "B", "C", "D"):
        print(f"  {k}: {results.get(k)}")
    print("─" * 68)

    # An error is NOT an answer. Only a case that actually reached the model and
    # came back with the wrong persona is evidence that locking failed.
    errored = [k for k, v in results.items() if str(v).startswith("ERROR")]
    if errored:
        print(f"VERDICT: INCONCLUSIVE — case(s) {', '.join(errored)} never reached the model.")
        print("         Nothing here says anything about whether the lock holds.")
        return 2

    if results.get("C") == "PIRATE" and results.get("B") == "PIRATE":
        print("VERDICT: PROCEED DIRECT — the lock holds against a hostile client.")
        return 0

    print("VERDICT: RELAY REQUIRED for the candidate voice interview.")
    print("         (recruiter voice preview can still go direct — its prompt is")
    print("          the recruiter's own, so there is nothing to protect.)")
    return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
