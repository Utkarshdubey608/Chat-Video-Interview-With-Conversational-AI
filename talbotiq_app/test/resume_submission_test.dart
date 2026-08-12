// test/resume_submission_test.dart
//
// Step 4: the candidate's résumé round.
//
// Two things are worth locking down here, and neither is the UI:
//
//   1. THE REQUEST CARRIES NO BAR. The criteria, the role and the prompt are all
//      resolved server-side, and this test asserts the app sends only the three
//      fields it is allowed to. If someone later "helpfully" adds the round's
//      criteria to the request payload, the score stops being trustworthy and
//      this fails.
//   2. A LANGUAGE-MODEL SCORE IS PARSED DEFENSIVELY. The score is written by the
//      backend from a model's output; a partial write or an older backend must
//      render as "no score yet" in a list, not throw inside a ListView builder.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:talbotiq/core/net/api_client.dart';
import 'package:talbotiq/core/net/backend_client.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/models/resume_submission.dart';
import 'package:talbotiq/features/interviews/services/resume_service.dart';

/// Captures what was sent and replies with whatever the test set up.
class _StubHttp extends http.BaseClient {
  int status = 200;
  String body = '{}';
  final List<http.BaseRequest> requests = [];
  List<int>? lastBody;

  http.BaseRequest get last => requests.last;
  Map<String, dynamic> get lastJson =>
      jsonDecode(utf8.decode(lastBody!)) as Map<String, dynamic>;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.Request) lastBody = request.bodyBytes;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

const _scoreJson = {
  'interviewId': 'int-1',
  'charCount': 120,
  'model': 'gemini-2.5-flash',
  'score': {
    'overallScore': 78,
    'verdict': 'strong_match',
    'summary': 'Four years of Flutter.',
    'experienceYears': 4.5,
    'strengths': ['Ships production apps'],
    'gaps': ['No Kotlin evidence'],
    'skills': [
      {
        'name': 'Flutter',
        'required': true,
        'score': 88,
        'evidence': '3 years at Acme',
      }
    ],
  },
};

