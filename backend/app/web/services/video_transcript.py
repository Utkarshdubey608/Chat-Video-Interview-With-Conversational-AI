"""Turning a submitted video answer into transcript turns.

Ports `server/services/videoTranscript.ts`.

The Video Interview track stores no video — **the live transcript IS the answer**.
Mirroring it into `session.transcript` as a question/answer pair is what lets scoring,
the speech metrics and the results view run the same conversation path as the Voice
track, instead of needing a fourth shape to understand.

Pure. The id generator is injected so the output is deterministic under test.
"""

from __future__ import annotations

import uuid


def build_turns(
    question: dict, question_index: int, now_iso: str, *, new_id=lambda: str(uuid.uuid4())
) -> list[dict]:
    """The interviewer/candidate pair for one answered question.

    Both turns carry the same `questionIndex` — that is how the results view pairs them
    back up, and how per-question scoring knows which answer belongs to which question.
    """
    return [
        {
            "id": new_id(),
            "role": "interviewer",
            "content": question.get("text") or "",
            "turnType": "question",
            "questionIndex": question_index,
            "createdAt": now_iso,
        },
        {
            "id": new_id(),
            "role": "candidate",
            # Empty rather than absent when the candidate said nothing: the turn's
            # existence records that they were asked and had their chance, which a
            # missing turn would not.
            "content": question.get("answerText") or "",
            "questionIndex": question_index,
            "createdAt": now_iso,
        },
    ]
