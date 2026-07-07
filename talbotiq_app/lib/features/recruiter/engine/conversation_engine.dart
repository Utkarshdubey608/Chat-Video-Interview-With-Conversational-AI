// lib/features/recruiter/engine/conversation_engine.dart
//
// Native Dart port of talbotiq-platform `server/services/conversation.ts` — the
// conversational (chatbot) interview track. Drives an interviewer/candidate
// transcript: fixed-source templates walk a question set deterministically;
// adaptive templates let Gemini decide the next turn (grounded in the résumé),
// clamped to server-side limits. Timed conversational mode preserves the
// wall-clock thinking→answer state machine. Degrades gracefully offline
// (generic questions, heuristic transcript scoring) when no Gemini key is set.
//
// This engine calls the Gemini service for adaptive turns but has no Flutter
// imports, so the deterministic (no-key) paths are unit-testable.

import '../models/recruiter_models.dart';
import '../services/recruiter_gemini_service.dart';
import 'scoring_engine.dart';

int _clamp(num n) => n.clamp(0, 100).round();

/// Timed conversational mode = mode 'timed' with a conversationTiming config.
bool isTimedTemplate(InterviewTemplate t) =>
    t.mode == InterviewMode.timed && t.conversationTiming != null;

enum ConvPhase { thinking, answer }

// Offline fallbacks (no Gemini key / error), mirroring the web GENERIC list.
const List<String> _generic = [
  'Tell me about a project you’re especially proud of and your specific contribution.',
  'Describe a difficult technical problem you solved recently — how did you approach it?',
  'How do you handle disagreement with a teammate about a technical decision?',
  'What part of your experience is most relevant to this role, and why?',
  'Where do you want to grow over the next couple of years?',
  'Tell me about a time you had to learn something new quickly.',
];
String _genericPrimary(int idx) => _generic[idx % _generic.length];

final RegExp _closingRe =
    RegExp(r"thank you|concludes|all the questions|that'?s all", caseSensitive: false);

/// Mutable runtime turn (the immutable [Turn] model is snapshotted on save).
class ConvTurn {
  final String id;
  final String role; // 'interviewer' | 'candidate'
  String content;
  int? questionIndex;
  bool isFollowUp;
  final int createdAt; // epoch ms
  int? thinkingStartedAt;
  int? answerStartedAt;
  int? submittedAt;
  bool autoAdvanced;
  String draft;

  ConvTurn({
    required this.id,
    required this.role,
    required this.content,
    this.questionIndex,
    this.isFollowUp = false,
    required this.createdAt,
    this.thinkingStartedAt,
    this.answerStartedAt,
    this.submittedAt,
    this.autoAdvanced = false,
    this.draft = '',
  });

  Turn toTurn() => Turn(
        id: id,
        role: role,
        content: content,
        questionIndex: questionIndex,
        isFollowUp: role == 'interviewer' ? isFollowUp : null,
        createdAt: _iso(createdAt)!,
        thinkingStartedAt: _iso(thinkingStartedAt),
        answerStartedAt: _iso(answerStartedAt),
        submittedAt: _iso(submittedAt),
        autoAdvanced: autoAdvanced ? true : null,
        draft: draft.isEmpty ? null : draft,
      );
}

