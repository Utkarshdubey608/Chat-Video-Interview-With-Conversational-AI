"""Tiny, safe template rendering.

Recruiter-authored templates use `{{ variable }}` placeholders. We deliberately
do NOT use a full template engine (e.g. Jinja): recruiter input is only
semi-trusted and a full engine invites server-side template injection. This
renderer only substitutes known string values and never evaluates code.
"""

from __future__ import annotations

import re

# Variables the editor advertises and render() knows how to fill. Keep in sync
# with the "supported variables" list surfaced in the Flutter editor.
SUPPORTED_VARIABLES: dict[str, str] = {
    "candidate_name": "The candidate's name (falls back to their email).",
    "candidate_email": "The candidate's email address.",
    "interview_title": "Title of the interview / exam.",
    "interview_link": "Deep link that opens the assigned interview.",
    "recruiter_name": "Name of the recruiter sending the invite.",
    "company": "Company / organisation name.",
}

# HTML default (Gmail sends HTML nicely — matches the reference concept).
DEFAULT_SUBJECT = "You've been invited to an interview: {{ interview_title }}"
DEFAULT_BODY = """\
<!DOCTYPE html>
<html>
  <body style="font-family: Arial, sans-serif; color:#111;">
    <div style="max-width:600px;margin:auto;padding:24px;border:1px solid #e2e2e2;border-radius:10px;">
      <div style="font-size:20px;font-weight:bold;">Hi {{ candidate_name }},</div>
      <p style="line-height:1.6;margin-top:12px;">
        {{ recruiter_name }} has invited you to complete the
        <b>"{{ interview_title }}"</b> interview on {{ company }}.
      </p>
      <p style="margin:24px 0;">
        <a href="{{ interview_link }}"
           style="background:#10B981;color:#fff;text-decoration:none;padding:12px 20px;border-radius:999px;font-weight:bold;">
          Open your interview
        </a>
      </p>
      <p style="font-size:12px;color:#888;">
        Or paste this link into your browser:<br>{{ interview_link }}
      </p>
      <div style="font-size:12px;margin-top:20px;color:#888;">
        You're receiving this because {{ recruiter_name }} assigned you an interview on {{ company }}.
      </div>
    </div>
  </body>
</html>
"""

_PLACEHOLDER = re.compile(r"{{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*}}")


def render(template: str, context: dict[str, str]) -> str:
    """Replace every `{{ key }}` with context[key]; unknown keys become ''."""

    def _sub(match: re.Match[str]) -> str:
        value = context.get(match.group(1), "")
        return "" if value is None else str(value)

    return _PLACEHOLDER.sub(_sub, template)
