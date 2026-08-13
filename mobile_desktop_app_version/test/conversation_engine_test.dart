// Unit tests for the conversational (chatbot) engine. These exercise the
// deterministic (no-Gemini-key) paths: the fixed-source walk, the adaptive
// generic fallback, timed thinking→answer advancement, transcript grouping,
// and the heuristic conversation report — all without any network calls.

import 'package:flutter_test/flutter_test.dart';
import 'package:talbotiq/features/recruiter/models/recruiter_models.dart';
import 'package:talbotiq/features/recruiter/engine/defaults.dart';
import 'package:talbotiq/features/recruiter/engine/conversation_engine.dart';

InterviewTemplate _template({
  String source = QuestionSource.fixed,
  String? mode,
  ConversationTimingConfig? conversationTiming,
  AdaptiveConfig? adaptive,
}) {
  final now = DateTime.now().toIso8601String();
  return InterviewTemplate(
    id: 'tpl',
    name: 'T',
    role: 'Engineer',
    track: TrackType.chatbot,
    questionSource: source,
    timing: const TimingConfig(numberOfQuestions: 3),
    rubric: defaultRubric(),
    integrity: defaultIntegrity(),
    branding: defaultBranding(),
    mode: mode,
    conversationTiming: conversationTiming,
    adaptive: adaptive,
    createdAt: now,
    updatedAt: now,
  );
}

List<FixedQuestion> _fixed(int n) =>
    List.generate(n, (i) => FixedQuestion(id: 'f$i', text: 'Fixed question $i'));

