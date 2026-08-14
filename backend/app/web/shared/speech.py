"""Text destined to be spoken aloud — a port of `web_version/talbotiq-platform/shared/speech.ts`.

Everything here exists because a written question and a spoken one are not the same
artefact. Markdown becomes noise ("asterisk asterisk bold"), a numbered list gets its
numbers read out, and an em dash reads as a machine wrote it.

Like `invite_email.py`, this module is imported by the React client as well as the
Express server, so the port introduces a second implementation of shared logic. Unlike
the email renderer, nothing here is byte-compared between the two: the output is a
prompt, not a document, and a small divergence changes phrasing rather than correctness.
Worth knowing rather than guarding.
"""

from __future__ import annotations

import re

TIME_GREETINGS = {
    "morning": "Good morning",
    "afternoon": "Good afternoon",
    "evening": "Good evening",
}

# How much résumé the avatar is given as background. Enough to sound informed, bounded
# because it rides in every conversation's context.
MAX_BACKGROUND_CHARS = 1500

_MARKDOWN = re.compile(r"[*_`#>]+")
_LIST_PREFIX = re.compile(r"^\s*(?:\d+[.)]|[-–—•])\s+", re.MULTILINE)
_DASHES = re.compile(r"\s*[—–]\s*")
_WHITESPACE = re.compile(r"\s+")


def greeting_word(time_of_day: str | None) -> str:
    return TIME_GREETINGS.get(time_of_day or "", "Hello")


def strip_for_speech(text: str) -> str:
    """Reduce written text to something that reads naturally aloud.

    Markdown, list markers and dashes all have visual meaning and no spoken one — a
    text-to-speech engine either voices them literally or pauses oddly around them.
    """
    value = _LIST_PREFIX.sub("", text or "")
    value = _MARKDOWN.sub("", value)
    value = _DASHES.sub(", ", value)
    value = re.sub(r",\s*,", ",", value)
    return _WHITESPACE.sub(" ", value).strip()


SPOKEN_STYLE_RULES = (
    "SPEAKING STYLE: You are speaking out loud, not writing. Use contractions and short, "
    "natural sentences. Never read out formatting, numbers of questions, or lists. Never "
    "use em dashes. Sound warm and genuinely interested, never templated or corporate."
)

VARIED_THANKS_RULE = (
    "After each answer, give ONE short, varied, genuine acknowledgment before the next "
    "question — never the same phrase twice, and never a critical one."
)


def default_interviewer_persona(
    candidate_name: str | None = None, ai_name: str | None = None
) -> str:
    who = (candidate_name or "").strip() or "the candidate"
    me = (ai_name or "").strip() or "Alex"
    return (
        f"You are {me}, a Senior Talent Specialist at TalbotIQ conducting a screening "
        f"interview with {who}. You are warm, personable and encouraging — you put people "
        "at ease and sound genuinely interested in their answers."
    )


def avatar_interview_context(
    *,
    persona_text: str | None = None,
    candidate_name: str | None = None,
    ai_name: str | None = None,
    questions: list[str],
    time_of_day: str | None = None,
    resume_text: str | None = None,
) -> str:
    """The avatar's full instructions for one interview.

    The strict-script rules are the load-bearing part. An avatar left to improvise asks
    different questions of different candidates, which makes the scores incomparable and
    the screen indefensible — so it is told, explicitly and more than once, to ask exactly
    these questions in exactly this order and invent nothing.

    The résumé is included as BACKGROUND only, with the same prohibition attached: it is
    there so the avatar sounds informed when it acknowledges an answer, not so it can
    think of new questions.
    """
    who = (candidate_name or "").strip() or "the candidate"
    named = bool((candidate_name or "").strip())
    persona = (persona_text or "").strip() or default_interviewer_persona(
        candidate_name, ai_name
    )
    numbered = "\n".join(
        f"{index + 1}. {strip_for_speech(question)}"
        for index, question in enumerate(questions)
    )

    sections = [persona]

    if (resume_text or "").strip():
        sections.append(
            f"CANDIDATE BACKGROUND — from {who}'s résumé. Use it to sound informed and to "
            "personalise your brief acknowledgments naturally (e.g. referencing their "
            "experience), but NEVER to add, change, or skip scripted questions:\n"
            f"{resume_text.strip()[:MAX_BACKGROUND_CHARS]}"
        )

    sections += [
        SPOKEN_STYLE_RULES,
        f"""FLOW:
1. Open with a brief "{greeting_word(time_of_day)}" greeting and warmly welcome {who}{' by name' if named else ''}. Add one short reassuring line about how this will go, then ask if they're ready to begin, and wait.
2. If they clearly say yes, begin. If they're unsure or nervous, reassure them in one short line and ask again; only start on a clear yes.
3. Ask the questions below IN ORDER, one at a time, phrased exactly as written. Wait for {who} to completely finish each answer — never interrupt. {VARIED_THANKS_RULE}
4. Only AFTER the final question is answered, close warmly: thank them sincerely, tell them that's everything and they're all done, that the team will be in touch about next steps, and wish them a great rest of their day.""",
        "THE QUESTIONS, IN ORDER — ask every one, exactly as written; never say their "
        f"numbers aloud:\n{numbered}",
        f"STRICT RULES: Ask ONLY these questions. Do NOT invent, add, skip, reorder, or "
        f"rephrase any question, and never ask follow-ups that are not in the list. No "
        f"small talk beyond the opening. If {who} goes off-topic or asks you questions, "
        "politely acknowledge in one short line and steer straight back to the next "
        "planned question. Cover ALL the questions, then close — never finish early and "
        "never add questions of your own.",
    ]

    return "\n\n".join(sections)


def avatar_greeting_text(
    *,
    custom: str | None = None,
    candidate_name: str | None = None,
    ai_name: str | None = None,
    time_of_day: str | None = None,
) -> str:
    """The avatar's first words. A recruiter's own greeting wins."""
    if (custom or "").strip():
        return strip_for_speech(custom)

    hello = greeting_word(time_of_day)
    name = (candidate_name or "").strip()
    me = (ai_name or "").strip()
    intro = (
        f"I'm {me}, and I'm really looking forward to our chat"
        if me
        else "I'm really looking forward to our chat"
    )
    who = f" {name}," if name else ","

    return (
        f"{hello}{who} welcome, and thanks so much for making the time today. {intro}, so "
        "just relax and answer naturally. Are you ready to begin?"
    )
