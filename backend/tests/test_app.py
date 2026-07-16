"""End-to-end smoke tests. DRY_RUN (no network), a throwaway SQLite file, and
the in-app worker pool disabled (WORKER_CONCURRENCY=0) so we drive the queue
deterministically via worker.process_next()."""

from __future__ import annotations

import asyncio
import os

_DB = "./test_mailer.db"
os.environ["DATABASE_URL"] = f"sqlite:///{_DB}"
os.environ["DRY_RUN"] = "true"
os.environ["API_KEY"] = ""
os.environ["WORKER_CONCURRENCY"] = "0"  # no background workers during tests

if os.path.exists(_DB):
    os.remove(_DB)

from fastapi.testclient import TestClient  # noqa: E402

from app.config import get_settings  # noqa: E402
from app.db import init_db  # noqa: E402
from app.main import app  # noqa: E402
from app.queue import worker  # noqa: E402

init_db()  # lifespan isn't triggered without the context manager; create tables
client = TestClient(app)


def _drain_queue() -> None:
    async def run() -> None:
        settings = get_settings()
        # Bounded so a bug can't loop forever.
        for _ in range(100):
            if not await worker.process_next(settings):
                break

    asyncio.run(run())


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_builtin_defaults():
    r = client.get("/api/templates/defaults")
    assert r.status_code == 200
    data = r.json()
    assert "{{ interview_title }}" in data["subject"]
    assert "candidate_name" in data["variables"]


def test_template_crud_and_single_default():
    a = client.post(
        "/api/templates",
        json={"recruiter_id": "rec1", "name": "A", "subject": "Hi {{ candidate_name }}",
              "body": "Link {{ interview_link }}", "is_default": True},
    )
    assert a.status_code == 201, a.text
    b = client.post(
        "/api/templates",
        json={"recruiter_id": "rec1", "name": "B", "is_default": True},
    )
    assert b.status_code == 201

    rows = client.get("/api/templates", params={"recruiter_id": "rec1"}).json()
    defaults = [r for r in rows if r["is_default"]]
    assert len(defaults) == 1 and defaults[0]["id"] == b.json()["id"]

    upd = client.put(f"/api/templates/{a.json()['id']}", json={"name": "A2"})
    assert upd.status_code == 200 and upd.json()["name"] == "A2"

    d = client.delete(f"/api/templates/{a.json()['id']}")
    assert d.status_code == 204


def test_enqueue_then_workers_deliver():
    # API responds immediately with 202 and everything queued.
    r = client.post(
        "/api/emails/send",
        json={
            "recruiter_id": "rec1",
            "subject": "Invite: {{ interview_title }}",
            "body": "Hi {{ candidate_name }}, open {{ interview_link }}",
            "shared_context": {"interview_title": "Backend Screen"},
            "recipients": [
                {"email": "ada@example.com", "name": "Ada",
                 "context": {"interview_link": "talbotiq://interview/x1"}},
                {"email": "grace@example.com",
                 "context": {"interview_link": "talbotiq://interview/x2"}},
            ],
        },
    )
    assert r.status_code == 202, r.text
    batch_id = r.json()["batch_id"]
    assert r.json()["queued"] == 2

    # Before workers run: all still queued.
    pre = client.get(f"/api/emails/batches/{batch_id}").json()
    assert pre["queued"] == 2 and pre["sent"] == 0

    _drain_queue()

    post = client.get(f"/api/emails/batches/{batch_id}").json()
    assert post["sent"] == 2, post
    assert post["queued"] == 0 and post["failed"] == 0
    assert {j["to_email"] for j in post["jobs"]} == {"ada@example.com", "grace@example.com"}


def test_multiple_recruiters_share_queue():
    r1 = client.post("/api/emails/send", json={
        "recruiter_id": "recA", "subject": "s", "body": "b",
        "recipients": [{"email": "a@x.com"}]})
    r2 = client.post("/api/emails/send", json={
        "recruiter_id": "recB", "subject": "s", "body": "b",
        "recipients": [{"email": "b@x.com"}]})
    assert r1.status_code == 202 and r2.status_code == 202

    _drain_queue()

    assert client.get(f"/api/emails/batches/{r1.json()['batch_id']}").json()["sent"] == 1
    assert client.get(f"/api/emails/batches/{r2.json()['batch_id']}").json()["sent"] == 1
