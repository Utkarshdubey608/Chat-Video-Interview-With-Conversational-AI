"""End-to-end HTTP walkthrough against a running server, with a real Firebase ID token.

`live_smoke.py` proves the vendors answer. This proves the *surface* works: real auth on
real routes, a recruiter creating a template and a session, a candidate answering it, and
the ownership boundary actually refusing a stranger.

    .venv/bin/python -m uvicorn app.main:app --port 8791 &
    .venv/bin/python scripts/live_e2e.py --base http://127.0.0.1:8791

Everything it creates it deletes. It signs in as two throwaway UIDs — a recruiter and an
unrelated second recruiter used only to prove cross-tenant reads are refused.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
import uuid
from dataclasses import dataclass, field

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent))

import httpx  # noqa: E402

from app.config import Settings  # noqa: E402

WEB_API_KEY = "AIzaSyAF1O1SoXKv5iZ1RMaXQurVYwRSoT4ynqY"  # public client key for talbotiq-9cc4e

PASS, FAIL = "PASS", "FAIL"


@dataclass
class Step:
    name: str
    status: str
    detail: str = ""
    notes: list[str] = field(default_factory=list)


def id_token_for(uid: str, claims: dict) -> str:
    """A real Firebase ID token, the way a browser would end up holding one."""
    import firebase_admin.auth as fa

    from app import firebase

    settings = Settings()
    firebase.ensure_app(settings)
    custom = fa.create_custom_token(uid, claims)
    response = httpx.post(
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key={WEB_API_KEY}",
        json={"token": custom.decode(), "returnSecureToken": True},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["idToken"]


async def run(base: str) -> list[Step]:
    steps: list[Step] = []
    created: list[tuple[str, str]] = []  # (kind, id) for teardown

    recruiter_uid = f"e2e-recruiter-{uuid.uuid4().hex[:8]}"
    stranger_uid = f"e2e-stranger-{uuid.uuid4().hex[:8]}"
    recruiter = id_token_for(recruiter_uid, {"role": "recruiter"})
    stranger = id_token_for(stranger_uid, {"role": "recruiter"})

    auth = {"Authorization": f"Bearer {recruiter}"}
    other = {"Authorization": f"Bearer {stranger}"}

    async with httpx.AsyncClient(base_url=base, timeout=120) as client:

        def record(name: str, ok: bool, detail: str, notes: list[str] | None = None) -> bool:
            steps.append(Step(name, PASS if ok else FAIL, detail, notes or []))
            print(f"  {'✓' if ok else '✗'} {name}: {detail}", flush=True)
            return ok

        # ── auth is actually enforced ────────────────────────────────────────
        r = await client.get("/api/web/templates")
        record("unauthenticated is refused", r.status_code == 401, f"→ {r.status_code}")

        r = await client.get("/api/web/templates", headers={"Authorization": "Bearer garbage"})
        record("a forged token is refused", r.status_code == 401, f"→ {r.status_code}")

        r = await client.get("/api/web/auth/me", headers=auth)
        me = r.json() if r.status_code == 200 else {}
        record(
            "a real ID token is accepted",
            r.status_code == 200 and me.get("uid") == recruiter_uid,
            f"→ {r.status_code} uid={me.get('uid')} admin={me.get('admin')}",
        )

        # ── recruiter creates a question set, then a template that uses it ───
        # Templates reference a set by id rather than carrying questions inline, which
        # is the Express shape too — a set is reusable across templates.
        r = await client.post(
            "/api/web/question-sets",
            headers=auth,
            json={
                "name": "Live smoke set",
                "questions": [
                    {"text": "What does idempotent mean?"},
                    {"text": "Describe a race condition you have fixed."},
                ],
            },
        )
        qset = r.json() if r.status_code in (200, 201) else {}
        set_id = qset.get("id", "")
        if record(
            "create a question set",
            bool(set_id) and len(qset.get("questions", [])) == 2,
            f"→ {r.status_code} id={set_id or r.text[:120]} questions={len(qset.get('questions', []))}",
        ):
            created.append(("question-sets", set_id))

        payload = {
            "name": "Live smoke template",
            "role": "Live Smoke Engineer",
            "track": "chat",
            "questionSource": "fixed",
            "fixedQuestionSetId": set_id,
            "timing": {"numberOfQuestions": 2, "prepSeconds": 15, "answerSeconds": 60},
        }
        r = await client.post("/api/web/templates", headers=auth, json=payload)
        template = r.json() if r.status_code in (200, 201) else {}
        template_id = template.get("id", "")
        if record(
            "create a template",
            bool(template_id),
            f"→ {r.status_code} id={template_id or r.text[:120]}",
        ):
            created.append(("templates", template_id))

        r = await client.get(f"/api/web/templates/{template_id}", headers=auth)
        got = r.json() if r.status_code == 200 else {}
        record(
            "read it back",
            got.get("role") == payload["role"] and got.get("fixedQuestionSetId") == set_id,
            f"→ {r.status_code} role={got.get('role')!r} set={got.get('fixedQuestionSetId') == set_id}",
        )

        # ── a session on that template ───────────────────────────────────────
        r = await client.post(
            "/api/web/sessions",
            headers=auth,
            json={"templateId": template_id, "candidate": {"name": "Ada Lovelace", "email": "ada@example.test"}},
        )
        session = r.json() if r.status_code in (200, 201) else {}
        session_id = session.get("id", "")
        if record(
            "create a session",
            bool(session_id),
            f"→ {r.status_code} id={session_id or r.text[:160]}",
        ):
            created.append(("sessions", session_id))

        # ── the ownership boundary ───────────────────────────────────────────
        r = await client.get(f"/api/web/sessions/{session_id}/state", headers=other)
        record(
            "a stranger cannot read the session",
            r.status_code in (403, 404),
            f"→ {r.status_code} (404 preferred — it leaks no existence)",
        )

        r = await client.get("/api/web/sessions/mine", headers=other)
        mine = r.json() if r.status_code == 200 else []
        rows = mine if isinstance(mine, list) else mine.get("sessions", [])
        record(
            "a stranger's list does not include it",
            all(s.get("id") != session_id for s in rows),
            f"→ {r.status_code}, {len(rows)} row(s), none of them ours",
        )

        # ── the interview runs ───────────────────────────────────────────────
        r = await client.get(f"/api/web/sessions/{session_id}/state", headers=auth)
        state = r.json() if r.status_code == 200 else {}
        record("read session state", r.status_code == 200, f"→ {r.status_code} phase={state.get('phase')}")

        r = await client.post(f"/api/web/sessions/{session_id}/begin", headers=auth, json={})
        began = r.json() if r.status_code == 200 else {}
        record("begin the interview", r.status_code in (200, 201, 204), f"→ {r.status_code}")

        # The question ids are generated server-side, so ask the session which question
        # it is actually on rather than assuming.
        r = await client.get(f"/api/web/sessions/{session_id}/state", headers=auth)
        live = r.json() if r.status_code == 200 else {}
        current = live.get("question") or {}
        question_id = current.get("id") or ""
        progress = live.get("progress") or {}
        record(
            "the session reports a current question",
            bool(question_id) and progress.get("total") == 2,
            f"→ phase={live.get('phase')} q{progress.get('current')}/{progress.get('total')} "
            f"remaining={live.get('remainingSeconds')}s text={current.get('text')!r}",
        )

        # Answers are refused during prep — that is the timing engine working, not a
        # fault, so skip prep the way the Start answering button does.
        r = await client.post(f"/api/web/sessions/{session_id}/skip-prep", headers=auth, json={})
        after = r.json() if r.status_code == 200 else {}
        record(
            "skip prep moves to the answer phase",
            after.get("phase") == "answer",
            f"→ {r.status_code} phase={after.get('phase')} remaining={after.get('remainingSeconds')}s",
        )

        r = await client.post(
            f"/api/web/sessions/{session_id}/answers",
            headers=auth,
            json={
                "questionId": question_id,
                "text": "An idempotent operation can be applied repeatedly without changing "
                        "the result beyond the first application.",
            },
        )
        record("submit an answer", r.status_code in (200, 201, 204), f"→ {r.status_code} {r.text[:100]}")

        # ── analytics and the board read without error ───────────────────────
        for path, label in [
            ("/api/web/analytics", "analytics"),
            ("/api/web/pipelines", "pipelines"),
            ("/api/web/question-sets", "question sets"),
            ("/api/web/settings", "settings"),
            ("/api/web/voices", "voice catalog"),
            ("/api/web/invite-email-templates", "invite email templates"),
        ]:
            r = await client.get(path, headers=auth)
            record(label, r.status_code == 200, f"→ {r.status_code}")

        # ── the token routes the frontend now depends on ─────────────────────
        r = await client.post("/api/web/help/tts-token", headers=auth, json={"text": "hello", "lang": "en"})
        grant = r.json() if r.status_code == 200 else {}
        record(
            "help TTS token mints",
            bool(grant.get("token")) and "generativelanguage" in grant.get("wsUrl", ""),
            f"→ {r.status_code} token={len(grant.get('token', ''))}ch",
        )

        r = await client.post(
            "/api/rt/gemini-preview-token",
            headers=auth,
            json={"voice_name": "Aoede", "sample_text": "Testing one two."},
        )
        preview = r.json() if r.status_code == 200 else {}
        record(
            "voice preview token mints (common surface)",
            bool(preview.get("token")),
            f"→ {r.status_code} token={len(preview.get('token', ''))}ch",
        )

        # ── the mobile surface is untouched ──────────────────────────────────
        r = await client.get("/health")
        record("the mobile surface still answers", r.status_code == 200, f"→ {r.status_code}")

        # ── error shape ──────────────────────────────────────────────────────
        r = await client.get("/api/web/templates/does-not-exist", headers=auth)
        body = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
        record(
            "404 uses the {error, detail} shape the client parses",
            r.status_code == 404 and "error" in body,
            f"→ {r.status_code} keys={sorted(body)}",
        )

        # ── teardown ─────────────────────────────────────────────────────────
        # Sessions have no DELETE route — Express has none either, so this is parity,
        # not a gap. Anything the API cannot remove is removed from Firestore directly,
        # along with the default invite template the recruiter's first list seeded.
        removed = 0
        for kind, ident in reversed(created):
            r = await client.delete(f"/api/web/{kind}/{ident}", headers=auth)
            if r.status_code in (200, 204):
                removed += 1

        import asyncio as _asyncio

        from app import firebase

        db = await _asyncio.to_thread(firebase.get_db, Settings())

        def _purge() -> int:
            n = 0
            for ident in (session_id,):
                if ident:
                    db.collection("web_sessions").document(ident).delete()
                    db.collection("web_reports").document(ident).delete()
                    n += 1
            for uid in (recruiter_uid, stranger_uid):
                for doc in db.collection("web_invite_email_templates").where(
                    "recruiterId", "==", uid
                ).stream():
                    doc.reference.delete()
                    n += 1
            return n

        removed += await _asyncio.to_thread(_purge)
        print(f"\n  cleaned up {removed} object(s)")

    return steps


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="http://127.0.0.1:8791")
    opts = parser.parse_args()

    print(f"Driving {opts.base} with a real Firebase ID token.\n")
    steps = asyncio.run(run(opts.base))

    failed = [s for s in steps if s.status == FAIL]
    print("\n" + "═" * 78)
    print(f"{len(steps) - len(failed)} passed, {len(failed)} failed")
    for s in failed:
        print(f"  ✗ {s.name}: {s.detail}")
    print("═" * 78)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
