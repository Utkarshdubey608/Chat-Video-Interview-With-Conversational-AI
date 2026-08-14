"""`GET /api/web/auth/me` — the signed-in user's record.

Ports `server/routes/auth.ts`. There is no `/session` endpoint and no
custom-claim write: nothing a client sends to this router can change its role.

The Express version first looked for a mirrored `AppUser` in its JSON store and
synthesised one only as a fallback. The mirror is gone (see
`app/web/services/users.py` for why), so the synthesised path is now the only
path — which is what the fallback already produced for every user who had never
been mirrored.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Request

from app.security import AuthedUser
from app.web.deps import WebUser, settings_of
from app.web.schemas import AppUser
from app.web.services import users

router = APIRouter(prefix="/auth", tags=["web:auth"])


@router.get("/me", response_model=AppUser, summary="The current user")
async def me(request: Request, user: AuthedUser = WebUser) -> AppUser:
    settings = settings_of(request)
    role = await users.get_role(settings, user.uid)
    now = datetime.now(timezone.utc).isoformat()

    return AppUser(
        uid=user.uid,
        email=(user.email or "").lower(),
        role=role,
        admin=users.is_admin(settings, email=user.email, role=role),
        displayName=await users.get_display_name(settings, user.uid),
        emailVerified=users.email_verified(user),
        status="active",
        # No mirror document exists, so there is no stored creation time to
        # report. The client displays these but does not compute with them.
        createdAt=now,
        updatedAt=now,
    )
