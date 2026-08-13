// test/evaluation_failure_test.dart
//
// "Never show a candidate a score nobody computed."
//
// The chat track used to store the HEURISTIC fallback — scores derived from answer
// LENGTH, not content — as `evaluatedBy: 'ai'`. A recruiter saw a plausible number
// labelled like a real evaluation, and could publish it to the candidate. These
// tests pin the three properties that fix relies on:
//
//   1. a failed evaluation stores NO score, not a zero;
//   2. it is therefore absent from the leaderboard rather than ranked last;
//   3. retrying only ever touches candidates nobody has scored, and a failed
//      retry still leaves no score behind.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talbotiq/core/services/gemini_service.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/models/interview_round.dart';
import 'package:talbotiq/features/interviews/recruiter/round_timeline_page.dart';
import 'package:talbotiq/features/interviews/services/evaluation_retry_service.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';

const _rec = 'rec-1';
const _testId = 'test-1';

const _answers = [
  {'question': 'Tell me about yourself.', 'answer': 'I build Flutter apps.'},
  {'question': 'A hard bug?', 'answer': 'A race in an isolate.'},
];

void main() {
  late FakeFirebaseFirestore db;
  late InterviewRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = InterviewRepository(firestore: db);
  });

  Future<String> seed({
    String email = 'asha@b.com',
    String status = 'completed',
    Map<String, dynamic>? result,
    String? roundId,
  }) async {
    final ref = await db.collection('interviews').add({
      'recruiterId': _rec,
      'testId': _testId,
      if (roundId != null) 'roundId': roundId,
      'candidateEmail': email,
      'candidateEmailLower': email,
      'title': 'Backend Engineer',
      'type': 'chat',
      'status': status,
      if (result != null) 'result': result,
      'createdAt': Timestamp.now(),
    });
    return ref.id;
  }

  Future<Interview> read(String id) async =>
      Interview.fromDoc(await db.collection('interviews').doc(id).get());

  group('a failed evaluation stores no score', () {
    test('completeWithoutScore omits overallScore entirely', () async {
      final id = await seed(result: null, status: 'in_progress');
      await repo.completeWithoutScore(
        id,
        error: 'Gemini returned 503',
        responses: _answers,
      );

      final raw = (await db.collection('interviews').doc(id).get()).data()!;
      final result = raw['result'] as Map<String, dynamic>;

      // The key is ABSENT. A 0 would rank the candidate last on the leaderboard
      // as though they had earned it, and would read as a real result.
      expect(result.containsKey('overallScore'), isFalse);
      expect(result['evaluatedBy'], '');
      expect(result['evaluationError'], 'Gemini returned 503');
      expect(raw['status'], 'completed');

      final i = await read(id);
      expect(i.evaluationFailed, isTrue);
      expect(i.hasScore, isFalse);
      expect(i.isAiScored, isFalse);
      expect(i.canRetryEvaluation, isTrue, reason: 'answers were kept');
    });

    test('no error recorded reads as "not scored yet", not as a failure',
        () async {
      // The placeholder written the moment a call ends, before scoring runs.
      final id = await seed(result: null, status: 'in_progress');
      await repo.completeWithoutScore(id);

      final i = await read(id);
      expect(i.awaitingEvaluation, isTrue);
      expect(i.evaluationFailed, isFalse,
          reason: 'nothing failed — nothing has tried yet');
      expect(i.canRetryEvaluation, isFalse,
          reason: 'no stored answers, so there is nothing to re-score');
    });

    test('a real AI score is reported as one', () async {
      final id = await seed(result: {
        'overallScore': 74,
        'evaluatedBy': 'ai',
        'responses': _answers,
      });
      final i = await read(id);
      expect(i.isAiScored, isTrue);
      expect(i.hasScore, isTrue);
      expect(i.evaluationFailed, isFalse);
      expect(i.awaitingEvaluation, isFalse);
      expect(i.canRetryEvaluation, isFalse,
          reason: 'a scored candidate must never be re-scored by a bulk retry');
    });

    test('a recruiter\'s manual score is never treated as retryable', () async {
      final id = await seed(result: {
        'overallScore': 55,
        'evaluatedBy': 'manual',
        'responses': _answers,
      });
      final i = await read(id);
      expect(i.isManuallyScored, isTrue);
      expect(i.canRetryEvaluation, isFalse);
    });
  });

  group('the leaderboard does not rank an unscored candidate', () {
    test('a failed evaluation is absent, not last', () async {
      await seed(email: 'scored@b.com', result: {
        'overallScore': 80,
        'evaluatedBy': 'ai',
      });
      final failedId = await seed(email: 'failed@b.com', status: 'in_progress');
      await repo.completeWithoutScore(failedId,
          error: 'scoring failed', responses: _answers);

      final page = await repo.fetchLeaderboardPage(
          recruiterId: _rec, testId: _testId);

      expect(page.items.map((i) => i.candidateEmailLower), ['scored@b.com']);
      // Both completed the round; only one has a rank.
      expect(
        await repo.countForRecruiter(
            recruiterId: _rec,
            testId: _testId,
            status: InterviewStatus.completed),
        2,
      );
    });
  });

  group('fetchRetryableEvaluations', () {
    test('finds only the unscored-with-answers', () async {
      final retryable = await seed(email: 'retry@b.com', status: 'in_progress');
      await repo.completeWithoutScore(retryable,
          error: 'boom', responses: _answers);

      await seed(email: 'scored@b.com', result: {
        'overallScore': 70,
        'evaluatedBy': 'ai',
        'responses': _answers,
      });
      // Unscored but with nothing to score — manual evaluation only.
      final noAnswers = await seed(email: 'empty@b.com', status: 'in_progress');
      await repo.completeWithoutScore(noAnswers, error: 'no transcript');
      // Never took it.
      await seed(email: 'pending@b.com', status: 'assigned');

      final found = await repo.fetchRetryableEvaluations(
          recruiterId: _rec, testId: _testId);

      expect(found.map((i) => i.candidateEmailLower), ['retry@b.com']);
    });

    test('scopes to a round when asked', () async {
      for (final rid in ['r1', 'r2']) {
        final id = await seed(
            email: '$rid@b.com', status: 'in_progress', roundId: rid);
        await repo.completeWithoutScore(id, error: 'x', responses: _answers);
      }

      final r1 = await repo.fetchRetryableEvaluations(
          recruiterId: _rec, testId: _testId, roundId: 'r1');
      expect(r1.map((i) => i.candidateEmailLower), ['r1@b.com']);

      final all = await repo.fetchRetryableEvaluations(
          recruiterId: _rec, testId: _testId);
      expect(all.length, 2);
    });

    test('never reaches another recruiter\'s candidates', () async {
      await db.collection('interviews').add({
        'recruiterId': 'someone-else',
        'testId': _testId,
        'candidateEmailLower': 'theirs@b.com',
        'title': 'T',
        'type': 'chat',
        'status': 'completed',
        'result': {'evaluatedBy': '', 'responses': _answers},
      });

      expect(
        await repo.fetchRetryableEvaluations(
            recruiterId: _rec, testId: _testId),
        isEmpty,
      );
    });
  });

  group('retrying', () {
    RegeneratedResult goodScore() => const RegeneratedResult(
          overallScore: 81,
          summary: 'Strong on concurrency.',
          recommendation: 'Recommended',
          strengths: ['Clear reasoning'],
          improvements: ['Shallow on testing'],
        );

    test('writes a real AI score and clears the failure', () async {
      final id = await seed(status: 'in_progress');
      await repo.completeWithoutScore(id,
          error: 'Gemini 503', responses: _answers);

      final service = EvaluationRetryService(
        repository: repo,
        scorer: ({required jobRole, required responses}) async {
          // The scorer is handed the stored answers and the job title.
          expect(jobRole, 'Backend Engineer');
          expect(responses.length, 2);
          return goodScore();
        },
      );

      final report = await service.retryEach([await read(id)]);

      expect(report.total, 1);
      expect(report.scored, 1);
      expect(report.allSucceeded, isTrue);

      final after = await read(id);
      expect(after.isAiScored, isTrue);
      expect(after.result?['overallScore'], 81);
      expect(after.evaluationFailed, isFalse);
      // The failure reason is gone, and the answers survive for a manual review.
      expect(after.evaluationError, isEmpty);
      expect(after.storedResponses.length, 2);
    });

    test('a failed retry records the new reason and still stores no score',
        () async {
      final id = await seed(status: 'in_progress');
      await repo.completeWithoutScore(id,
          error: 'first failure', responses: _answers);

      final service = EvaluationRetryService(
        repository: repo,
        scorer: ({required jobRole, required responses}) async =>
            throw Exception('quota exhausted'),
      );

      final report = await service.retryEach([await read(id)]);

      expect(report.failed, 1);
      expect(report.scored, 0);
      expect(report.summary, contains('quota exhausted'));

      final after = await read(id);
      // THE point of this whole change: a failed retry leaves no fabricated
      // number behind, and the answers are still there to try again.
      expect(after.hasScore, isFalse);
      expect(after.result?.containsKey('overallScore'), isFalse);
      expect(after.evaluationError, 'quota exhausted');
      expect(after.canRetryEvaluation, isTrue);
    });

    test('skips anyone who already has a score, even if passed in', () async {
      final scoredId = await seed(email: 'scored@b.com', result: {
        'overallScore': 90,
        'evaluatedBy': 'manual',
        'summary': 'My own assessment.',
        'responses': _answers,
      });

      var scorerCalls = 0;
      final service = EvaluationRetryService(
        repository: repo,
        scorer: ({required jobRole, required responses}) async {
          scorerCalls++;
          return goodScore();
        },
      );

      final report = await service.retryEach([await read(scoredId)]);

      expect(scorerCalls, 0, reason: 'no billable call for an already-scored row');
      expect(report.total, 0);

      // Their manual assessment is untouched.
      final after = await read(scoredId);
      expect(after.result?['overallScore'], 90);
      expect(after.result?['summary'], 'My own assessment.');
      expect(after.isManuallyScored, isTrue);
    });

    test('a partial failure is reported as a partial failure', () async {
      final ok = await seed(email: 'ok@b.com', status: 'in_progress');
      final bad = await seed(email: 'bad@b.com', status: 'in_progress');
      for (final id in [ok, bad]) {
        await repo.completeWithoutScore(id, error: 'x', responses: _answers);
      }

      // Fail the second call only.
      var calls = 0;
      final service = EvaluationRetryService(
        repository: repo,
        scorer: ({required jobRole, required responses}) async {
          calls++;
          if (calls > 1) throw Exception('rate limited');
          return goodScore();
        },
      );

      final report =
          await service.retryEach([await read(ok), await read(bad)]);

      expect(report.total, 2);
      expect(report.scored, 1);
      expect(report.failed, 1);
      expect(report.allSucceeded, isFalse);
      // Must not read as success.
      expect(report.summary, contains('still failing 1'));
    });

    test('progress is reported per candidate', () async {
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        final id = await seed(email: 'c$i@b.com', status: 'in_progress');
        await repo.completeWithoutScore(id, error: 'x', responses: _answers);
        ids.add(id);
      }

      final seenProgress = <String>[];
      final service = EvaluationRetryService(
        repository: repo,
        scorer: ({required jobRole, required responses}) async => goodScore(),
      );
      await service.retryEach(
        [for (final id in ids) await read(id)],
        onProgress: (done, total) => seenProgress.add('$done/$total'),
      );

      expect(seenProgress, ['1/3', '2/3', '3/3']);
    });

    test('nothing to retry is stated, not reported as success', () async {
      final service = EvaluationRetryService(
        repository: repo,
        scorer: ({required jobRole, required responses}) async => goodScore(),
      );
      final report = await service.retryEach(const []);
      expect(report.total, 0);
      expect(report.allSucceeded, isFalse);
      expect(report.summary, 'Nothing needed re-scoring.');
    });
  });

  group('the current round marker', () {
    InterviewRound r(String id, int order,
            {DateTime? opensAt, DateTime? closesAt}) =>
        InterviewRound(
          id: id,
          testId: _testId,
          recruiterId: _rec,
          order: order,
          title: 'Round ${order + 1}',
          kind: RoundKind.chat,
          opensAt: opensAt,
          closesAt: closesAt,
        );

    final now = DateTime.utc(2026, 8, 15, 12);
    final past = now.subtract(const Duration(days: 5));
    final future = now.add(const Duration(days: 5));

    test('the earliest OPEN round is current', () {
      final rounds = [
        r('a', 0, closesAt: past), // closed
        r('b', 1), // open
        r('c', 2), // open too, but later in the sequence
      ];
      expect(activeRoundId(rounds, now), 'b');
    });

    test('with none open, the next one due to open is current', () {
      final rounds = [
        r('a', 0, closesAt: past),
        r('b', 1, opensAt: future),
      ];
      expect(activeRoundId(rounds, now), 'b');
    });

    test('a finished pipeline has no current round', () {
      final rounds = [
        r('a', 0, closesAt: past),
        r('b', 1, closesAt: past),
      ];
      expect(activeRoundId(rounds, now), isNull);
    });

    test('an empty timeline has no current round', () {
      expect(activeRoundId(const [], now), isNull);
    });
  });
}
