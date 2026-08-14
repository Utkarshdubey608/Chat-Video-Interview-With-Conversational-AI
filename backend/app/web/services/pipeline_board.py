"""Multi-round pipeline logic — the pure half of `server/routes/pipelines.ts`.

Validation, the kanban board projection, the advance-rule selection, and the
eligibility check. No storage and no HTTP, so the rules that decide whether a real
candidate moves forward are directly testable.

The one thing to keep in mind throughout: **a null score is never a pass.** A candidate
who has not been scored — not started, still in progress, or scored with no answers
captured — must never be selected by a threshold or a top-N rule, and must never be
advanced. Treating "no score" as zero would silently reject them; treating it as
passing would advance someone nobody assessed.
"""

from __future__ import annotations

import uuid
from fastapi import HTTPException, status

# `two_way` is deliberately absent: a live recruiter-led call has no scripted question
# source and no automatic score, so it cannot participate in threshold or top-N
# advancement. Allowing it would create rounds that can never advance anyone.
ALLOWED_ROUND_MODES = ("chatbot", "voice", "video_avatar", "chat", "video")

ADVANCE_RULE_KINDS = ("threshold", "topN")

IN_ROUND = "in_round"
ADVANCED = "advanced"
SELECTED = "selected"
NOT_ADVANCING = "not_advancing"


def _bad_request(message: str) -> HTTPException:
    return HTTPException(status.HTTP_400_BAD_REQUEST, message)


# ── validation ────────────────────────────────────────────────────────────────


def normalise_round(raw: object, index: int) -> dict:
    """One round, validated. Raises 400 with the round number in the message.

    The index is REASSIGNED from position rather than trusted from the body: the
    rounds are an ordered list, and a client-supplied index that disagreed with its
    position would make "advance to the next round" ambiguous.
    """
    data = raw if isinstance(raw, dict) else {}

    name = str(data.get("name") or "").strip()
    if not name:
        raise _bad_request(f"Round {index + 1}: name is required")

    mode = data.get("mode")
    if mode not in ALLOWED_ROUND_MODES:
        raise _bad_request(
            f'Round {index + 1}: mode "{mode}" is not allowed (two_way deferred)'
        )

    round_def: dict = {"index": index, "name": name, "mode": mode}

    source = data.get("source")
    if source in ("tailor", "set"):
        round_def["source"] = source

    if source == "tailor" and isinstance(data.get("config"), dict):
        config = data["config"]
        round_def["config"] = {
            "style": config.get("style"),
            "techCount": _as_int(config.get("techCount")),
            "nonTechCount": _as_int(config.get("nonTechCount")),
            "difficulty": config.get("difficulty"),
            "domains": config["domains"] if isinstance(config.get("domains"), list) else [],
            "model": config.get("model"),
        }

    if source == "set" and isinstance(data.get("questionSetId"), str):
        round_def["questionSetId"] = data["questionSetId"]

    rule = data.get("advanceRule")
    if isinstance(rule, dict) and rule.get("kind") in ADVANCE_RULE_KINDS:
        round_def["advanceRule"] = {
            "kind": rule["kind"],
            "value": _as_int(rule.get("value")),
        }

    return round_def


def _as_int(value: object) -> int:
    try:
        return int(float(value))  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return 0


def normalise(body: object) -> dict:
    """A pipeline's stored fields from a request. Raises 400 on invalid input."""
    data = body if isinstance(body, dict) else {}

    role = str(data.get("role") or "").strip()
    if not role:
        raise _bad_request("role is required")

    rounds = data.get("rounds")
    if not isinstance(rounds, list) or not rounds:
        raise _bad_request("at least one round is required")

    return {
        "role": role,
        "type": "multi",
        "name": str(data["name"]).strip() if isinstance(data.get("name"), str) else None,
        # Reindexed 0..n from position.
        "rounds": [normalise_round(raw, index) for index, raw in enumerate(rounds)],
    }


def build_candidate(
    *,
    pipeline_id: str,
    recruiter_id: str,
    candidate_email: str,
    role: str,
    interview_id: str,
    now: str,
    candidate_id: str | None = None,
) -> dict:
    """A pipeline candidate at round 0, with their first history entry.

    `history` is append-only and is the audit trail: who moved this person, when, on
    what basis, and whether the email actually went. A recruiter explaining a hiring
    decision months later has nothing else to go on.
    """
    return {
        "id": candidate_id or str(uuid.uuid4()),
        "pipelineId": pipeline_id,
        "recruiterId": recruiter_id,
        "candidateEmail": candidate_email,
        "candidateEmailLower": candidate_email.lower(),
        "role": role,
        "currentRoundIndex": 0,
        "status": IN_ROUND,
        "perRound": [{"roundIndex": 0, "interviewId": interview_id, "invitedAt": now}],
        "history": [
            {
                "at": now,
                "byUid": recruiter_id,
                "action": "invited",
                "toRound": 0,
                "basis": "round-1 invite",
            }
        ],
        "createdAt": now,
        "updatedAt": now,
    }


# ── the board ─────────────────────────────────────────────────────────────────


