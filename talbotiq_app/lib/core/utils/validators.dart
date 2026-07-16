// lib/core/utils/validators.dart
//
// Centralised input validation so every screen enforces the same rules. Auth,
// candidate assignment, session config, and Settings all previously validated
// (or failed to validate) emails and URLs inconsistently.

class Validators {
  Validators._();

  // Pragmatic email pattern: one @, a dotted domain, no spaces. Deliberately
  // not RFC-5322-exhaustive — it rejects the mistakes users actually make
  // (missing @, trailing spaces, no TLD) without rejecting valid addresses.
  static final RegExp _email = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );

  static bool isValidEmail(String? value) {
    if (value == null) return false;
    final v = value.trim();
    return v.isNotEmpty && v.length <= 254 && _email.hasMatch(v);
  }

  /// Returns a user-facing error string, or null when [value] is a valid email.
  static String? emailError(String? value) =>
      isValidEmail(value) ? null : 'Enter a valid email address.';

  /// A safe outbound URL: a well-formed absolute `https` (or `http` for
  /// localhost dev) URL with a real host. Blocks the SSRF/scheme-injection
  /// surface (`javascript:`, `file://`, `http://169.254.169.254/…`, opaque
  /// URIs) that the webhook / AWS-proxy / virtual-background fields accepted.
  static bool isSafeHttpUrl(String? value, {bool allowHttpLocalhost = true}) {
    if (value == null) return false;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    if (allowHttpLocalhost &&
        uri.scheme == 'http' &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
      return true;
    }
    return false;
  }

  static String? httpUrlError(String? value, {bool required = true}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return required ? 'Enter a URL.' : null;
    return isSafeHttpUrl(v) ? null : 'Enter a valid https URL.';
  }

  /// Clamp a user-entered integer into an inclusive range, falling back to
  /// [fallback] when the text isn't a parseable int. Used for the session
  /// timeout / duration fields that previously accepted negatives and huge
  /// values.
  static int clampedInt(String? text, {
    required int min,
    required int max,
    required int fallback,
  }) {
    final parsed = int.tryParse((text ?? '').trim());
    if (parsed == null) return fallback;
    return parsed.clamp(min, max);
  }
}
