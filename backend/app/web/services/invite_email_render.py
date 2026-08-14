"""Sanitising the recruiter's WYSIWYG body — ports `server/services/inviteEmailRender.ts`.

The recruiter authors only the BODY; the shell, the interview link and the
exact-email note are injected by `app.web.shared.invite_email` and are not editable.
That body is semi-trusted HTML from a rich-text editor, so it is filtered against an
allowlist here as well as on save — defence in depth, because a body that reached
storage before a filter was tightened would otherwise be sent as-is forever.

`nh3` replaces the Express `sanitize-html`. It is an allowlist filter over the same
tag and attribute sets, so a tag absent from the list is discarded rather than escaped
— the recruiter sees their formatting drop out, not markup appear in the email.
"""

from __future__ import annotations

import re

import nh3

# Tags a recruiter can produce in the editor. Anything else is dropped.
ALLOWED_TAGS = {
    "p", "br", "strong", "em", "u", "s", "a", "ul", "ol", "li",
    "h1", "h2", "h3", "span", "div", "blockquote",
}

# `style` is allowed on the layout tags because the editor emits inline colour and
# alignment; the declarations inside it are filtered separately below.
ALLOWED_ATTRIBUTES = {
    "a": {"href", "style"},
    "span": {"style"},
    "p": {"style"},
    "div": {"style"},
    "li": {"style"},
}

# Only these schemes survive on a link. `javascript:` and `data:` are the two that
# turn an email body into an attack, and both are absent.
ALLOWED_SCHEMES = {"http", "https", "mailto"}

# The style declarations the editor legitimately produces. Everything else is
# stripped: a `style` attribute is a wide surface, and properties like `position` or
# `background-image` let a body escape its box or fetch a remote resource.
_ALLOWED_STYLE_PROPERTIES = {
    "color": re.compile(r"^(#(0x)?[0-9a-f]+|rgb\()", re.IGNORECASE),
    "background-color": re.compile(r"^(#(0x)?[0-9a-f]+|rgb\()", re.IGNORECASE),
    "text-align": re.compile(r"^(left|right|center|justify)$", re.IGNORECASE),
    "font-weight": re.compile(r"^(\d+|bold|normal)$", re.IGNORECASE),
}


def filter_style(value: str) -> str:
    """Keep only the allowed declarations from a `style` attribute.

    `nh3` allows an attribute wholesale or not at all, so the per-property filtering
    the Express sanitiser did through `allowedStyles` happens here instead. Without
    it, allowing `style` at all would allow every CSS property.
    """
    kept = []
    for declaration in (value or "").split(";"):
        if ":" not in declaration:
            continue
        prop, _, raw = declaration.partition(":")
        prop = prop.strip().lower()
        raw = raw.strip()
        pattern = _ALLOWED_STYLE_PROPERTIES.get(prop)
        if pattern and pattern.match(raw):
            kept.append(f"{prop}:{raw}")
    return ";".join(kept)


def _attribute_filter(tag: str, attribute: str, value: str) -> str | None:
    """Per-attribute filtering. Returning None drops the attribute."""
    if attribute == "style":
        filtered = filter_style(value)
        return filtered or None
    return value


def sanitize_body_html(html: str) -> str:
    """The recruiter's body, reduced to the allowlist."""
    if not html:
        return ""
    return nh3.clean(
        html,
        tags=ALLOWED_TAGS,
        attributes=ALLOWED_ATTRIBUTES,
        url_schemes=ALLOWED_SCHEMES,
        attribute_filter=_attribute_filter,
        # Off: the shared renderer already escapes every merge value it substitutes,
        # and re-escaping here would double-encode an ampersand the recruiter typed.
        strip_comments=True,
        link_rel=None,
    ).strip()


def build_invite_email(
    template: dict, variables: dict, *, interview_link: str, candidate_email: str
) -> dict:
    """Sanitise the body, then render the full email."""
    from app.web.shared import invite_email

    safe = {**template, "bodyHtml": sanitize_body_html(template.get("bodyHtml") or "")}
    return invite_email.render_invite_email(
        safe, variables, interview_link=interview_link, candidate_email=candidate_email
    )


def build_transition_email(
    template: dict,
    kind: str,
    variables: dict,
    *,
    interview_link: str | None = None,
    candidate_email: str | None = None,
) -> dict:
    """Sanitise the body, then render an advance / selection / rejection email."""
    from app.web.shared import invite_email

    safe = {**template, "bodyHtml": sanitize_body_html(template.get("bodyHtml") or "")}
    return invite_email.render_transition_email(
        safe,
        kind,
        variables,
        interview_link=interview_link,
        candidate_email=candidate_email,
    )