def is_scored(report: dict | None) -> bool:
    """Does this report represent a real assessment?

    `notEvaluated` is the case that matters: a session can complete with no answers
    captured, and its report carries zero scores as PLACEHOLDERS, not judgments.
    Treating that as scored would advance or reject someone on a number nobody
    produced.
    """
    if not report:
        return False
    if report.get("notEvaluated") is True:
        return False
    return isinstance(report.get("overallScore"), (int, float)) and not isinstance(
        report.get("overallScore"), bool
    )


def round_status(interview_id: str | None, report: dict | None, session_status: str | None) -> str:
    """What the card shows for the candidate's current round."""
    if not interview_id:
        return "none"
    if is_scored(report) or session_status == "completed":
        return "completed"
    if session_status in ("in_progress", "system_check"):
        return "in_progress"
    if session_status == "expired":
        return "expired"
    return "invited"


def current_interview_id(candidate: dict) -> str | None:
    """The interview for the round the candidate is in right now."""
    for progress in candidate.get("perRound") or []:
        if progress.get("roundIndex") == candidate.get("currentRoundIndex"):
            return progress.get("interviewId")
    return None


def build_board(
    pipeline: dict,
    candidates: list[dict],
    report_of,
    session_status_of,
) -> dict:
    """The kanban projection: one column per round, plus the two terminal columns.

    `report_of` and `session_status_of` are injected rather than read here, so this
    stays pure and the caller decides how to batch the lookups.
    """
    round_columns = [
        {
            "key": f"round-{round_def['index']}",
            "title": round_def["name"],
            "roundIndex": round_def["index"],
            "kind": "round",
            "cards": [],
        }
        for round_def in pipeline.get("rounds") or []
    ]
    selected_column = {
        "key": "selected",
        "title": "Selected",
        "roundIndex": None,
        "kind": "selected",
        "cards": [],
    }
    not_advancing_column = {
        "key": "not-advancing",
        "title": "Not advancing",
        "roundIndex": None,
        "kind": "not_advancing",
        "cards": [],
    }

    for candidate in candidates:
        interview_id = current_interview_id(candidate)
        report = report_of(interview_id) if interview_id else None
        scored = is_scored(report)

        card = {
            "pipelineCandidateId": candidate.get("id"),
            "candidateEmail": candidate.get("candidateEmail"),
            "candidateName": candidate.get("candidateName"),
            "currentRoundIndex": candidate.get("currentRoundIndex"),
            "status": candidate.get("status"),
            "roundStatus": round_status(
                interview_id,
                report,
                session_status_of(interview_id) if interview_id else None,
            ),
            # Null, not 0: an unscored candidate has no score, and 0 would sort them
            # alongside someone who genuinely scored zero.
            "score": report.get("overallScore") if scored else None,
            # The button state. Only a scored candidate in an active round can move.
            "advanceable": candidate.get("status") == IN_ROUND and scored,
            "history": candidate.get("history") or [],
        }

        if candidate.get("status") == SELECTED:
            selected_column["cards"].append(card)
        elif candidate.get("status") == NOT_ADVANCING:
            not_advancing_column["cards"].append(card)
        else:
            column = next(
                (c for c in round_columns if c["roundIndex"] == candidate.get("currentRoundIndex")),
                round_columns[0] if round_columns else None,
            )
            if column is not None:
                column["cards"].append(card)

    return {
        "pipeline": pipeline,
        "columns": [*round_columns, selected_column, not_advancing_column],
    }


# ── advancement ───────────────────────────────────────────────────────────────


def select_by_criteria(cards: list[dict], rule: dict) -> list[str]:
    """The candidate ids an advance rule picks.

    Unscored candidates are filtered out FIRST, so they can never be selected by
    either rule — a `topN` over a list padded with nulls would otherwise advance
    people nobody assessed once the scored pool was smaller than N.
    """
    scored = [
        card
        for card in cards
        if isinstance(card.get("score"), (int, float)) and not isinstance(card.get("score"), bool)
    ]

    if rule.get("kind") == "threshold":
        value = rule.get("value") or 0
        return [c["pipelineCandidateId"] for c in scored if c["score"] >= value]

    limit = max(0, int(rule.get("value") or 0))
    ranked = sorted(scored, key=lambda c: c["score"], reverse=True)
    return [c["pipelineCandidateId"] for c in ranked[:limit]]


def assert_advanceable(
    candidate: dict, target_round_index: int, round_count: int, scored: bool
) -> None:
    """Raise 400 unless this candidate may move to `target_round_index` right now.

    Four separate refusals, each preventing a different wrong outcome: re-advancing
    someone already selected or rejected, advancing on no assessment, skipping a round,
    and advancing past the end of the pipeline.
    """
    if candidate.get("status") != IN_ROUND:
        raise _bad_request("Candidate is not in an active round")
    if not scored:
        raise _bad_request(
            "Candidate has not completed and been scored in the current round"
        )
    if target_round_index != (candidate.get("currentRoundIndex") or 0) + 1:
        raise _bad_request("Can only advance to the next round")
    if target_round_index > round_count:
        raise _bad_request("Target round out of range")


def email_result(sent: bool, send_emails: bool) -> str:
    """What the history entry records about the email.

    Three states, not two: `skipped` when the recruiter chose not to send is different
    from `failed` when it was attempted and did not go, and conflating them would make
    the audit trail lie about whether a candidate was ever contacted.
    """
    if not send_emails:
        return "skipped"
    return "accepted" if sent else "failed"
