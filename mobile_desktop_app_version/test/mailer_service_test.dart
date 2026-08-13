// Unit tests for the mailer client: the exact requests it puts on the wire
// (owner scoping, template id, per-candidate interview links), how it reads the
// responses back, and how backend errors become messages a recruiter can act
// on. No network — a MockClient stands in for the server.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:talbotiq/core/deep_link/deep_link_service.dart';
import 'package:talbotiq/core/net/api_client.dart';
import 'package:talbotiq/features/mailer/models/email_template.dart';
import 'package:talbotiq/features/mailer/services/mailer_service.dart';

/// Builds a service whose HTTP calls are answered by [handler], recording the
/// request each time so tests can assert on what was actually sent.
({MailerService service, List<http.Request> requests}) _service(
  Future<http.Response> Function(http.Request) handler, {
  String baseUrl = 'https://mail.example.com',
}) {
  final requests = <http.Request>[];
  final client = MockClient((req) {
    requests.add(req);
    return handler(req);
  });
  return (
    service: MailerService(
      baseUrl: baseUrl,
      client: ApiClient(client: client, maxRetries: 0),
    ),
    requests: requests,
  );
}

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _templateListBody = {
  'templates': [
    {
      'id': 'builtin:interview_invite',
      'name': 'Interview invite',
      'subject': 'Invited: {{ interview_title }}',
      'body': '<p>Hi {{ candidate_name }}</p>',
      'is_html': true,
      'source': 'builtin',
      'is_default': true,
    },
    {
      'id': 'abc123',
      'name': 'Round 2',
      'subject': 'Round 2',
      'body': 'body',
      'is_html': false,
      'source': 'custom',
      'owner_email': 'vaishnavi@talbotiq.com',
    },
  ],
  'default_template_id': 'builtin:interview_invite',
  'variables': {'candidate_name': 'The candidate.'},
  'warning': null,
};