String? _iso(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String();

/// Runtime state machine for one conversational interview.
class ConversationEngine {
  final InterviewTemplate template;
  final List<FixedQuestion> fixedQuestions;
  final String resumeText;
  final RecruiterGeminiService service;

  final List<ConvTurn> transcript = [];
  int currentIndex = 0;
  int followUpsThisQuestion = 0;
  int plannedQuestionCount = 0;
  int? startedAt;
  bool completed = false;

  ConversationEngine({
    required this.template,
    this.fixedQuestions = const [],
    this.resumeText = '',
    RecruiterGeminiService? service,
  }) : service = service ?? recruiterGeminiService;

  bool get isFixed => template.questionSource == QuestionSource.fixed;
  bool get isTimed => isTimedTemplate(template);

  int plannedCountFor() {
    if (isFixed) return fixedQuestions.length;
    return template.adaptive?.numberOfQuestions ??
        template.timing.numberOfQuestions ??
        5;
  }

  String _fallbackFirst() =>
      'Hi, thanks for joining! To start, tell me about your background and what drew you to the ${template.role.isNotEmpty ? template.role : 'this'} role.';

  // ── Turn plumbing ─────────────────────────────────────────────────────────
  void _armTimed(int nowMs, ConvTurn turn) {
    if (!isTimed) return;
    final t = template.conversationTiming!;
    if (t.thinkingSeconds > 0) {
      turn.thinkingStartedAt = nowMs;
    } else {
      turn.answerStartedAt = nowMs;
    }
  }

  void _appendInterviewer(
      int nowMs, String content, int? questionIndex, bool isFollowUp) {
    final turn = ConvTurn(
      id: recruiterId('turn'),
      role: 'interviewer',
      content: content,
      questionIndex: questionIndex,
      isFollowUp: isFollowUp,
      createdAt: nowMs,
    );
    if (questionIndex != null) _armTimed(nowMs, turn);
    transcript.add(turn);
  }

  void _endConversation(int nowMs, String? closing) {
    if (closing != null && closing.trim().isNotEmpty) {
      transcript.add(ConvTurn(
        id: recruiterId('turn'),
        role: 'interviewer',
        content: closing.trim(),
        createdAt: nowMs,
      ));
    }
    completed = true;
  }

  ConvTurn? get _lastInterviewer {
    for (final t in transcript.reversed) {
      if (t.role == 'interviewer') return t;
    }
    return null;
  }

  /// The interviewer turn the candidate is currently answering (unsubmitted).
  ConvTurn? get awaitingInterviewer {
    if (completed) return null;
    for (final t in transcript.reversed) {
      if (t.role == 'interviewer' && t.submittedAt == null) return t;
    }
    return null;
  }

  Future<TurnDecision> _adaptiveTurn({required bool isFirst}) {
    final a = template.adaptive!;
    final followBudget = a.maxFollowUpsPerQuestion - followUpsThisQuestion;
    final primariesLeft = plannedQuestionCount - (currentIndex + 1);
    return service.generateAdaptiveTurn(
      adaptive: a,
      transcript: transcript.map((t) => t.toTurn()).toList(),
      resumeText: resumeText,
      isFirst: isFirst,
      followBudgetLeft: followBudget < 0 ? 0 : followBudget,
      primariesLeft: primariesLeft < 0 ? 0 : primariesLeft,
    );
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initialise the session and produce the first interviewer turn.
  Future<void> begin(int nowMs) async {
    transcript.clear();
    currentIndex = 0;
    followUpsThisQuestion = 0;
    plannedQuestionCount = plannedCountFor();
    startedAt = nowMs;
    completed = false;

    String message;
    if (isFixed) {
      if (fixedQuestions.isEmpty) {
        throw Exception('The template references an empty question set.');
      }
      message = fixedQuestions[0].text;
    } else {
      if (resumeText.trim().isEmpty) {
        throw Exception('A résumé is required before starting this interview.');
      }
      try {
        message = service.enabled
            ? (await _adaptiveTurn(isFirst: true)).message
            : _fallbackFirst();
      } catch (_) {
        message = _fallbackFirst();
      }
    }
    _appendInterviewer(nowMs, message, 0, false);
  }

  /// Record the candidate's answer to the current turn and produce the next.
  Future<void> submitAnswer(int nowMs, String answerText,
      {bool autoAdvanced = false}) async {
    if (completed) return;
    final lastInterviewer = _lastInterviewer;
    transcript.add(ConvTurn(
      id: recruiterId('turn'),
      role: 'candidate',
      content: answerText.trim(),
      questionIndex: lastInterviewer?.questionIndex ?? currentIndex,
      isFollowUp: lastInterviewer?.isFollowUp ?? false,
      createdAt: nowMs,
    ));
    if (lastInterviewer != null) {
      lastInterviewer.submittedAt = nowMs;
      if (autoAdvanced) lastInterviewer.autoAdvanced = true;
    }

    final plannedCount = plannedQuestionCount;
    final atLastPrimary = currentIndex >= plannedCount - 1;

    // Fixed source: deterministic walk, no follow-ups.
    if (isFixed) {
      final nextIdx = currentIndex + 1;
      if (nextIdx >= fixedQuestions.length) {
        return _endConversation(
            nowMs, 'That’s all the questions I had — thank you for your time!');
      }
      currentIndex = nextIdx;
      followUpsThisQuestion = 0;
      _appendInterviewer(nowMs, fixedQuestions[nextIdx].text, nextIdx, false);
      return;
    }

    // Adaptive: let Gemini decide, then clamp to limits.
    final a = template.adaptive!;
    TurnDecision decision;
    try {
      decision = service.enabled
          ? await _adaptiveTurn(isFirst: false)
          : TurnDecision(
              message: atLastPrimary ? '' : _genericPrimary(currentIndex + 1),
              action: atLastPrimary
                  ? TurnDecision.actionEnd
                  : TurnDecision.actionNext,
            );
    } catch (_) {
      decision = TurnDecision(
        message: atLastPrimary ? '' : _genericPrimary(currentIndex + 1),
        action:
            atLastPrimary ? TurnDecision.actionEnd : TurnDecision.actionNext,
      );
    }

    final followBudgetLeft =
        a.allowFollowUps && followUpsThisQuestion < a.maxFollowUpsPerQuestion;

    var action = decision.action;
    if (action == TurnDecision.actionEnd && !atLastPrimary) {
      action = TurnDecision.actionNext;
    }
    if (action == TurnDecision.actionFollowUp && !followBudgetLeft) {
      action = TurnDecision.actionNext;
    }

    if (action == TurnDecision.actionEnd) {
      return _endConversation(nowMs,
          decision.message.isNotEmpty ? decision.message : 'Thank you — that concludes our interview.');
    }
    if (action == TurnDecision.actionFollowUp) {
      followUpsThisQuestion += 1;
      _appendInterviewer(
          nowMs,
          decision.message.isNotEmpty
              ? decision.message
              : 'Could you go a little deeper on that?',
          currentIndex,
          true);
      return;
    }

    // next_question
    if (atLastPrimary) {
      return _endConversation(nowMs, 'Thank you — that concludes our interview.');
    }
    final nextIdx = currentIndex + 1;
    currentIndex = nextIdx;
    followUpsThisQuestion = 0;
    final looksClosing = _closingRe.hasMatch(decision.message);
    final msg = decision.message.isNotEmpty && !looksClosing
        ? decision.message
        : _genericPrimary(nextIdx);
    _appendInterviewer(nowMs, msg, nextIdx, false);
  }

  // ── Timed-mode advancement ────────────────────────────────────────────────

  /// Progress timed phases that have elapsed. Returns true when the answer
  /// window is up and the caller must auto-submit the current draft.
  bool advanceTiming(int nowMs) {
    if (completed || !isTimed) return false;
    final ct = template.conversationTiming!;
    final turn = _lastInterviewer;
    if (turn == null || turn.submittedAt != null || turn.questionIndex == null) {
      return false;
    }
    if (turn.thinkingStartedAt != null && turn.answerStartedAt == null) {
      final deadline = turn.thinkingStartedAt! + ct.thinkingSeconds * 1000;
      if (nowMs >= deadline) {
        turn.answerStartedAt = deadline;
      } else {
        return false;
      }
    }
    if (turn.answerStartedAt != null) {
      final deadline = turn.answerStartedAt! + ct.perQuestionSeconds * 1000;
      if (nowMs >= deadline) return true; // answer_expired
    }
    return false;
  }

  /// Candidate ends thinking early and starts answering now.
  bool skipThinking(int nowMs) {
    if (!isTimed || template.conversationTiming?.allowSkipThinking != true) {
      return false;
    }
    final turn = _lastInterviewer;
    if (turn == null ||
        turn.submittedAt != null ||
        turn.answerStartedAt != null ||
        turn.thinkingStartedAt == null) {
      return false;
    }
    turn.answerStartedAt = nowMs;
    return true;
  }

  void saveDraft(String text) {
    awaitingInterviewer?.draft = text;
  }

  ConvPhase? phase(int nowMs) {
    if (!isTimed) return null;
    final turn = awaitingInterviewer;
    if (turn == null || turn.questionIndex == null) return null;
    if (turn.answerStartedAt != null) return ConvPhase.answer;
    if (turn.thinkingStartedAt != null) return ConvPhase.thinking;
    return null;
  }

  int totalPhaseSeconds(int nowMs) {
    final ct = template.conversationTiming;
    if (ct == null) return 0;
    return phase(nowMs) == ConvPhase.answer
        ? ct.perQuestionSeconds
        : ct.thinkingSeconds;
  }

  int remainingSeconds(int nowMs) {
    final ct = template.conversationTiming;
    final turn = awaitingInterviewer;
    if (ct == null || turn == null) return 0;
    double rem = 0;
    if (turn.answerStartedAt != null) {
      rem = ct.perQuestionSeconds - (nowMs - turn.answerStartedAt!) / 1000.0;
    } else if (turn.thinkingStartedAt != null) {
      rem = ct.thinkingSeconds - (nowMs - turn.thinkingStartedAt!) / 1000.0;
    }
    return rem < 0 ? 0 : rem.ceil();
  }

  int get progressCurrent {
    final total = plannedQuestionCount;
    final c = currentIndex + 1;
    return total > 0 && c > total ? total : c;
  }

  /// Snapshot the runtime transcript back into the persisted session.
  InterviewSession toSession(InterviewSession base,
      {required bool markCompleted, List<IntegrityEvent>? integrityEvents, int? tabSwitchCount}) {
    return base.copyWith(
      status: markCompleted ? SessionStatus.completed : SessionStatus.inProgress,
      transcript: transcript.map((t) => t.toTurn()).toList(),
      currentIndex: currentIndex,
      plannedQuestionCount: plannedQuestionCount,
      followUpsThisQuestion: followUpsThisQuestion,
      startedAt: startedAt != null ? _iso(startedAt) : base.startedAt,
      completedAt: markCompleted ? DateTime.now().toIso8601String() : base.completedAt,
      integrityEvents: integrityEvents,
      tabSwitchCount: tabSwitchCount,
    );
  }
}

// ── Transcript grouping (for scoring / the report) ───────────────────────────

class PrimaryQuestionGroup {
  final int index;
  final String question;
  final String answer;
  final bool autoAdvanced;
  const PrimaryQuestionGroup({
    required this.index,
    required this.question,
    required this.answer,
    required this.autoAdvanced,
  });
}

class _GroupAcc {
  String question;
  final List<String> answers = [];
  bool autoAdvanced = false;
  _GroupAcc(this.question);
}

/// Group the transcript by primary question, mirroring the web
/// `primaryQuestionGroups` (follow-up answers fold into their question).
List<PrimaryQuestionGroup> primaryQuestionGroups(List<Turn> turns) {
  final map = <int, _GroupAcc>{};
  int? lastIndex;
  for (final t in turns) {
    if (t.role == 'interviewer' && t.questionIndex != null) {
      lastIndex = t.questionIndex;
      map.putIfAbsent(t.questionIndex!, () => _GroupAcc(t.content));
    } else if (t.role == 'candidate') {
      final qi = t.questionIndex ?? lastIndex;
      if (qi != null) {
        final acc = map.putIfAbsent(qi, () => _GroupAcc(''));
        if (t.content.trim().isNotEmpty) acc.answers.add(t.content.trim());
        if (t.autoAdvanced == true) acc.autoAdvanced = true;
      }
    }
  }
  final entries = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  return entries
      .map((e) => PrimaryQuestionGroup(
            index: e.key,
            question: e.value.question,
            answer: e.value.answers.join('\n\n'),
            autoAdvanced: e.value.autoAdvanced,
          ))
      .toList();
}

// ── Conversation report assembly ─────────────────────────────────────────────

const List<String> _recs = [
  Recommendation.strongYes,
  Recommendation.yes,
  Recommendation.maybe,
  Recommendation.no,
];

ResultReport assembleConversationReport(
  InterviewSession session,
  InterviewTemplate template,
  RawConversationScore raw,
  List<PrimaryQuestionGroup> groups,
) {
  final enabledIds =
      template.rubric.kpis.where((k) => k.enabled).map((k) => k.id).toSet();
  final perQuestion = groups.map((g) {
    RawConvQuestionScore? match;
    for (final p in raw.perQuestion) {
      if (p.questionIndex == g.index) {
        match = p;
        break;
      }
    }
    final kpiScores = <String, double>{};
    if (match != null) {
      match.scores.forEach((kpiId, score) {
        if (enabledIds.contains(kpiId)) kpiScores[kpiId] = _clamp(score).toDouble();
      });
    }
    return PerQuestionResult(
      questionId: 'q${g.index}',
      kpiScores: kpiScores,
      feedback: match?.feedback ?? 'No feedback returned.',
    );
  }).toList();

  final kpiAverages = averageKpis(template.rubric, perQuestion);
  final overall = weightedOverall(template.rubric, kpiAverages);
  final rec = _recs.contains(raw.recommendation)
      ? raw.recommendation!
      : recommendationFor(overall);

  return ResultReport(
    sessionId: session.id,
    perQuestion: perQuestion,
    kpiAverages: kpiAverages,
    overallScore: overall.toDouble(),
    summary: raw.summary.isNotEmpty ? raw.summary : 'No summary returned.',
    strengths: raw.strengths.isNotEmpty ? raw.strengths : null,
    improvements: raw.improvements.isNotEmpty ? raw.improvements : null,
    recommendation: rec,
    generatedAt: DateTime.now().toIso8601String(),
  );
}

/// Fully offline heuristic report over the grouped transcript.
ResultReport conversationHeuristicReport(
  InterviewSession session,
  InterviewTemplate template,
  List<PrimaryQuestionGroup> groups,
) {
  final enabled = template.rubric.kpis.where((k) => k.enabled).toList();
  final perQuestion = groups.map((g) {
    final kpiScores = <String, double>{};
    for (final k in enabled) {
      kpiScores[k.id] = heuristicScore(g.answer, k.id).toDouble();
    }
    return PerQuestionResult(
      questionId: 'q${g.index}',
      kpiScores: kpiScores,
      feedback: g.answer.trim().isNotEmpty
          ? 'Heuristic placeholder — add a Gemini key in Settings for content-aware feedback.'
          : 'No answer was provided.',
    );
  }).toList();

  final kpiAverages = averageKpis(template.rubric, perQuestion);
  final overall = weightedOverall(template.rubric, kpiAverages);
  return ResultReport(
    sessionId: session.id,
    perQuestion: perQuestion,
    kpiAverages: kpiAverages,
    overallScore: overall.toDouble(),
    summary:
        'Generated by the heuristic fallback (no Gemini key). Scores reflect answer length only.',
    recommendation: recommendationFor(overall),
    generatedAt: DateTime.now().toIso8601String(),
    degraded: true,
  );
}
