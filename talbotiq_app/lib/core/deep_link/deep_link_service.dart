// lib/core/deep_link/deep_link_service.dart
//
// Deep-linking entry point for candidate invite links.
//
// A recruiter sends a candidate a link; tapping it opens the app straight on
// their assigned interview. Two link families are supported:
//
//   1. Custom scheme (works purely client-side, no server config required):
//        talbotiq://interview/<interviewId>
//
//   2. HTTPS App Links / Universal Links (needs a deployed domain — see the
//      TODO(deploy) markers in AndroidManifest.xml + ios/Runner/Info.plist):
//        https://<any-host>/take/<interviewId>
//        https://<any-host>/interview/<interviewId>
//
// The service is intentionally thin: it wraps the `app_links` package, parses
// an incoming Uri into a [DeepLinkTarget], and exposes an initial-link future
// plus a stream of subsequent links. It never navigates on its own — main.dart
// owns navigation and the auth flow owns the "consume after login" behaviour
// via [PendingDeepLink].

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Parsed result of a supported deep link.
@immutable
class DeepLinkTarget {
  const DeepLinkTarget({required this.interviewId});

  /// The Firestore interview document id the link points at.
  final String interviewId;

  @override
  String toString() => 'DeepLinkTarget(interviewId: $interviewId)';

  @override
  bool operator ==(Object other) =>
      other is DeepLinkTarget && other.interviewId == interviewId;

  @override
  int get hashCode => interviewId.hashCode;
}

/// Holds an interview id parsed from a deep link that has not yet been acted
/// on. This survives the auth flow: if the app opens from a link while the
/// candidate is signed out, the id is parked here, [AuthGate] shows the login
/// page, and after sign-in the candidate flow can read + clear it.
///
/// Exposed as a [ValueNotifier] so widgets can `ValueListenableBuilder` on it.
///
/// Consumed in `candidate_home.dart` (`_consumePendingDeepLink`): once the
/// candidate is authenticated and their interview list has loaded, it calls
/// [take] to read+clear the parked id and opens that interview via the launch
/// adapters. This notifier is the hand-off point between the two.
class PendingDeepLink {
  PendingDeepLink._();

  /// App-lifetime singleton.
  static final PendingDeepLink instance = PendingDeepLink._();

  /// The pending interview id, or null when nothing is waiting to be consumed.
  final ValueNotifier<String?> interviewId = ValueNotifier<String?>(null);

  /// Parks an interview id to be consumed after auth.
  void set(String id) {
    if (id.isEmpty) return;
    interviewId.value = id;
  }

  /// Returns the pending id (if any) and clears it in one step. Idempotent:
  /// a second call returns null. This is the intended consumption API for the
  /// candidate flow.
  String? take() {
    final id = interviewId.value;
    interviewId.value = null;
    return id;
  }

  /// Clears any pending id without reading it.
  void clear() => interviewId.value = null;
}

/// Wraps `app_links` and turns raw [Uri]s into [DeepLinkTarget]s.
class DeepLinkService {
  DeepLinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  /// Path segments that precede an interview id in a supported link, e.g.
  /// `/take/<id>`, `/interview/<id>`. Also matches the custom-scheme host
  /// `talbotiq://interview/<id>`, where "interview" arrives as the host.
  static const Set<String> _interviewMarkers = {'interview', 'take'};

  /// The custom scheme handled entirely client-side (no server config).
  static const String customScheme = 'talbotiq';

  /// Returns the link the app was launched with, already parsed. Null when the
  /// app was launched normally or the launch link is unsupported/malformed.
  Future<DeepLinkTarget?> getInitialTarget() async {
    try {
      final uri = await _appLinks.getInitialLink();
      return parse(uri);
    } catch (e) {
      // app_links can throw on some platforms during cold start; never let a
      // deep-link failure crash app startup.
      debugPrint('DeepLinkService.getInitialTarget failed: $e');
      return null;
    }
  }

  /// Stream of parsed targets from links received while the app is running.
  /// Unsupported/malformed links are silently dropped (never emitted).
  Stream<DeepLinkTarget> get targetStream => _appLinks.uriLinkStream
      .map(parse)
      .where((t) => t != null)
      .cast<DeepLinkTarget>();

  /// Parses a raw [Uri] into a [DeepLinkTarget], or null if unsupported.
  ///
  /// Handled shapes:
  ///   talbotiq://interview/<id>          -> host="interview", seg[0]=<id>
  ///   https://host/take/<id>             -> seg = [take, <id>]
  ///   https://host/interview/<id>        -> seg = [interview, <id>]
  ///   talbotiq://interview?id=<id>       -> query fallback
  ///
  /// Robust to null, empty, trailing slashes, and extra path segments.
  @visibleForTesting
  static DeepLinkTarget? parse(Uri? uri) {
    if (uri == null) return null;
    try {
      final segments =
          uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();

      // Custom scheme: talbotiq://interview/<id> — "interview" is the host.
      final host = uri.host.trim().toLowerCase();
      if (uri.scheme.toLowerCase() == customScheme) {
        if (_interviewMarkers.contains(host)) {
          if (segments.isNotEmpty) {
            return _target(segments.first);
          }
          // talbotiq://interview?id=<id>
          return _target(uri.queryParameters['id']);
        }
        // talbotiq://<id> (host itself is the id) — tolerate it.
        if (host.isNotEmpty) return _target(host);
        return null;
      }

      // HTTPS (and http) App Links: look for a marker segment followed by id.
      for (var i = 0; i < segments.length - 1; i++) {
        if (_interviewMarkers.contains(segments[i].toLowerCase())) {
          return _target(segments[i + 1]);
        }
      }
      return null;
    } catch (e) {
      debugPrint('DeepLinkService.parse failed for "$uri": $e');
      return null;
    }
  }

  static DeepLinkTarget? _target(String? id) {
    final trimmed = id?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return DeepLinkTarget(interviewId: trimmed);
  }
}
