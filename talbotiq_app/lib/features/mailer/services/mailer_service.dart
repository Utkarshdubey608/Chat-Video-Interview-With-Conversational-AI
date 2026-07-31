// lib/features/mailer/services/mailer_service.dart
//
// Client for the TalbotIQ mailer backend (backend/). Three calls, mirroring the
// service's three endpoints:
//
//   listTemplates()  GET  /api/templates?owner_email=…  built-ins + mine
//   createTemplate() POST /api/templates                save one of mine
//   send()           POST /api/emails/send              mail a list of candidates
//
// The base URL and optional API key come from Settings (AppStore), so the same
// build can point at a local server or a deployed one. Transport concerns
// (timeout, retry/backoff) are the shared ApiClient's job; this only owns the
// payload shapes and error messages.

import 'dart:convert';

import 'package:talbotiq/core/net/api_client.dart';
import 'package:talbotiq/features/mailer/models/email_template.dart';
import 'package:talbotiq/features/mailer/models/send_report.dart';
import 'package:talbotiq/shared/providers/app_store.dart';

/// A mailer call that failed, with a message already fit to show a recruiter.
class MailerException implements Exception {
  const MailerException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// The backend answers 503 when sending or Firestore isn't configured yet —
  /// the one failure a recruiter can act on themselves.
  bool get isNotConfigured => statusCode == 503;

  @override
  String toString() => message;
}

/// One candidate to mail, plus the variables unique to them.
class MailRecipient {
  const MailRecipient({required this.email, this.name, this.context = const {}});

  final String email;
  final String? name;
  final Map<String, String> context;

  Map<String, dynamic> toJson() => {
        'email': email,
        if (name != null && name!.trim().isNotEmpty) 'name': name!.trim(),
        if (context.isNotEmpty) 'context': context,
      };
}

/// Templates as the list endpoint returns them: the pickable list plus the id
/// used when none is chosen, the variables the editor can offer, and a warning
/// when the recruiter's own templates couldn't be read (built-ins still work).
class TemplateCatalog {
  const TemplateCatalog({
    required this.templates,
    required this.defaultTemplateId,
    required this.variables,
    this.warning,
  });

  final List<EmailTemplate> templates;
  final String defaultTemplateId;
  final Map<String, String> variables;
  final String? warning;

  EmailTemplate? get defaultTemplate {
    for (final t in templates) {
      if (t.id == defaultTemplateId) return t;
    }
    return templates.isEmpty ? null : templates.first;
  }
}

class MailerService {
  MailerService({required this.baseUrl, this.apiKey = '', ApiClient? client})
      : _client = client ?? ApiClient(timeout: const Duration(seconds: 45));

  /// Root of the mailer backend, e.g. `https://mail.talbotiq.com`.
  final String baseUrl;

  /// Sent as `X-API-Key` when the backend has one configured.
  final String apiKey;

  final ApiClient _client;

  /// Builds a service from the values a recruiter saved in Settings.
  factory MailerService.fromStore(AppStore store) => MailerService(
        baseUrl: store.mailerBaseUrl,
        apiKey: store.mailerApiKey,
      );

  /// False when no backend URL is configured — callers hide the email options
  /// rather than failing at send time.
  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.trim().isNotEmpty) 'X-API-Key': apiKey.trim(),
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final parsed = Uri.parse('$root$path');
    return query == null || query.isEmpty
        ? parsed
        : parsed.replace(queryParameters: {...parsed.queryParameters, ...query});
  }

  /// Built-in templates plus the ones [ownerEmail] saved. Never returns another
  /// recruiter's templates — the backend scopes the query by this address.
  Future<TemplateCatalog> listTemplates({required String ownerEmail}) async {
    _requireConfigured();
    final resp = await _guard(
      () => _client.get(
        _uri('/api/templates', {'owner_email': ownerEmail.trim()}),
        headers: _headers,
      ),
      'load templates',
    );
    final body = _decode(resp.body, 'load templates');
    return TemplateCatalog(
      templates: ((body['templates'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EmailTemplate.fromJson)
          .toList(),
      defaultTemplateId: (body['default_template_id'] ?? '') as String,
      variables: ((body['variables'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
      warning: body['warning'] as String?,
    );
  }

  /// Saves a template owned by [ownerEmail]; only they will see it listed.
  Future<EmailTemplate> createTemplate({
    required String ownerEmail,
    required String name,
    required String subject,
    required String body,
    String? description,
    bool isHtml = true,
    String? recruiterId,
  }) async {
    _requireConfigured();
    final resp = await _guard(
      () => _client.post(
        _uri('/api/templates'),
        headers: _headers,
        body: jsonEncode({
          'owner_email': ownerEmail.trim(),
          'name': name.trim(),
          'subject': subject,
          'body': body,
          'is_html': isHtml,
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          if (recruiterId != null && recruiterId.isNotEmpty) 'recruiter_id': recruiterId,
        }),
      ),
      'save the template',
    );
    return EmailTemplate.fromJson(_decode(resp.body, 'save the template'));
  }

  /// Mails every recipient using [templateId] (the default template when null).
  /// Resolves even when some addresses fail — inspect [SendReport.failures].
  Future<SendReport> send({
    required List<MailRecipient> recipients,
    required String ownerEmail,
    String? templateId,
    Map<String, String> sharedContext = const {},
  }) async {
    _requireConfigured();
    final resp = await _guard(
      () => _client.post(
        _uri('/api/emails/send'),
        headers: _headers,
        body: jsonEncode({
          'owner_email': ownerEmail.trim(),
          if (templateId != null && templateId.isNotEmpty) 'template_id': templateId,
          if (sharedContext.isNotEmpty) 'shared_context': sharedContext,
          'recipients': recipients.map((r) => r.toJson()).toList(),
        }),
      ),
      'send the emails',
    );
    return SendReport.fromJson(_decode(resp.body, 'send the emails'));
  }

  void _requireConfigured() {
    if (!isConfigured) {
      throw const MailerException(
        'No mail server configured. Add the mailer URL in Settings → Email.',
      );
    }
  }

  /// Runs a request, turning transport failures and non-2xx responses into a
  /// [MailerException] carrying the backend's own `detail` message (which is
  /// written to be shown as-is, e.g. "EMAIL_APP_PASSWORD must be a 16-character…").
  Future<dynamic> _guard(Future Function() run, String action) async {
    final dynamic resp;
    try {
      resp = await run();
    } on ApiException catch (e) {
      throw MailerException(
        e.isTimeout
            ? 'The mail server did not respond. Check that it is running and reachable.'
            : 'Could not $action: ${e.message}',
        statusCode: e.statusCode,
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw MailerException(
        _detail(resp.body) ?? 'Could not $action (HTTP ${resp.statusCode}).',
        statusCode: resp.statusCode,
      );
    }
    return resp;
  }

  /// FastAPI puts the human-readable reason in `detail` (a string for our
  /// HTTPExceptions, a list of field errors for validation failures).
  String? _detail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] != null) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] != null) return first['msg'].toString();
        }
      }
    } catch (_) {
      // Not JSON — fall through to the generic message.
    }
    return null;
  }

  Map<String, dynamic> _decode(String body, String action) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through.
    }
    throw MailerException('The mail server returned an unexpected response to $action.');
  }

  void dispose() => _client.close();
}
