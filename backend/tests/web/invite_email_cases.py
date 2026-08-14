"""The input half of the invite-email golden contract.

Kept as code rather than JSON so the cases can carry comments explaining what each
one pins. The OUTPUTS live in `contracts/invite_email.fixtures.json`, which both this
suite and the web repo's suite assert against — that file is the contract between the
Python sender and the TypeScript preview.

Adding a case is safe. Changing one means regenerating the fixtures (see
`test_web_invite_email.py`) and updating the web side to match.
"""

from __future__ import annotations

BASE_TEMPLATE = {
    "id": "tpl-1",
    "recruiterId": "uid-1",
    "name": "Default invite",
    "isDefault": True,
    "sender": {"verifiedSenderEmail": "talent@acme.test", "fromName": "Acme Talent", "replyTo": ""},
    "subject": "Interview invitation — {{role}}",
    "bodyHtml": "<p>Hi {{candidate_name}},</p><p>{{recruiter_name}} invited you.</p><p>{{interview_link}}</p>",
    "cta": {"text": "Start your interview", "color": "#6B2BE0"},
    "branding": {"companyName": "Acme", "accentColor": "#123456", "footer": "Sent via Acme."},
    "deadlineText": "",
    "createdAt": "2026-01-01T00:00:00.000Z",
    "updatedAt": "2026-01-01T00:00:00.000Z",
}

INVITE_VARS = {
    "candidate_name": "Ada",
    "role": "Backend Engineer",
    "recruiter_name": "Grace",
    "company": "Acme",
    "deadline": "Friday",
}

LINK = "https://app.test/take/abc123"
EMAIL = "ada@example.com"


def _template(**overrides) -> dict:
    return {**BASE_TEMPLATE, **overrides}


