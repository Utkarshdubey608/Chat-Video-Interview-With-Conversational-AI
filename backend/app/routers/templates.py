"""CRUD for recruiter-owned email templates + the built-in default.

Lets a recruiter customise an email template and save it for future use.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlmodel import Session, select

from app.db import get_session
from app.models import EmailTemplate
from app.schemas import TemplateCreate, TemplateRead, TemplateUpdate
from app.security import require_api_key
from app.templating import DEFAULT_BODY, DEFAULT_SUBJECT, SUPPORTED_VARIABLES

router = APIRouter(
    prefix="/api/templates",
    tags=["templates"],
    dependencies=[Depends(require_api_key)],
)


def _clear_other_defaults(session: Session, recruiter_id: str, keep_id: int | None) -> None:
    """Enforce a single default template per recruiter."""
    rows = session.exec(
        select(EmailTemplate).where(
            EmailTemplate.recruiter_id == recruiter_id,
            EmailTemplate.is_default == True,  # noqa: E712
        )
    ).all()
    for row in rows:
        if row.id != keep_id:
            row.is_default = False
            session.add(row)


@router.get("/defaults", response_model=dict)
async def get_builtin_default() -> dict:
    """Starter subject/body + the variables the editor can offer. Not persisted."""
    return {
        "subject": DEFAULT_SUBJECT,
        "body": DEFAULT_BODY,
        "variables": SUPPORTED_VARIABLES,
    }


@router.get("", response_model=list[TemplateRead])
async def list_templates(
    recruiter_id: str = Query(min_length=1),
    session: Session = Depends(get_session),
) -> list[EmailTemplate]:
    return session.exec(
        select(EmailTemplate)
        .where(EmailTemplate.recruiter_id == recruiter_id)
        .order_by(EmailTemplate.is_default.desc(), EmailTemplate.updated_at.desc())
    ).all()


@router.post("", response_model=TemplateRead, status_code=status.HTTP_201_CREATED)
async def create_template(
    payload: TemplateCreate,
    session: Session = Depends(get_session),
) -> EmailTemplate:
    template = EmailTemplate(**payload.model_dump())
    if template.is_default:
        _clear_other_defaults(session, template.recruiter_id, keep_id=None)
    session.add(template)
    session.commit()
    session.refresh(template)
    return template


@router.put("/{template_id}", response_model=TemplateRead)
async def update_template(
    template_id: int,
    payload: TemplateUpdate,
    session: Session = Depends(get_session),
) -> EmailTemplate:
    template = session.get(EmailTemplate, template_id)
    if template is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Template not found.")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(template, field, value)
    template.updated_at = datetime.now(timezone.utc)
    if template.is_default:
        _clear_other_defaults(session, template.recruiter_id, keep_id=template.id)
    session.add(template)
    session.commit()
    session.refresh(template)
    return template


@router.delete("/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_template(
    template_id: int,
    session: Session = Depends(get_session),
) -> Response:
    template = session.get(EmailTemplate, template_id)
    if template is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Template not found.")
    session.delete(template)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
