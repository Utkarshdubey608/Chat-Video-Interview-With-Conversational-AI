// lib/features/mailer/models/send_report.dart
//
// What POST /api/emails/send answers with: one row per candidate, so a single
// bad address is reported without hiding the ones that went out.

class SendOutcome {
  const SendOutcome({required this.email, required this.status, this.error});

  final String email;

  /// 'sent' or 'failed'.
  final String status;
  final String? error;

  bool get isSent => status == 'sent';

  factory SendOutcome.fromJson(Map<String, dynamic> json) => SendOutcome(
        email: (json['email'] ?? '') as String,
        status: (json['status'] ?? 'failed') as String,
        error: json['error'] as String?,
      );
}

class SendReport {
  const SendReport({
    required this.total,
    required this.sent,
    required this.failed,
    required this.templateId,
    required this.provider,
    required this.subjectPreview,
    required this.results,
  });

  final int total;
  final int sent;
  final int failed;
  final String templateId;

  /// 'smtp', 'gmail_api' or 'dry_run' — dry_run means the backend logged the
  /// mail instead of delivering it.
  final String provider;
  final String subjectPreview;
  final List<SendOutcome> results;

  bool get allSent => failed == 0 && sent > 0;
  bool get isDryRun => provider == 'dry_run';

  Iterable<SendOutcome> get failures => results.where((r) => !r.isSent);

  factory SendReport.fromJson(Map<String, dynamic> json) => SendReport(
        total: (json['total'] as num?)?.toInt() ?? 0,
        sent: (json['sent'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        templateId: (json['template_id'] ?? '') as String,
        provider: (json['provider'] ?? '') as String,
        subjectPreview: (json['subject_preview'] ?? '') as String,
        results: ((json['results'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SendOutcome.fromJson)
            .toList(),
      );
}
