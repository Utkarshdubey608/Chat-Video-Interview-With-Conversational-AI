"""Runtime configuration, loaded from environment variables / a local .env file.

Everything the service needs is declared here so the rest of the code never
reads os.environ directly. See .env.example for the full list.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- App ---
    app_name: str = "TalbotIQ Mailer"
    # Comma-separated list of allowed CORS origins. "*" allows any (dev only).
    cors_origins: str = "*"

    # --- Auth ---
    # Shared secret the Flutter app sends as the `X-API-Key` header. When empty,
    # auth is DISABLED (handy for local dev; set it in any real deploy).
    api_key: str = ""

    # --- Delivery ---
    # When true, emails are NOT actually sent — they're logged instead, and the
    # endpoint still returns per-recipient results. No credentials needed.
    dry_run: bool = True

    # Display name used on the "From" header.
    from_name: str = "TalbotIQ"
    # The Gmail address mail is sent from. Needed by both modes below.
    email_user: str = ""

    # Mode A (simplest): Gmail SMTP with a 16-character App Password.
    email_app_password: str = ""
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587

    # Mode B: Gmail API with an OAuth refresh token — used when all three are
    # set. Handy where outbound SMTP is blocked (some PaaS hosts).
    gmail_client_id: str = ""
    gmail_client_secret: str = ""
    gmail_refresh_token: str = ""

    # How many recipients of one /send call are delivered in parallel.
    send_concurrency: int = 5

    # --- Third-party AI providers ---
    # These are the ONLY place these credentials exist. The app never sees them:
    # it either calls a proxy route here, or receives a short-lived Gemini Live
    # token minted from gemini_api_key. Blank = that feature reports 503 rather
    # than failing with a confusing vendor 401.
    gemini_api_key: str = ""
    tavus_api_key: str = ""
    deepgram_api_key: str = ""
    # Daily — the live recruiter↔candidate call (two-way interview track). Blank
    # makes that track report 503; every other track is unaffected.
    daily_api_key: str = ""
    # Your Daily subdomain, e.g. "talbotiq" for talbotiq.daily.co. Needed only to
    # build a room URL for the candidate; the recruiter's URL comes back from the
    # room-creation call itself.
    daily_domain: str = ""

    # Model used for scoring / question generation (REST generateContent).
    gemini_model: str = "gemini-2.5-flash"
    # Models a caller may request instead of the default. Comma-separated, and an
    # ALLOWLIST rather than free choice: a client must not be able to redirect
    # spend onto an arbitrarily expensive model, but recruiters do legitimately
    # choose between flash and pro.
    gemini_allowed_models: str = "gemini-2.5-flash,gemini-2.5-pro"
    # Native-audio model used for the live voice interview.
    gemini_live_model: str = "models/gemini-2.5-flash-native-audio-preview-09-2025"

    # --- Gemini Live ephemeral tokens ---
    # Minted per interview launch; the client connects straight to Google with one.
    # Grace added to the interview's own duration before the session is cut off.
    gemini_token_expiry_buffer_minutes: int = 10
    # Window the client has to OPEN the session after minting. Google's own
    # default is 60s; the client mints on launch-tap so this is ample.
    gemini_token_connect_window_seconds: int = 120
    # A voice preview is one short spoken line — it needs no interview-length
    # session, and a tight cap limits what a misused preview token can cost.
    gemini_preview_session_minutes: int = 2

    # --- Tavus conversation defaults ---
    # Org infrastructure, applied when the backend creates a conversation. These
    # were text fields in the app's Settings — an AWS assume-role ARN typed on a
    # phone — and are server-side for the same reason the API keys are.
    tavus_enable_recording: bool = False
    tavus_recording_s3_bucket: str = ""
    tavus_recording_s3_region: str = ""
    tavus_aws_assume_role_arn: str = ""
    # Session properties the app used to expose globally. Sensible defaults; the
    # per-interview values (duration, language) still come from the interview.
    tavus_participant_left_timeout: int = 60
    tavus_participant_absent_timeout: int = 300
    tavus_enable_transcription: bool = True

    # --- Rate limiting (per user, per worker) ---
    # Auth proves a caller is a real user; these bound how much one user can
    # spend. In-process counters — see app/ratelimit.py for the caveats.
    rate_limit_enabled: bool = True
    rate_limit_window_seconds: int = 60
    # Minting a Live token hands out a credential. One interview launch needs
    # exactly one, so a low ceiling still leaves room for retries.
    rate_limit_live_token: int = 10
    # Scoring an interview makes a handful of calls; regeneration adds more.
    rate_limit_generate: int = 30
    # Audio uploads: transcription, and starting an avatar conversation.
    rate_limit_media: int = 20

    # --- Firebase (saved templates only — same project as the mobile app) ---
    firebase_project_id: str = "talbotiq-9cc4e"
    # Path to a service-account JSON file...
    firebase_credentials_file: str = ""
    # ...or that JSON inline (convenient as a single PaaS env var). If both are
    # empty, Application Default Credentials are used.
    firebase_credentials_json: str = ""
    # Firestore collection holding recruiter-saved templates.
    templates_collection: str = "email_templates"

    @property
    def cors_origin_list(self) -> list[str]:
        raw = self.cors_origins.strip()
        if raw == "*" or not raw:
            return ["*"]
        return [o.strip() for o in raw.split(",") if o.strip()]

    @property
    def allowed_gemini_models(self) -> set[str]:
        """The requestable models, always including the default."""
        names = {
            m.strip().removeprefix("models/")
            for m in self.gemini_allowed_models.split(",")
            if m.strip()
        }
        names.add(self.gemini_model.strip().removeprefix("models/"))
        return names

    @property
    def live_model_name(self) -> str:
        """The Live model, always in Google's `models/…` resource form."""
        m = self.gemini_live_model.strip()
        return m if m.startswith("models/") else f"models/{m}"


@lru_cache
def get_settings() -> Settings:
    return Settings()