void main() {
  group('renderTemplate', () {
    test('substitutes placeholders and blanks unknown ones', () {
      expect(
        renderTemplate('Hi {{ candidate_name }} — {{ nope }}!', {'candidate_name': 'Ada'}),
        'Hi Ada — !',
      );
    });

    test('tolerates spacing variants', () {
      expect(renderTemplate('{{name}}/{{  name  }}', {'name': 'x'}), 'x/x');
    });
  });

  group('listTemplates', () {
    test('scopes the request to the recruiter and parses the catalog', () async {
      final h = _service((_) async => _json(_templateListBody));
      final catalog = await h.service.listTemplates(ownerEmail: 'Vaishnavi@talbotiq.com ');

      final req = h.requests.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/api/templates');
      // Without this the backend would return built-ins only.
      expect(req.url.queryParameters['owner_email'], 'Vaishnavi@talbotiq.com');

      expect(catalog.templates, hasLength(2));
      expect(catalog.defaultTemplate?.id, 'builtin:interview_invite');
      expect(catalog.templates.first.isBuiltin, isTrue);
      expect(catalog.templates.last.ownerEmail, 'vaishnavi@talbotiq.com');
      expect(catalog.templates.last.isHtml, isFalse);
      expect(catalog.variables, containsPair('candidate_name', 'The candidate.'));
    });

    test('never sends an X-API-Key header', () async {
      // The mailer used to carry a user-entered shared secret. There is no key
      // in the app any more, so a request must not claim to have one.
      final h = _service((_) async => _json(_templateListBody));
      await h.service.listTemplates(ownerEmail: 'a@b.com');
      expect(h.requests.single.headers.containsKey('X-API-Key'), isFalse);
    });

    test('joins paths correctly when the base URL has a trailing slash', () async {
      final h = _service(
        (_) async => _json(_templateListBody),
        baseUrl: 'https://mail.example.com/',
      );
      await h.service.listTemplates(ownerEmail: 'a@b.com');
      expect(h.requests.single.url.toString(),
          startsWith('https://mail.example.com/api/templates?'));
    });
  });

  group('createTemplate', () {
    test('binds the new template to the recruiter email', () async {
      final h = _service((_) async => _json({
            'id': 'new1',
            'name': 'Mine',
            'subject': 's',
            'body': 'b',
            'is_html': true,
            'source': 'custom',
            'owner_email': 'me@talbotiq.com',
          }, status: 201));

      final saved = await h.service.createTemplate(
        ownerEmail: 'me@talbotiq.com',
        name: 'Mine',
        subject: 's',
        body: 'b',
        recruiterId: 'uid-1',
      );

      final sent = jsonDecode(h.requests.single.body) as Map<String, dynamic>;
      expect(sent['owner_email'], 'me@talbotiq.com');
      expect(sent['recruiter_id'], 'uid-1');
      expect(sent['is_html'], true);
      expect(saved.id, 'new1');
      expect(saved.isBuiltin, isFalse);
    });
  });

  group('send', () {
    test('gives every candidate their own interview link', () async {
      final h = _service((_) async => _json({
            'total': 2,
            'sent': 2,
            'failed': 0,
            'template_id': 'abc123',
            'provider': 'smtp',
            'subject_preview': 'Invited: Flutter Role',
            'results': [
              {'email': 'ada@x.com', 'status': 'sent'},
              {'email': 'grace@x.com', 'status': 'sent'},
            ],
          }));

      final report = await h.service.send(
        ownerEmail: 'me@talbotiq.com',
        templateId: 'abc123',
        sharedContext: {'interview_title': 'Flutter Role'},
        recipients: [
          MailRecipient(
            email: 'ada@x.com',
            context: {'interview_link': DeepLinkService.interviewLink('i1')},
          ),
          MailRecipient(
            email: 'grace@x.com',
            context: {'interview_link': DeepLinkService.interviewLink('i2')},
          ),
        ],
      );

      final sent = jsonDecode(h.requests.single.body) as Map<String, dynamic>;
      expect(sent['template_id'], 'abc123');
      expect(sent['owner_email'], 'me@talbotiq.com');
      expect(sent['shared_context'], {'interview_title': 'Flutter Role'});
      final recipients = sent['recipients'] as List;
      expect(recipients, hasLength(2));
      expect(recipients[0]['context']['interview_link'], 'talbotiq://interview/i1');
      expect(recipients[1]['context']['interview_link'], 'talbotiq://interview/i2');

      expect(report.allSent, isTrue);
      expect(report.isDryRun, isFalse);
    });

    test('omits template_id so the backend applies its default', () async {
      final h = _service((_) async => _json({
            'total': 1,
            'sent': 1,
            'failed': 0,
            'template_id': 'builtin:interview_invite',
            'provider': 'dry_run',
            'subject_preview': 's',
            'results': [
              {'email': 'ada@x.com', 'status': 'sent'},
            ],
          }));

      final report = await h.service.send(
        ownerEmail: 'me@talbotiq.com',
        recipients: const [MailRecipient(email: 'ada@x.com')],
      );

      final sent = jsonDecode(h.requests.single.body) as Map<String, dynamic>;
      expect(sent.containsKey('template_id'), isFalse);
      expect(report.templateId, 'builtin:interview_invite');
      expect(report.isDryRun, isTrue);
    });

    test('reports per-recipient failures instead of throwing', () async {
      final h = _service((_) async => _json({
            'total': 2,
            'sent': 1,
            'failed': 1,
            'template_id': 't',
            'provider': 'smtp',
            'subject_preview': 's',
            'results': [
              {'email': 'ok@x.com', 'status': 'sent'},
              {'email': 'bad@x.com', 'status': 'failed', 'error': 'mailbox unavailable'},
            ],
          }));

      final report = await h.service.send(
        ownerEmail: 'me@talbotiq.com',
        recipients: const [
          MailRecipient(email: 'ok@x.com'),
          MailRecipient(email: 'bad@x.com'),
        ],
      );

      expect(report.allSent, isFalse);
      expect(report.failures.single.email, 'bad@x.com');
      expect(report.failures.single.error, 'mailbox unavailable');
    });
  });

  group('errors', () {
    test("surfaces the backend's own explanation", () async {
      final h = _service((_) async => _json(
            {'detail': 'EMAIL_APP_PASSWORD must be a 16-character Google App Password'},
            status: 503,
          ));

      await expectLater(
        h.service.send(
          ownerEmail: 'me@talbotiq.com',
          recipients: const [MailRecipient(email: 'a@x.com')],
        ),
        throwsA(isA<MailerException>()
            .having((e) => e.isNotConfigured, 'isNotConfigured', isTrue)
            .having((e) => e.message, 'message', contains('16-character'))),
      );
    });

    test('reads the first field error out of a 422', () async {
      final h = _service((_) async => _json({
            'detail': [
              {'msg': 'value is not a valid email address', 'loc': ['body', 'recipients', 0]},
            ],
          }, status: 422));

      await expectLater(
        h.service.send(
          ownerEmail: 'me@talbotiq.com',
          recipients: const [MailRecipient(email: 'nope')],
        ),
        throwsA(isA<MailerException>()
            .having((e) => e.message, 'message', contains('not a valid email'))),
      );
    });

    test('refuses to call anything when no server is configured', () async {
      final service = MailerService(baseUrl: '   ');
      expect(service.isConfigured, isFalse);
      await expectLater(
        service.listTemplates(ownerEmail: 'a@b.com'),
        throwsA(isA<MailerException>()
            .having((e) => e.message, 'message', contains('Settings'))),
      );
    });
  });
}
