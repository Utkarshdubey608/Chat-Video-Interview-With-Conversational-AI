"""Request/response models for the web surface.

Separate from `app.schemas` on purpose. Those models are the mobile/desktop
contract and some of them are snake_case, which the Flutter app parses by literal
key (`json['is_html']`, `json['template_id']`). Everything here is camelCase,
because it is the web frontend's contract and its TypeScript types are camelCase.

Never add a web-only field to `app.schemas`, and never "fix" a common-surface
model's casing to match these — see this package's README.

Models live at module scope. They have to: `from __future__ import annotations`
makes a route's parameter annotation a string that FastAPI resolves against
MODULE globals, so a model defined inside a function is silently treated as a
plain body field instead.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class WebModel(BaseModel):
    """Base for every model here.

    `populate_by_name` lets a model validate from either the field name or its
    alias, which matters where a ported payload uses a name that is a Python
    keyword or a builtin.
    """

    model_config = ConfigDict(populate_by_name=True)


# ── auth ──────────────────────────────────────────────────────────────────────


class AppUser(WebModel):
    """The signed-in user, as `GET /api/web/auth/me` returns it.

    `role` is NOT decided by this endpoint: it is read from Firestore
    `users/{uid}.role`, the same document the web client and the Flutter app write
    at sign-up. Nothing a client sends here can change it.
    """

    uid: str
    email: str
    role: str
    # A recruiter with elevated visibility, derived purely from the server-side
    # ADMIN_EMAILS allowlist plus the token's verified email. Never taken from the
    # client, and not a role.
    admin: bool = False
    displayName: str | None = None
    emailVerified: bool = False
    status: str = "active"
    createdAt: str
    updatedAt: str


# ── leads (public marketing capture) ──────────────────────────────────────────


class LeadCreate(WebModel):
    """A "Book a demo" submission from the public marketing site.

    Unauthenticated, so every field is bounded: this is the one endpoint on this
    surface that anyone on the internet can post to.
    """

    firstName: str = Field(min_length=1, max_length=120)
    lastName: str = Field(min_length=1, max_length=120)
    email: EmailStr = Field(max_length=200)
    hiresPerYear: str = Field(min_length=1, max_length=120)
    source: str | None = Field(default=None, max_length=120)


# ── voices ────────────────────────────────────────────────────────────────────


class VoiceOption(WebModel):
    id: str
    label: str
    gender: str | None = None
    language: str
    engine: str
    description: str | None = None
    sampleUrl: str | None = None


class InterviewPersona(WebModel):
    id: str
    name: str
    description: str
    stylePrompt: str
    defaultVoiceId: str
    speakingRate: float | None = None
    pitch: float | None = None


class VoiceCatalog(WebModel):
    voices: list[VoiceOption]
    personas: list[InterviewPersona]


class VoiceSampleRequest(WebModel):
    """Optional line to speak in a voice preview. Capped server-side regardless
    of what the client asks for — a preview is one short spoken sentence."""

    text: str | None = Field(default=None, max_length=200)


class VoiceSampleResponse(WebModel):
    voiceId: str
    mimeType: str
    # Base64 PCM. The client plays it directly; the Gemini key never leaves here.
    audio: str


# ── Mimic Guide ───────────────────────────────────────────────────────────────


class GuideMessage(WebModel):
    role: str = Field(pattern="^(user|assistant)$")
    # The cap must exceed the longest possible assistant reply. A bilingual answer
    # with the <details> English block can pass 4000 characters, and that reply
    # comes BACK in the history on the next turn — too tight a limit here would
    # fail validation on every subsequent message.
    content: str = Field(min_length=1, max_length=8000)


class GuideChatRequest(WebModel):
    """Up to 20 turns of history for multi-turn context."""

    messages: list[GuideMessage] = Field(min_length=1, max_length=20)


class GuideChatResponse(WebModel):
    reply: str


class TtsRequest(WebModel):
    text: str = Field(min_length=1, max_length=2000)
    lang: str = Field(min_length=2, max_length=12)


class LiveTokenGrant(WebModel):
    """A short-lived Gemini Live credential the browser connects to Google with.

    Deliberately NOT `app.schemas.LiveTokenResponse`, even though the fields match.
    That model is the mobile contract, and importing it here would couple the two
    surfaces through a shared response type — the layering test in
    `tests/test_layering.py` rejects it. The duplication is the cost of a boundary
    that can be moved later without breaking Flutter.

    The token carries the whole session setup with no `fieldMask`, so whatever setup
    the client sends on connect is ignored in favour of the locked copy.
    """

    token: str
    # Handed back rather than hardcoded in the client: the token-authenticated
    # socket lives on a different API version from the minting endpoint, and that
    # mapping should change without shipping a new frontend.
    wsUrl: str
    model: str
    expiresAt: str
    # How long the client has to OPEN the session. Distinct from `expiresAt`, which
    # bounds how long it may then run.
    connectBy: str


# ── Autopilot ─────────────────────────────────────────────────────────────────


class ParamSpec(WebModel):
    name: str
    type: str = Field(pattern="^(string|number|boolean|enum)$")
    enum: list[str] | None = None
    required: bool | None = None
    description: str | None = None


class ActionDescriptor(WebModel):
    name: str
    description: str
    screen: str
    sideEffect: bool
    params: list[ParamSpec] = Field(default_factory=list)


class AgentContext(WebModel):
    route: str = Field(max_length=200)
    availableActions: list[ActionDescriptor] = Field(default_factory=list, max_length=100)
    state: dict = Field(default_factory=dict)


class AgentMessage(WebModel):
    """Deliberately more tolerant than `GuideMessage`.

    `content` may be empty and the list may be long: a single empty turn must not
    reject the request, because that would fail every later turn and brick the
    session. The handler trims to the recent non-empty tail instead.
    """

    role: str = Field(pattern="^(user|assistant)$")
    content: str = Field(max_length=8000)


class AgentRequest(WebModel):
    messages: list[AgentMessage] = Field(min_length=1, max_length=200)
    context: AgentContext
