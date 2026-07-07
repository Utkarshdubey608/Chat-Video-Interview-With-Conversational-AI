// Unit tests for the pure recruiter engines (timing + scoring). These verify
// the ported state-machine and scoring semantics deterministically, without UI.

import 'package:flutter_test/flutter_test.dart';
import 'package:talbotiq/features/recruiter/models/recruiter_models.dart';
import 'package:talbotiq/features/recruiter/engine/defaults.dart';
import 'package:talbotiq/features/recruiter/engine/timing_engine.dart';
import 'package:talbotiq/features/recruiter/engine/scoring_engine.dart';
import 'package:talbotiq/features/recruiter/services/recruiter_gemini_service.dart';

InterviewTemplate _template({int prep = 2, int answer = 3}) {
  final now = DateTime.now().toIso8601String();
  return InterviewTemplate(
    id: 'tpl',
    name: 'T',
    role: 'Engineer',
    track: TrackType.chat,
    questionSource: QuestionSource.fixed,
    timing: TimingConfig(prepSeconds: prep, answerSeconds: answer),
    rubric: defaultRubric(),
    integrity: defaultIntegrity(),
    branding: defaultBranding(),
    createdAt: now,
    updatedAt: now,
  );
}

List<SessionQuestion> _qs(int n) => List.generate(
    n, (i) => SessionQuestion(id: 'q$i', text: 'Question $i'));

void main() {
  group('RunnerEngine timing state machine', () {
    test('advances prep → answer → auto-submit → complete', () {
      final t = _template(prep: 2, answer: 3);
      final e = RunnerEngine.fromQuestions(_qs(2), t.timing);
      e.begin(0);
      expect(e.phase, RunnerPhase.prep);
      expect(e.currentIndex, 0);

      e.tick(2000); // prep elapsed → answer phase
      expect(e.phase, RunnerPhase.answer);

      e.tick(5000); // answer elapsed → auto-submit q0, arm q1 prep
      expect(e.questions[0].autoSubmitted, isTrue);
      expect(e.currentIndex, 1);
      expect(e.completed, isFalse);

      e.tick(10000); // q1 prep(→7000) + answer(→10000) elapse → complete
      expect(e.completed, isTrue);
      expect(e.questions[1].autoSubmitted, isTrue);
    });

    test('manual submit advances and preserves answer text', () {
      final t = _template();
      final e = RunnerEngine.fromQuestions(_qs(2), t.timing);
      e.begin(0);
      e.submitAnswer(500, 'my answer');
      expect(e.questions[0].answerText, 'my answer');
      expect(e.questions[0].autoSubmitted, isFalse);
      expect(e.currentIndex, 1);
      e.submitAnswer(1000, 'second');
      expect(e.completed, isTrue);
    });

    test('skipPrep jumps to the answer phase', () {
      final t = _template(prep: 30, answer: 60);
      final e = RunnerEngine.fromQuestions(_qs(1), t.timing);
      e.begin(0);
      expect(e.phase, RunnerPhase.prep);
      e.skipPrep(1000);
      expect(e.phase, RunnerPhase.answer);
    });

    test('remainingSeconds counts down within a phase', () {
      final t = _template(prep: 10, answer: 20);
      final e = RunnerEngine.fromQuestions(_qs(1), t.timing);
      e.begin(0);
      expect(e.remainingSeconds(0), 10);
      expect(e.remainingSeconds(4000), 6);
    });
  });

  group('résumé generation helpers', () {
    test('clampInt bounds and falls back', () {
      expect(clampInt(30, 0, 25, 8), 25);
      expect(clampInt(-3, 0, 25, 8), 0);
      expect(clampInt(null, 0, 25, 8), 8);
      expect(clampInt(12, 0, 25, 8), 12);
    });

    test('resumeQuestionTotal by style', () {
      expect(resumeQuestionTotal(QuestionStyle.mix, 3, 2), 5);
      expect(resumeQuestionTotal(QuestionStyle.technical, 3, 2), 3);
      expect(resumeQuestionTotal(QuestionStyle.nonTechnical, 3, 2), 2);
    });
  });

  group('scoring engine', () {
    test('recommendationFor thresholds', () {
      expect(recommendationFor(80), Recommendation.strongYes);
      expect(recommendationFor(79), Recommendation.yes);
      expect(recommendationFor(65), Recommendation.yes);
      expect(recommendationFor(50), Recommendation.maybe);
      expect(recommendationFor(49), Recommendation.no);
    });

    test('heuristicScore is 0 for empty and bounded for content', () {
      expect(heuristicScore('', 'communication'), 0);
      final s = heuristicScore('this is a reasonably detailed answer', 'depth');
      expect(s, greaterThan(0));
      expect(s, lessThanOrEqualTo(100));
    });

    test('weightedOverall normalizes enabled weights', () {
      final rubric = KpiRubric(kpis: const [
        KpiDefinition(id: 'a', label: 'A', description: '', weight: 1),
        KpiDefinition(id: 'b', label: 'B', description: '', weight: 3),
        KpiDefinition(
            id: 'c', label: 'C', description: '', weight: 5, enabled: false),
      ]);
      // (80*1 + 40*3)/4 = 50 ; disabled 'c' ignored.
      final overall = weightedOverall(rubric, {'a': 80, 'b': 40, 'c': 100});
      expect(overall, 50);
    });

    test('heuristicReport produces a complete, degraded report', () {
      final t = _template();
      final session = InterviewSession(
        id: 's1',
        templateId: t.id,
        track: TrackType.chat,
        candidateName: 'Jane',
        candidateEmail: 'j@e.com',
        status: SessionStatus.completed,
        questions: [
          SessionQuestion(
              id: 'q0',
              text: 'Q0',
              answerText: 'A fairly detailed answer with several words here.'),
          SessionQuestion(id: 'q1', text: 'Q1', answerText: ''),
        ],
        createdAt: DateTime.now().toIso8601String(),
      );
      final report = heuristicReport(session, t);
      expect(report.degraded, isTrue);
      expect(report.perQuestion.length, 2);
      expect(report.overallScore, inInclusiveRange(0, 100));
      expect(report.recommendation, isNotNull);
      // Empty answer scores 0 on every KPI.
      final q1 = report.perQuestion.firstWhere((p) => p.questionId == 'q1');
      expect(q1.kpiScores.values.every((v) => v == 0), isTrue);
    });
  });
}
