// lib/core/security/recruiter_credentials.dart
//
// Immutable value object for a recruiter/org's third-party API credentials.
// Kept separate from any storage concern so the transport (Firestore today,
// a server-side proxy tomorrow) can change without touching callers.

class RecruiterCredentials {
  const RecruiterCredentials({
    this.tavusKey = '',
    this.geminiKey = '',
    this.humeKey = '',
    this.deepgramKey = '',
    this.awsKey = '',
    this.anthropicKey = '',
    this.awsProxyUrl = '',
    this.webhookUrl = '',
  });

  final String tavusKey;
  final String geminiKey;
  final String humeKey;
  final String deepgramKey;
  final String awsKey;
  final String anthropicKey;
  final String awsProxyUrl;
  final String webhookUrl;

  static String _str(Object? v) => v is String ? v.trim() : '';

  factory RecruiterCredentials.fromMap(Map<String, dynamic> d) =>
      RecruiterCredentials(
        tavusKey: _str(d['tavusKey']),
        geminiKey: _str(d['geminiKey']),
        humeKey: _str(d['humeKey']),
        deepgramKey: _str(d['deepgramKey']),
        awsKey: _str(d['awsKey']),
        anthropicKey: _str(d['anthropicKey']),
        awsProxyUrl: _str(d['awsProxyUrl']),
        webhookUrl: _str(d['webhookUrl']),
      );

  Map<String, dynamic> toMap() => {
        'tavusKey': tavusKey,
        'deepgramKey': deepgramKey,
        'humeKey': humeKey,
        'awsKey': awsKey,
        'anthropicKey': anthropicKey,
        'geminiKey': geminiKey,
        'awsProxyUrl': awsProxyUrl,
        'webhookUrl': webhookUrl,
      };

  /// Applies per-test [overrides] (from `Interview.keyOverrides`): any non-empty
  /// override wins over the stored value.
  RecruiterCredentials withOverrides(Map<String, String> overrides) {
    String pick(String key, String current) {
      final o = overrides[key];
      return (o != null && o.trim().isNotEmpty) ? o.trim() : current;
    }

    return RecruiterCredentials(
      tavusKey: pick('tavusKey', tavusKey),
      geminiKey: pick('geminiKey', geminiKey),
      humeKey: pick('humeKey', humeKey),
      deepgramKey: pick('deepgramKey', deepgramKey),
      awsKey: pick('awsKey', awsKey),
      anthropicKey: pick('anthropicKey', anthropicKey),
      awsProxyUrl: pick('awsProxyUrl', awsProxyUrl),
      webhookUrl: pick('webhookUrl', webhookUrl),
    );
  }
}