# Each case: a name, the render call to make, and its arguments. The name is the key
# in the fixtures file.
CASES: list[dict] = [
    {
        "name": "invite/basic",
        "why": "The ordinary path: body places the link itself, so no fallback CTA.",
        "call": "invite",
        "template": _template(),
        "vars": INVITE_VARS,
        "link": LINK,
        "email": EMAIL,
    },
    {
        "name": "invite/body-without-link",
        "why": (
            "The body omits {{interview_link}}, so the shell must append a CTA. An "
            "invite with no link is the one failure the candidate cannot work around."
        ),
        "call": "invite",
        "template": _template(bodyHtml="<p>Hi {{candidate_name}}, please interview.</p>"),
        "vars": INVITE_VARS,
        "link": LINK,
        "email": EMAIL,
    },
    {
        "name": "invite/html-injection-in-vars",
        "why": (
            "Merge values are candidate- and recruiter-supplied. A name containing a "
            "script tag must arrive escaped, not executed in a mail client."
        ),
        "call": "invite",
        "template": _template(),
        "vars": {
            **INVITE_VARS,
            "candidate_name": '<script>alert("x")</script>',
            "company": 'Acme " & <Co>',
            "recruiter_name": "O'Brien",
        },
        "link": LINK,
        "email": EMAIL,
    },
    {
        "name": "invite/link-with-query-and-entities",
        "why": "The link is escaped in both the CTA href and the paste-this-link line.",
        "call": "invite",
        "template": _template(),
        "vars": INVITE_VARS,
        "link": "https://app.test/take/abc?a=1&b=2",
        "email": EMAIL,
    },
    {
        "name": "invite/bad-accent-and-cta-colour",
        "why": (
            "Colours are interpolated into style attributes. A non-hex value must fall "
            "back rather than close the attribute and inject markup."
        ),
        "call": "invite",
        "template": _template(
            cta={"text": "Go", "color": 'red;"><script>x</script>'},
            branding={"companyName": "Acme", "accentColor": "not-a-colour", "footer": "F"},
        ),
        "vars": INVITE_VARS,
        "link": LINK,
        "email": EMAIL,
    },
    {
        "name": "invite/logo-branding",
        "why": "A logo replaces the wordmark; its URL and the alt text are both escaped.",
        "call": "invite",
        "template": _template(
            branding={
                "companyName": "Acme & Sons",
                "accentColor": "#6B2BE0",
                "footer": "Sent via Acme.",
                "logoUrl": "https://cdn.test/logo.png?v=2&x=1",
            }
        ),
        "vars": INVITE_VARS,
        "link": LINK,
        "email": EMAIL,
    },
    {
        "name": "invite/spaced-and-unknown-tokens",
        "why": (
            "`{{ role }}` is the same token as `{{role}}`; an unknown token stays "
            "literal so a typo is visible in the preview instead of vanishing."
        ),
        "call": "invite",
        "template": _template(
            subject="Role: {{ role }}",
            bodyHtml="<p>{{ candidate_name }} / {{typo_token}} / {{interview_link}}</p>",
        ),
        "vars": INVITE_VARS,
        "link": LINK,
        "email": EMAIL,
    },
    {
        "name": "invite/empty-branding-defaults",
        "why": "A template with no branding still renders with the product defaults.",
        "call": "invite",
        "template": _template(branding={}, cta={}),
        "vars": INVITE_VARS,
        "link": LINK,
        "email": EMAIL,
    },
    {
        "name": "advance/basic",
        "why": "Advance carries the link and the exact-email note, like an invite.",
        "call": "transition",
        "kind": "advance",
        "template": _template(
            kind="advance",
            subject="You've advanced — {{role}} ({{round_name}})",
            bodyHtml="<p>Hi {{candidate_name}}, next: {{round_name}}.</p><p>{{interview_link}}</p>",
        ),
        "vars": {
            "candidate_name": "Ada",
            "role": "Backend Engineer",
            "recruiter_name": "Grace",
            "company": "Acme",
            "round_name": "Technical",
            "previous_round_name": "Screening",
            "score": "82",
        },
        "link": LINK,
        "email": EMAIL,
    },
    {
        "name": "selected/no-link",
        "why": (
            "Terminal email: no link and no note. A link here would send the candidate "
            "back into an interview they have finished."
        ),
        "call": "transition",
        "kind": "selected",
        "template": _template(
            kind="selected",
            subject="You've been selected — {{role}}",
            bodyHtml="<p>Congratulations {{candidate_name}} — score {{score}}.</p>",
        ),
        "vars": {
            "candidate_name": "Ada",
            "role": "Backend Engineer",
            "recruiter_name": "Grace",
            "company": "Acme",
            "score": "91",
        },
        "link": None,
        "email": None,
    },
    {
        "name": "rejection/no-link",
        "why": "Terminal email, and the CTA text is empty in the default rejection.",
        "call": "transition",
        "kind": "rejection",
        "template": _template(
            kind="rejection",
            subject="Update on your {{role}} application",
            bodyHtml="<p>Hi {{candidate_name}}, thank you for your time.</p>",
            cta={"text": "", "color": "#6B2BE0"},
        ),
        "vars": {
            "candidate_name": "Ada",
            "role": "Backend Engineer",
            "recruiter_name": "Grace",
            "company": "Acme",
        },
        "link": None,
        "email": None,
    },
    {
        "name": "advance/link-omitted-from-body",
        "why": "The fallback CTA applies to advance emails too.",
        "call": "transition",
        "kind": "advance",
        "template": _template(kind="advance", bodyHtml="<p>Next round: {{round_name}}.</p>"),
        "vars": {
            "candidate_name": "Ada",
            "role": "Backend Engineer",
            "recruiter_name": "Grace",
            "company": "Acme",
            "round_name": "Final",
        },
        "link": LINK,
        "email": EMAIL,
    },
]


def render_case(case: dict) -> dict:
    """Run one case through the renderer. Used to generate and to verify."""
    from app.web.shared import invite_email

    if case["call"] == "invite":
        return invite_email.render_invite_email(
            case["template"],
            case["vars"],
            interview_link=case["link"],
            candidate_email=case["email"],
        )
    return invite_email.render_transition_email(
        case["template"],
        case["kind"],
        case["vars"],
        interview_link=case["link"],
        candidate_email=case["email"],
    )
