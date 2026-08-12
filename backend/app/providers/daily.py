"""Daily — the live recruiter ↔ candidate call (the two-way interview track).

Managed WebRTC: rooms, SFU and TURN are Daily's problem, not ours. The device
joins a room URL directly, exactly as it already does for the Tavus avatar track
(Tavus itself runs on Daily), so the app needs no new video plumbing.

Three operations, and the shape of them is the security model:

* **rooms are deterministic** — `room-{interviewId}`. Two people joining the same
  interview must land in the same room without any handshake, and a recruiter
  re-joining after a dropped connection must return to the call rather than open
  a second empty one.
* **tokens are short-lived and role-scoped** — the recruiter gets `is_owner`, the
  candidate does not. Ownership is what makes admitting people possible, so a
  candidate holding an owner token could admit themselves and anyone else.
* **the API key never leaves this service.** The device receives a room URL and a
  token, both useless once the room expires. Same rule as Tavus and Gemini.

Rooms are created with knocking enabled, which is Daily's built-in lobby: the
candidate waits until the recruiter admits them. That replaces the custom
waiting-room the web app had to build.

Recording is deliberately NOT enabled. Cloud recording is a paid Daily feature,
and without it there is no transcript — which is why the two-way track is scored
by the recruiter rather than by the model. See `docs` in the app's review card.
"""

from __future__ import annotations

import logging

from app.providers.base import ProviderClient, UpstreamError

logger = logging.getLogger("providers.daily")

# How long a room stays alive after creation. Generously longer than any
# interview, because expiry mid-call would drop both parties with no recourse.
ROOM_TTL_SECONDS = 4 * 60 * 60

# A token outlives the room deliberately — a token that expired first would fail
# a re-join into a room that is still perfectly alive.
TOKEN_TTL_SECONDS = ROOM_TTL_SECONDS + 30 * 60


def room_name_for(interview_id: str) -> str:
    """The room an interview's call happens in.

    Derived, not stored: both sides compute the same name from the same id, so
    there is nothing to keep in sync and a re-join always finds the same room.
    """
    return f"room-{interview_id}"


class DailyClient(ProviderClient):
    name = "Daily"
    env_var = "DAILY_API_KEY"
    base_url = "https://api.daily.co/v1"

    @property
    def api_key(self) -> str:
        return self.settings.daily_api_key

    def auth_headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.api_key.strip()}",
            "Content-Type": "application/json",
        }

    def room_properties(self, now_seconds: int) -> dict:
        return {
            # Daily's built-in lobby. The candidate knocks; the recruiter admits.
            "enable_knocking": True,
            "enable_screenshare": True,
            "enable_chat": False,
            "start_video_off": False,
            "start_audio_off": False,
            # Self-expiring, so an abandoned interview does not leave a room open
            # indefinitely for anyone holding the URL.
            "exp": now_seconds + ROOM_TTL_SECONDS,
            "eject_at_room_exp": True,
        }

    async def ensure_room(self, room_name: str, *, now_seconds: int) -> dict:
        """The room for this interview, creating it only if it is not there.

        Idempotent on purpose. A recruiter tapping "join" twice, or rejoining
        after their connection dropped, must land back in the SAME room — a
        create-always implementation would 400 on the duplicate name, or worse,
        put the two parties in different rooms.
        """
        self.require_configured()

        try:
            existing = await self.request("GET", f"/rooms/{room_name}")
            if isinstance(existing, dict) and existing.get("url"):
                return existing
        except UpstreamError as exc:
            # 404 is the normal "not created yet" path; anything else is a real
            # failure and must not be papered over by creating a second room.
            if exc.status_code != 404:
                raise

        created = await self.request(
            "POST",
            "/rooms",
            json={
                "name": room_name,
                "privacy": "private",
                "properties": self.room_properties(now_seconds),
            },
        )
        logger.info("created Daily room %s", room_name)
        return created

    async def room_exists(self, room_name: str) -> bool:
        """Whether the recruiter has opened the call yet.

        This is the candidate's gate: their client polls until this is true. A
        missing room means "the interviewer has not started", NOT an error — so a
        404 is answered as False rather than raised.
        """
        self.require_configured()
        try:
            room = await self.request("GET", f"/rooms/{room_name}")
        except UpstreamError as exc:
            if exc.status_code == 404:
                return False
            raise
        return isinstance(room, dict) and bool(room.get("url"))

    async def mint_token(
        self,
        *,
        room_name: str,
        is_owner: bool,
        user_name: str,
        now_seconds: int,
    ) -> str:
        """A short-lived meeting token for one participant.

        `is_owner` is the whole authorisation model of the call: an owner can
        admit knockers and eject people. Only the recruiter gets one, and only
        after this service has checked they own the interview.
        """
        self.require_configured()

        response = await self.request(
            "POST",
            "/meeting-tokens",
            json={
                "properties": {
                    "room_name": room_name,
                    "is_owner": is_owner,
                    "user_name": user_name[:80],
                    "exp": now_seconds + TOKEN_TTL_SECONDS,
                    # A non-owner lands in the lobby and waits to be let in.
                    "start_video_off": False,
                    "start_audio_off": False,
                }
            },
        )
        token = (response or {}).get("token", "")
        if not token:
            raise UpstreamError(self.name, 502, "meeting-tokens returned no token")
        # Never log the token — it is a bearer credential for the call.
        logger.info("minted Daily token: room=%s owner=%s", room_name, is_owner)
        return token

    async def delete_room(self, room_name: str) -> None:
        """Ends the call for everyone still in it.

        Best-effort: a room that is already gone (404) is the desired state, and
        rooms self-expire anyway, so a failure here must not fail the request
        that ends the interview.
        """
        self.require_configured()
        try:
            await self.request("DELETE", f"/rooms/{room_name}")
        except UpstreamError as exc:
            if exc.status_code != 404:
                logger.warning("could not delete Daily room %s: %s", room_name, exc)
