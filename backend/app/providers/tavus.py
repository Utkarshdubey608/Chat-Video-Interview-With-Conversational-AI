"""Tavus — the video-avatar interview.

REST only. Tavus has no ephemeral-token scheme, so every call is proxied. That
costs nothing in practice: the calls are create/poll/end, none on a latency-
sensitive path. The conversation's *media* never touches this service — creating
a conversation returns a Daily room URL that the candidate's device joins
directly.
"""

from __future__ import annotations

import asyncio

from app.providers.base import ProviderClient


class TavusClient(ProviderClient):
    name = "Tavus"
    env_var = "TAVUS_API_KEY"
    base_url = "https://tavusapi.com/v2"

    @property
    def api_key(self) -> str:
        return self.settings.tavus_api_key

    def auth_headers(self) -> dict[str, str]:
        return {"x-api-key": self.api_key.strip(), "Content-Type": "application/json"}

    # --- replicas & personas -------------------------------------------------
    async def list_replicas(self) -> list[dict]:
        """Custom + stock replicas, merged and de-duplicated.

        Two upstream calls because Tavus splits them. Either may fail on its own;
        returning whatever succeeded matches the app's existing behaviour — a
        recruiter with only stock replicas should still see a populated picker.
        Both failing is a real error.
        """
        custom, stock = await asyncio.gather(
            self.request("GET", "/replicas"),
            self.request("GET", "/replicas", params={"replica_type": "stock"}),
            return_exceptions=True,
        )

        if isinstance(custom, Exception) and isinstance(stock, Exception):
            raise custom

        merged: list[dict] = []
        seen: set[str] = set()
        # Custom first, so a replica present in both keeps its custom entry.
        for result, is_stock in ((custom, False), (stock, True)):
            if isinstance(result, Exception):
                continue
            for replica in _items(result):
                replica_id = str(replica.get("replica_id") or replica.get("id") or "")
                if replica_id and replica_id in seen:
                    continue
                if replica_id:
                    seen.add(replica_id)
                # The stock endpoint does not label its own results, but the app
                # groups the picker by `replica_type`, so stamp it here — the
                # client can no longer tell which call a replica came from.
                merged.append({**replica, "replica_type": "stock"} if is_stock else replica)
        return merged

    async def list_personas(self) -> list[dict]:
        return _items(await self.request("GET", "/personas"))

    # --- conversations -------------------------------------------------------
    async def create_conversation(self, payload: dict) -> dict:
        return await self.request("POST", "/conversations", json=payload)

    async def get_conversation(self, conversation_id: str, *, verbose: bool = False) -> dict:
        return await self.request(
            "GET",
            f"/conversations/{conversation_id}",
            params={"verbose": "true"} if verbose else None,
        )

    async def end_conversation(self, conversation_id: str) -> dict:
        """POST /end, never DELETE.

        DELETE destroys the conversation record *and its server-side transcript*,
        which the results pipeline still needs to fetch afterwards.
        """
        return await self.request("POST", f"/conversations/{conversation_id}/end")

    async def send_interaction(self, conversation_id: str, text: str) -> dict:
        """Overwrite the live conversation's context — e.g. the next question."""
        return await self.request(
            "POST",
            f"/conversations/{conversation_id}/interactions",
            json={
                "message_type": "conversation",
                "event_type": "conversation.overwrite_context",
                "conversation_id": conversation_id,
                "properties": {"context": text},
            },
        )


def _items(payload: object) -> list[dict]:
    """Tavus returns either a bare list or a {"data": [...]} wrapper."""
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        data = payload.get("data")
        if isinstance(data, list):
            return [item for item in data if isinstance(item, dict)]
    return []
