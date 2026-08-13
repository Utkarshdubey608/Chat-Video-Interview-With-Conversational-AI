// lib/shared/widgets/iframe_host_allowlist.dart
//
// Allowlist of hosts an interview WebView may navigate to: the initial Tavus
// conversation URL host plus the Tavus / Daily.co video infrastructure a live
// call relies on. Shared by the mobile (webview_flutter, iframe_view_stub.dart)
// and desktop (flutter_inappwebview, desktop_webview.dart) implementations so
// the security boundary is defined in exactly one place.

bool isAllowedIframeHost(String? initialHost, String host) {
  if (host.isEmpty) return false;
  final h = host.toLowerCase();
  if (h == initialHost) return true;
  const suffixes = <String>['daily.co', 'tavus.io', 'tavusapi.com'];
  for (final s in suffixes) {
    if (h == s || h.endsWith('.$s')) return true;
  }
  return false;
}