void main() {
  group('isTimedTemplate', () {
    test('true only for timed mode with a conversationTiming', () {
      expect(isTimedTemplate(_template()), isFalse);
      expect(
          isTimedTemplate(_template(mode: InterviewMode.conversational)), isFalse);
      expect(
          isTimedTemplate(_template(
              mode: InterviewMode.timed,
              conversationTiming: defaultConversationTiming())),
          isTrue);
      expect(isTimedTemplate(_template(mode: InterviewMode.timed)), isFalse);
    });
  });

  group('fixed-source conversational walk', () {
    test('begins, walks the set, and ends after the last question', () async {
      final t = _template(source: QuestionSource.fixed);
      final e = ConversationEngine(template: t, fixedQuestions: _fixed(3));
      await e.begin(0);

      expect(e.plannedQuestionCount, 3);
      expect(e.transcript.length, 1);
      expect(e.transcript.first.role, 'interviewer');
      expect(e.transcript.first.content, 'Fixed question 0');
      expect(e.completed, isFalse);

      await e.submitAnswer(1000, 'answer 0');
      expect(e.currentIndex, 1);
      expect(e.transcript.last.content, 'Fixed question 1');

      await e.submitAnswer(2000, 'answer 1');
      expect(e.currentIndex, 2);

      await e.submitAnswer(3000, 'answer 2'); // last primary
      expect(e.completed, isTrue);
      // Closing interviewer line appended.
      expect(e.transcript.last.role, 'interviewer');
    });

    test('empty question set throws on begin', () async {
      final e = ConversationEngine(template: _template(), fixedQuestions: const []);
      expect(() => e.begin(0), throwsA(isA<Exception>()));
    });
  });

  group('adaptive fallback (no Gemini key)', () {
    test('requires a résumé', () async {
      final t = _template(
          source: QuestionSource.adaptive, adaptive: defaultAdaptive());
      final e = ConversationEngine(template: t, resumeText: '');
      expect(() => e.begin(0), throwsA(isA<Exception>()));
    });

    test('uses generic questions and ends after the planned count', () async {
      final t = _template(
        source: QuestionSource.adaptive,
        adaptive: defaultAdaptive().copyWith(numberOfQuestions: 3),
      );
      final e = ConversationEngine(template: t, resumeText: 'Lots of experience.');
      await e.begin(0);
      expect(e.plannedQuestionCount, 3);
      expect(e.transcript.length, 1); // fallback first question

      await e.submitAnswer(1000, 'a0');
      await e.submitAnswer(2000, 'a1');
      expect(e.completed, isFalse);
      await e.submitAnswer(3000, 'a2'); // at last primary → ends
      expect(e.completed, isTrue);
    });
  });

  group('timed advancement', () {
    test('thinking→answer→expire is deterministic', () async {
      final t = _template(
        source: QuestionSource.fixed,
        mode: InterviewMode.timed,
        conversationTiming: const ConversationTimingConfig(
            thinkingSeconds: 2, perQuestionSeconds: 3),
      );
      final e = ConversationEngine(template: t, fixedQuestions: _fixed(2));
      await e.begin(0);
      expect(e.isTimed, isTrue);
      expect(e.phase(0), ConvPhase.thinking);

      // Before the thinking deadline: nothing expires.
      expect(e.advanceTiming(1000), isFalse);
      expect(e.phase(1000), ConvPhase.thinking);

      // At the thinking deadline: transition to answer, not expired yet.
      expect(e.advanceTiming(2000), isFalse);
      expect(e.phase(2000), ConvPhase.answer);

      // At the answer deadline: expired (caller must auto-submit).
      expect(e.advanceTiming(5000), isTrue);
    });

    test('skipThinking jumps straight to the answer phase', () async {
      final t = _template(
        source: QuestionSource.fixed,
        mode: InterviewMode.timed,
        conversationTiming: const ConversationTimingConfig(
            thinkingSeconds: 30, perQuestionSeconds: 60),
      );
      final e = ConversationEngine(template: t, fixedQuestions: _fixed(1));
      await e.begin(0);
      expect(e.phase(0), ConvPhase.thinking);
      expect(e.skipThinking(1000), isTrue);
      expect(e.phase(1000), ConvPhase.answer);
    });
  });

  group('primaryQuestionGroups', () {
    test('folds follow-up answers into their primary question', () {
      final turns = <Turn>[
        Turn(id: 't0', role: 'interviewer', content: 'Q0', questionIndex: 0, createdAt: 'x'),
        Turn(id: 't1', role: 'candidate', content: 'A0', questionIndex: 0, createdAt: 'x'),
        Turn(id: 't2', role: 'interviewer', content: 'Follow', questionIndex: 0, isFollowUp: true, createdAt: 'x'),
        Turn(id: 't3', role: 'candidate', content: 'A0-more', questionIndex: 0, createdAt: 'x'),
        Turn(id: 't4', role: 'interviewer', content: 'Q1', questionIndex: 1, createdAt: 'x'),
        Turn(id: 't5', role: 'candidate', content: 'A1', questionIndex: 1, createdAt: 'x'),
      ];
      final groups = primaryQuestionGroups(turns);
      expect(groups.length, 2);
      expect(groups[0].index, 0);
      expect(groups[0].question, 'Q0');
      expect(groups[0].answer, 'A0\n\nA0-more');
      expect(groups[1].question, 'Q1');
      expect(groups[1].answer, 'A1');
    });
  });

  group('conversationHeuristicReport', () {
    test('is degraded, complete, and scores empty answers 0', () {
      final t = _template();
      final session = InterviewSession(
        id: 's1',
        templateId: t.id,
        track: TrackType.chatbot,
        candidateName: 'Jane',
        candidateEmail: 'j@e.com',
        status: SessionStatus.completed,
        questions: const [],
        createdAt: DateTime.now().toIso8601String(),
        transcript: [
          Turn(id: 't0', role: 'interviewer', content: 'Q0', questionIndex: 0, createdAt: 'x'),
          Turn(id: 't1', role: 'candidate', content: 'A fairly detailed answer with several words.', questionIndex: 0, createdAt: 'x'),
          Turn(id: 't2', role: 'interviewer', content: 'Q1', questionIndex: 1, createdAt: 'x'),
          Turn(id: 't3', role: 'candidate', content: '', questionIndex: 1, createdAt: 'x'),
        ],
      );
      final groups = primaryQuestionGroups(session.transcript!);
      final report = conversationHeuristicReport(session, t, groups);
      expect(report.degraded, isTrue);
      expect(report.perQuestion.length, 2);
      expect(report.overallScore, inInclusiveRange(0, 100));
      final q1 = report.perQuestion.firstWhere((p) => p.questionId == 'q1');
      expect(q1.kpiScores.values.every((v) => v == 0), isTrue);
    });
  });
}
