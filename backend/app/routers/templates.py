"""Two endpoints:

    GET  /api/templates   — every template that can be picked (built-in + custom)
    POST /api/templates   — save a custom template in Firestore

Custom templates live in the mobile app's Firebase project. The built-ins are in
code, so listing works even with no Firebase credentials.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from app import templates_store
from app.config import Settings
from app.firebase import FirestoreUnavailable
from app.schemas import TemplateCreate, TemplateList, TemplateRead
from app.security import require_api_key
from app.templating import DEFAULT_TEMPLATE_ID, SUPPORTED_VARIABLES

router = APIRouter(
    prefix="/api/templates",
    tags=["templates"],
    dependencies=[Depends(require_api_key)],
)


def _settings(request: Request) -> Settings:
    return request.app.state.settings


@router.get("", response_model=TemplateList)
async def list_templates(
    request: Request,
    owner_email: str | None = Query(
        default=None,
        description="The recruiter's email. Returns the built-ins plus only their own templates.",
    ),
) -> TemplateList:
    """All templates to choose from. Pass an `id` from here to /api/emails/send."""
    templates, warning = templates_store.list_all(_settings(request), owner_email)
    return TemplateList(
        templates=[TemplateRead(**t) for t in templates],
        default_template_id=DEFAULT_TEMPLATE_ID,
        variables=SUPPORTED_VARIABLES,
        warning=warning,
    )


@router.post("", response_model=TemplateRead, status_code=status.HTTP_201_CREATED)
async def create_template(payload: TemplateCreate, request: Request) -> TemplateRead:
    """Save a custom template; the returned `id` is what /send accepts."""
    try:
        created = templates_store.create(_settings(request), payload.model_dump())
    except FirestoreUnavailable as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(exc)) from exc
    return TemplateRead(**created)
