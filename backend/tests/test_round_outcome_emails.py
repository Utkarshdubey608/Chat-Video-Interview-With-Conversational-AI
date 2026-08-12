"""The two round-outcome templates: shortlisted, and not advancing.

These are the only built-ins that tell a candidate a DECISION, so what is checked
here is not "does it render" but the two ways a bad template does real harm:

  1. A leftover `{{ placeholder }}` in a rejection email. Every variable these
     templates use has to be one the sender actually supplies.
  2. A call-to-action pointing at the round the candidate just finished — for
     someone who advanced that is a dead link, and for someone who did not it
     invites them back into a closed round.

The delivery path itself is covered by tests/test_app.py; these tests are about
the content.
"""

from __future__ import annotations

import os

os.environ.setdefault("DRY_RUN", "true")
os.environ.setdefault("API_KEY", "")

import re  # noqa: E402

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import mailer  # noqa: E402
from app.main import create_app  # noqa: E402
from app.templating import (  # noqa: E402
    BUILTIN_BY_ID,
    SUPPORTED_VARIABLES,
    render,
)

SHORTLIST = "builtin:round_shortlist"
NOT_ADVANCING = "builtin:round_not_advancing"

client = TestClient(create_app())

# What app/features/interviews/recruiter/round_notify_page.dart sends, plus the
# two the backend fills per recipient. Kept literal rather than imported so a
# variable quietly disappearing from the Flutter side fails here.
SENDER_CONTEXT = {
    "interview_title": "Backend Engineer",
    "round_title": "Résumé screen",
    "next_round": "Technical round",
    "recruiter_name": "Sam",
    "company": "Acme",
    "candidate_name": "Asha",
    "candidate_email": "asha@example.com",
}

_PLACEHOLDER = re.compile(r"{{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*}}")


@pytest.mark.parametrize("template_id", [SHORTLIST, NOT_ADVANCING])
def test_every_variable_used_is_one_the_sender_supplies(template_id):
    """A `{{ round_title }}` the sender never sets renders as an empty string —
    "Thanks for completing """ + '""' + """" in a rejection email."""
    template = BUILTIN_BY_ID[template_id]
    used = set(_PLACEHOLDER.findall(template["subject"] + template["body"]))
    missing = used - SENDER_CONTEXT.keys()
    assert not missing, f"{template_id} uses variables nobody supplies: {missing}"


@pytest.mark.parametrize("template_id", [SHORTLIST, NOT_ADVANCING])
def test_nothing_unfilled_survives_rendering(template_id):
    template = BUILTIN_BY_ID[template_id]
    for part in ("subject", "body"):
        rendered = render(template[part], SENDER_CONTEXT)
        assert "{{" not in rendered, f"{template_id} {part} left a placeholder"
        assert rendered.strip()


@pytest.mark.parametrize("template_id", [SHORTLIST, NOT_ADVANCING])
def test_no_call_to_action_back_into_the_finished_round(template_id):
    body = BUILTIN_BY_ID[template_id]["body"]
    assert "interview_link" not in body
    assert "href" not in body, "an outcome email must not link into the round"


@pytest.mark.parametrize("template_id", [SHORTLIST, NOT_ADVANCING])
def test_every_variable_is_advertised_to_the_template_editor(template_id):
    """A recruiter copying one of these into a custom template needs the
    variables listed, or they will edit around a placeholder they cannot fill."""
    template = BUILTIN_BY_ID[template_id]
    used = set(_PLACEHOLDER.findall(template["subject"] + template["body"]))
    assert used <= SUPPORTED_VARIABLES.keys()


def test_shortlist_names_the_round_the_candidate_is_going_to():
    body = render(BUILTIN_BY_ID[SHORTLIST]["body"], SENDER_CONTEXT)
    assert "Technical round" in body
    assert "Résumé screen" in body, "it should also say what they just finished"


def test_not_advancing_does_not_promise_a_next_round():
    """`next_round` is set for both sends (one context is built for the screen),
    so a rejection template that used it would tell someone they were moving on to
    the round they were just rejected from."""
    template = BUILTIN_BY_ID[NOT_ADVANCING]
    assert "next_round" not in template["subject"] + template["body"]
    body = render(template["body"], SENDER_CONTEXT)
    assert "Technical round" not in body


@pytest.mark.parametrize("template_id", [SHORTLIST, NOT_ADVANCING])
def test_send_delivers_one_mail_per_candidate(template_id):
    sent: list[dict] = []

    def _capture(settings, **kwargs):
        sent.append(kwargs)

    original, mailer.send = mailer.send, _capture
    try:
        r = client.post(
            "/api/emails/send",
            json={
                "template_id": template_id,
                "shared_context": {
                    k: v
                    for k, v in SENDER_CONTEXT.items()
                    if k not in ("candidate_name", "candidate_email")
                },
                "recipients": [
                    {"email": "asha@example.com", "name": "Asha"},
                    {"email": "bo@example.com", "name": "Bo"},
                ],
            },
        )
    finally:
        mailer.send = original

    assert r.status_code == 200, r.text
    body = r.json()
    assert (body["total"], body["sent"], body["failed"]) == (2, 2, 0)
    assert body["template_id"] == template_id

    # Each candidate is addressed by their own name, and neither mail leaks a
    # placeholder to a real inbox.
    by_email = {m["to_email"]: m for m in sent}
    assert "Asha" in by_email["asha@example.com"]["body"]
    assert "Bo" in by_email["bo@example.com"]["body"]
    assert "Asha" not in by_email["bo@example.com"]["body"]
    for mail in sent:
        assert "{{" not in mail["body"]
        assert "{{" not in mail["subject"]