void main() {
  late _StubHttp stub;
  late ResumeService service;

  setUp(() {
    stub = _StubHttp();
    service = ResumeService(
      backend: BackendClient(
        client: ApiClient(client: stub, maxRetries: 0),
        baseUrl: 'https://backend.test',
        tokenProvider: () async => 'test-id-token',
      ),
    );
  });

  group('extraction', () {
    test('posts the PDF and returns the text', () async {
      stub.body = jsonEncode(
          {'text': 'Casey — engineer', 'charCount': 16, 'truncated': false});

      final result = await service.extractText(
          pdfBase64: 'JVBERi0=', fileName: 'casey.pdf');

      expect(result.text, 'Casey — engineer');
      expect(result.charCount, 16);
      expect(result.truncated, isFalse);
      expect(stub.last.url.path, '/api/resume/extract');
      expect(stub.lastJson['pdfBase64'], 'JVBERi0=');
      expect(stub.lastJson['fileName'], 'casey.pdf');
      // Every backend call carries the signed-in user's token.
      expect(stub.last.headers['Authorization'], 'Bearer test-id-token');
    });

    test('non-ASCII survives the round trip', () async {
      // REGRESSION: BackendClient used `response.body`, which decodes with the
      // charset from Content-Type and falls back to latin-1 when there is none —
      // and FastAPI sends a bare `application/json`. Every accent in a résumé
      // came back mangled. Résumés are the worst possible payload for that bug:
      // they are full of names, em dashes and bullets.
      const accented = 'José Muñoz — Sénior Engineer • 5 ans • naïve café';
      stub.body = jsonEncode({'text': accented, 'charCount': accented.length});

      final result = await service.extractText(pdfBase64: 'JVBERi0=');
      expect(result.text, accented);
      expect(result.text, isNot(contains('Ã')));
    });

    test('a truncated résumé is reported, not silently accepted', () async {
      stub.body =
          jsonEncode({'text': 'x' * 30, 'charCount': 30, 'truncated': true});
      final result = await service.extractText(pdfBase64: 'JVBERi0=');
      expect(result.truncated, isTrue);
    });

    test('an empty extraction is an error the candidate can act on', () async {
      stub.body = jsonEncode({'text': '   ', 'charCount': 0});
      await expectLater(
        service.extractText(pdfBase64: 'JVBERi0='),
        throwsA(isA<BackendException>().having(
            (e) => e.message, 'message', contains('paste it instead'))),
      );
    });

    test('a blank file name is omitted rather than sent empty', () async {
      stub.body = jsonEncode({'text': 'Casey — engineer', 'charCount': 16});
      await service.extractText(pdfBase64: 'JVBERi0=', fileName: '   ');
      expect(stub.lastJson.containsKey('fileName'), isFalse);
    });
  });

  group('scoring', () {
    test('the request carries no criteria, role or prompt', () async {
      stub.body = jsonEncode(_scoreJson);

      await service.submitForScoring(
        interviewId: 'int-1',
        resumeText: 'Casey — Flutter engineer with four years of experience.',
        fileName: 'casey.pdf',
      );

      expect(stub.last.url.path, '/api/resume/score');
      // EXACTLY these three. The bar lives on the round document, server-side;
      // anything else here would be a bar the candidate could move.
      expect(
        stub.lastJson.keys.toSet(),
        {'interviewId', 'resumeText', 'fileName'},
      );
    });

    test('returns the parsed score', () async {
      stub.body = jsonEncode(_scoreJson);
      final score = await service.submitForScoring(
          interviewId: 'int-1', resumeText: 'x' * 40);

      expect(score.overallScore, 78);
      expect(score.verdict, ResumeVerdict.strongMatch);
      expect(score.experienceYears, 4.5);
      expect(score.gaps, ['No Kotlin evidence']);
      expect(score.skills.single.name, 'Flutter');
      expect(score.skills.single.required, isTrue);
    });

    test('a response with no score does not read as a failed submission',
        () async {
      // The résumé may well have been stored; what failed is reading it back.
      stub.body = jsonEncode({'interviewId': 'int-1'});
      await expectLater(
        service.submitForScoring(interviewId: 'int-1', resumeText: 'x' * 40),
        throwsA(isA<BackendException>().having((e) => e.message, 'message',
            allOf(contains('was sent'), contains('before resubmitting')))),
      );
    });

    test('a backend error becomes a showable message', () async {
      stub.status = 409;
      stub.body = jsonEncode({'detail': 'This interview has expired.'});
      await expectLater(
        service.submitForScoring(interviewId: 'int-1', resumeText: 'x' * 40),
        throwsA(isA<BackendException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', contains('expired'))),
      );
    });
  });

  group('parsing a score written by a language model', () {
    test('an out-of-range score is clamped on the way in too', () {
      // The backend clamps before storing; this is the second gate, for a
      // document written by an older build.
      expect(ResumeScore.fromMap({'overallScore': 5000})!.overallScore, 100);
      expect(ResumeScore.fromMap({'overallScore': -5})!.overallScore, 0);
    });

    test('an unknown verdict falls back by score, never contradicting it', () {
      // The chip must not read "Weak match" beside a 92.
      expect(
        ResumeScore.fromMap({'overallScore': 92, 'verdict': 'amazing'})!.verdict,
        ResumeVerdict.strongMatch,
      );
      expect(
        ResumeScore.fromMap({'overallScore': 20, 'verdict': null})!.verdict,
        ResumeVerdict.weak,
      );
      expect(
        ResumeScore.fromMap({'overallScore': 55})!.verdict,
        ResumeVerdict.possible,
      );
    });

    test('a malformed skills list drops the bad entries, not the whole score',
        () {
      final score = ResumeScore.fromMap({
        'overallScore': 60,
        'skills': ['not a map', {'name': 'Dart', 'score': 70}, 42],
      })!;
      expect(score.skills.map((s) => s.name), ['Dart']);
      expect(score.overallScore, 60);
    });

    test('blank strings are dropped from strengths and gaps', () {
      final score = ResumeScore.fromMap({
        'overallScore': 60,
        'strengths': ['Real', '  ', ''],
        'gaps': [],
      })!;
      expect(score.strengths, ['Real']);
      expect(score.gaps, isEmpty);
    });

    test('gaps sort ahead of strong skills, must-haves ahead of everything', () {
      final score = ResumeScore.fromMap({
        'overallScore': 60,
        'skills': [
          {'name': 'NiceStrong', 'required': false, 'score': 95},
          {'name': 'MustWeak', 'required': true, 'score': 10},
          {'name': 'MustStrong', 'required': true, 'score': 90},
          {'name': 'NiceWeak', 'required': false, 'score': 20},
        ],
      })!;
      // The recruiter's question is "what is missing", so a missing must-have is
      // the first thing on screen.
      expect(
        score.skillsByConcern.map((s) => s.name),
        ['MustWeak', 'MustStrong', 'NiceWeak', 'NiceStrong'],
      );
    });

    test('an empty or absent score map is no score, not a zero score', () {
      expect(ResumeScore.fromMap(null), isNull);
      expect(ResumeScore.fromMap(const {}), isNull);
    });
  });

  group('the submission as stored on the interview', () {
    test('reads back off a Firestore document', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('interviews').doc('int-1').set({
        'recruiterId': 'rec-1',
        'candidateEmail': 'a@b.com',
        'candidateEmailLower': 'a@b.com',
        'title': 'Résumé screen',
        'type': 'chat',
        'roundId': 'r1',
        'roundKind': 'resume',
        'status': 'completed',
        'resume': {
          'text': 'Casey — Flutter engineer',
          'charCount': 24,
          'fileName': 'casey.pdf',
          'extractedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 10)),
          'score': {'overallScore': 78, 'verdict': 'strong_match'},
        },
      });

      final interview =
          Interview.fromDoc(await db.collection('interviews').doc('int-1').get());

      // A résumé round stores `type: chat`, so routing must use roundKind.
      expect(interview.effectiveRoundKind, RoundKind.resume);

      final submission = ResumeSubmission.fromMap(interview.resume)!;
      expect(submission.text, 'Casey — Flutter engineer');
      expect(submission.fileName, 'casey.pdf');
      expect(submission.hasScore, isTrue);
      expect(submission.score!.overallScore, 78);
    });

    test('a submission with text but no score still shows its text', () {
      // Scoring can fail after the text was captured; the raw résumé is still
      // the most useful thing a recruiter can look at.
      final submission = ResumeSubmission.fromMap({
        'text': 'Casey — engineer',
        'charCount': 16,
      })!;
      expect(submission.hasScore, isFalse);
      expect(submission.text, 'Casey — engineer');
    });

    test('a missing charCount falls back to the text length', () {
      // A partial write must not show "0 characters" beside a full résumé.
      final submission =
          ResumeSubmission.fromMap({'text': 'abcdefghij'})!;
      expect(submission.charCount, 10);
    });

    test('an absent or textless submission is null', () {
      expect(ResumeSubmission.fromMap(null), isNull);
      expect(ResumeSubmission.fromMap(const {}), isNull);
      expect(ResumeSubmission.fromMap({'text': '   '}), isNull);
    });
  });

  group('the app never writes the resume field', () {
    test('neither write map mentions it — the backend owns it', () {
      const interview = Interview(
        id: 'int-1',
        recruiterId: 'rec-1',
        recruiterEmail: 'rec@co.com',
        candidateEmail: 'a@b.com',
        candidateEmailLower: 'a@b.com',
        type: InterviewType.chat,
        title: 'T',
        prompt: '',
        questions: [],
        avatar: AvatarConfig(replicaId: ''),
        durationMinutes: 15,
        status: InterviewStatus.assigned,
        resume: {'text': 'forged', 'score': {'overallScore': 100}},
      );

      // firestore.rules blocks a candidate write to `resume`, so a client that
      // included it would fail the whole update — silently breaking unrelated
      // writes like "mark in progress".
      expect(interview.toCreateMap().containsKey('resume'), isFalse);
      expect(interview.toUpdateMap().containsKey('resume'), isFalse);
    });
  });
}
