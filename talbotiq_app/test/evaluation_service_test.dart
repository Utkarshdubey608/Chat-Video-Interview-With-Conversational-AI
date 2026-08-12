// test/evaluation_service_test.dart
//
// Handing a finished interview to the server instead of scoring it on the device.
//
// The property under test is what the old design got wrong: the request carries
// ONLY answers, and the reply is an acknowledgement rather than a score. A score
// in the reply would mean the device had waited for a model — which is the shape
// that produced the 504s, because `ApiClient` retries 429 and 503 but not 504.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:talbotiq/core/net/api_client.dart';
import 'package:talbotiq/core/net/backend_client.dart';
import 'package:talbotiq/features/interviews/services/evaluation_service.dart';

class _StubHttp extends http.BaseClient {
  int status = 202;
  String body = '{"interviewId":"int-1","status":"scoring","responses":2}';
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

const _responses = [
  {'question': 'Tell me about yourself.', 'answer': 'Four years of Flutter.'},
  {'question': 'Describe a hard bug.', 'answer': 'A race in the sync layer.'},
];

void main() {
  late _StubHttp stub;
  late EvaluationService service;

  setUp(() {
    stub = _StubHttp();
    service = EvaluationService(
      backend: BackendClient(
        client: ApiClient(client: stub, maxRetries: 0),
        baseUrl: 'https://backend.test',
        tokenProvider: () async => 'test-id-token',
      ),
    );
  });

  test('posts to the interview\'s own evaluate route', () async {
    await service.submit(interviewId: 'int-1', responses: _responses);

    expect(stub.last.url.path, '/api/interviews/int-1/evaluate');
    expect(stub.last.method, 'POST');
    expect(stub.last.headers['Authorization'], 'Bearer test-id-token');
  });

  test('sends ONLY the answers — no score, prompt or model', () async {
    await service.submit(interviewId: 'int-1', responses: _responses);

    // Exactly one key. The bar, the prompt and the model all live server-side;
    // anything else here would be something a tampered client could choose.
    expect(stub.lastJson.keys.toSet(), {'responses'});
    expect((stub.lastJson['responses'] as List).length, 2);
  });

  test('a 202 is an acknowledgement, not a score', () async {
    final ack = await service.submit(
        interviewId: 'int-1', responses: _responses);

    expect(ack.isScoring, isTrue);
    expect(ack.responses, 2);
    // Nothing here to render as a result — by design. The score arrives on the
    // interview document once the server's background task finishes.
    expect(ack.status, 'scoring');
  });

  test('"too little was said" is still a successful submission', () async {
    // The answers were stored; there simply was not enough to score. From the
    // candidate's side that is a completed submission.
    stub.body =
        '{"interviewId":"int-1","status":"stored_without_score","responses":1}';

    final ack = await service.submit(
        interviewId: 'int-1', responses: _responses);

    expect(ack.isScoring, isFalse);
    expect(ack.status, 'stored_without_score');
  });

  test('an unknown status is treated as scoring rather than as a failure',
      () async {
    // A newer server saying something this build has not heard of must not read
    // as "your interview was lost".
    stub.body = '{"interviewId":"int-1","status":"queued","responses":2}';
    final ack = await service.submit(
        interviewId: 'int-1', responses: _responses);
    expect(ack.status, 'queued');
    expect(ack.isScoring, isFalse);
  });

  test('a rejected submission throws, because that loses the answers', () async {
    stub.status = 403;
    stub.body = jsonEncode({'detail': 'This interview is not assigned to you.'});

    await expectLater(
      service.submit(interviewId: 'int-1', responses: _responses),
      throwsA(isA<BackendException>()
          .having((e) => e.statusCode, 'statusCode', 403)
          .having((e) => e.message, 'message', contains('not assigned'))),
    );
  });

  test('a gateway timeout surfaces instead of being swallowed', () async {
    // The failure that started all this. It must reach the caller so the answers
    // can be kept locally for the recruiter's retry — not vanish.
    stub.status = 504;
    stub.body = '<html>gateway timeout</html>';

    await expectLater(
      service.submit(interviewId: 'int-1', responses: _responses),
      throwsA(isA<BackendException>()
          .having((e) => e.statusCode, 'statusCode', 504)),
    );
  });

  test('non-ASCII answers survive the round trip', () async {
    stub.body =
        '{"interviewId":"int-1","status":"scoring","responses":1}';
    await service.submit(
      interviewId: 'int-1',
      responses: const [
        {'question': 'Nom ?', 'answer': 'José Muñoz — ingénieur'},
      ],
    );

    final sent = (stub.lastJson['responses'] as List).first as Map;
    expect(sent['answer'], 'José Muñoz — ingénieur');
  });
}
