// lib/widgets/iframe_view_stub.dart
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Platform-specific imports for camera/mic permission grants inside the WebView.
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'package:talbotiq/core/utils/desktop_platform.dart';

/// `webview_flutter` (used by [_MobileWebView]) has no Windows/macOS desktop
/// backend, so desktop uses `flutter_inappwebview` (WebView2 on Windows,
/// WKWebView on macOS) instead. Android/iOS keep the original, already
/// battle-tested `webview_flutter` implementation unchanged.
Widget buildIframe(String url) {
  if (isDesktopPlatform) {
    return _DesktopWebView(url: url);
  }
  return _MobileWebView(url: url);
}

/// Host allowlist shared by both the mobile and desktop WebView
/// implementations: only the initial Tavus conversation URL host plus the
/// Tavus/Daily.co video infrastructure a live call relies on may be
/// navigated to while the WebView holds camera/mic permission.
bool _isAllowedHost(String host, String? initialHost) {
  if (host.isEmpty) return false;
  final h = host.toLowerCase();
  if (h == initialHost) return true;
  const suffixes = <String>['daily.co', 'tavus.io', 'tavusapi.com'];
  for (final s in suffixes) {
    if (h == s || h.endsWith('.$s')) return true;
  }
  return false;
}

class _DesktopWebView extends StatefulWidget {
  final String url;
  const _DesktopWebView({required this.url});

  @override
  State<_DesktopWebView> createState() => _DesktopWebViewState();
}

class _DesktopWebViewState extends State<_DesktopWebView> {
  String? _error;
  bool _permissionsGranted = false;
  late final String? _initialHost = Uri.tryParse(widget.url)?.host.toLowerCase();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // macOS gates camera/mic via TCC (requires the usage-description keys in
    // Info.plist + the device entitlements). Windows has no equivalent OS-level
    // prompt for a desktop app, so permission_handler reports granted there;
    // the actual camera/mic grant on Windows happens via the WebView2
    // PermissionRequested handling below (onPermissionRequest).
    final statuses = await [Permission.camera, Permission.microphone].request();
    final camOk = statuses[Permission.camera]?.isGranted ?? false;
    final micOk = statuses[Permission.microphone]?.isGranted ?? false;

    if (!mounted) return;
    if (!camOk || !micOk) {
      setState(() {
        _error = 'Camera and microphone access are required for the interview. '
            'Please grant the permissions and try again.';
      });
      return;
    }
    setState(() => _permissionsGranted = true);
  }

  NavigationActionPolicy _decideNavigation(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return NavigationActionPolicy.CANCEL;
    if (uri.scheme == 'about' || uri.scheme == 'blob' || uri.scheme == 'data') {
      return NavigationActionPolicy.ALLOW;
    }
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        _isAllowedHost(uri.host, _initialHost)) {
      return NavigationActionPolicy.ALLOW;
    }
    debugPrint('Blocked desktop WebView navigation to $url');
    return NavigationActionPolicy.CANCEL;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () {
                  setState(() {
                    _error = null;
                    _permissionsGranted = false;
                  });
                  _requestPermissions();
                },
              ),
              TextButton(
                onPressed: openAppSettings,
                child: const Text('Open app settings'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_permissionsGranted) {
      return const Center(child: CircularProgressIndicator());
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        // WebView2 (Windows) only grants camera/mic to iframes that explicitly
        // allow it; the top-level page itself is granted via onPermissionRequest.
        iframeAllow: 'camera; microphone',
        iframeAllowFullscreen: true,
      ),
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final decision = _decideNavigation(navigationAction.request.url.toString());
        return decision;
      },
      onPermissionRequest: (controller, request) async {
        // Grant only camera/mic, and only for a resource on the allowlisted
        // host — mirrors the Android grant logic in _MobileWebView.
        final host = Uri.tryParse(request.origin.toString())?.host.toLowerCase();
        final allowed = {
          PermissionResourceType.CAMERA,
          PermissionResourceType.MICROPHONE,
        };
        final onlyCameraAndMic =
            request.resources.isNotEmpty && request.resources.every(allowed.contains);
        if (onlyCameraAndMic && _isAllowedHost(host ?? '', _initialHost)) {
          return PermissionResponse(
            resources: request.resources,
            action: PermissionResponseAction.GRANT,
          );
        }
        return PermissionResponse(action: PermissionResponseAction.DENY);
      },
      onReceivedError: (controller, request, error) {
        debugPrint('Desktop WebView load error: ${error.description}');
      },
    );
  }
}

class _MobileWebView extends StatefulWidget {
  final String url;
  const _MobileWebView({required this.url});

  @override
  State<_MobileWebView> createState() => _MobileWebViewState();
}

class _MobileWebViewState extends State<_MobileWebView> {
  WebViewController? _controller;
  String? _error;

  // Host of the URL we were asked to load. Navigation to any other host (other
  // than the known Tavus / Daily.co video hosts) is blocked so the locked-down
  // WebView cannot be steered elsewhere while it holds camera/mic permission.
  String? _initialHost;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Allowlist of hosts the interview WebView may navigate to: the initial
  /// Tavus conversation URL host plus the Tavus / Daily.co video infrastructure
  /// that a live call relies on.
  bool _isAllowedHost(String host) {
    if (host.isEmpty) return false;
    final h = host.toLowerCase();
    if (h == _initialHost) return true;
    const suffixes = <String>['daily.co', 'tavus.io', 'tavusapi.com'];
    for (final s in suffixes) {
      if (h == s || h.endsWith('.$s')) return true;
    }
    return false;
  }

  /// Gate every top-level navigation against the host allowlist. In-page
  /// about:/blob:/data: navigations used internally by the call UI are allowed;
  /// any other scheme (deep links, tel:, etc.) or off-allowlist host is blocked.
  NavigationDecision _decideNavigation(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return NavigationDecision.prevent;
    if (uri.scheme == 'about' || uri.scheme == 'blob' || uri.scheme == 'data') {
      return NavigationDecision.navigate;
    }
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        _isAllowedHost(uri.host)) {
      return NavigationDecision.navigate;
    }
    debugPrint('Blocked WebView navigation to $url');
    return NavigationDecision.prevent;
  }

  Future<void> _init() async {
    _initialHost = Uri.tryParse(widget.url)?.host.toLowerCase();

    // 1) Ask the OS for camera + microphone like a native app would.
    final statuses = await [Permission.camera, Permission.microphone].request();
    final camOk = statuses[Permission.camera]?.isGranted ?? false;
    final micOk = statuses[Permission.microphone]?.isGranted ?? false;

    if (!camOk || !micOk) {
      if (!mounted) return;
      setState(() {
        _error =
            'Camera and microphone access are required for the interview. '
            'Please grant the permissions and try again.';
      });
      return;
    }

    // 2) Build a controller that also grants the WebView page's request.
    final params = _platformParams();
    final controller = WebViewController.fromPlatformCreationParams(params);

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(const Color(0xFF000000));
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) => _decideNavigation(request.url),
        onWebResourceError: (error) {
          debugPrint('Web resource error in Tavus WebView: ${error.description}');
        },
      ),
    );

    // Android-specific wiring: allow autoplay without a tap and grant the
    // page's getUserMedia() camera/mic request.
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
      await platform.setOnPlatformPermissionRequest((request) {
        // Grant ONLY camera + microphone, and only when the request is limited
        // to those. Deny anything else the page might ask for (MIDI, protected
        // media / DRM, etc.). The navigation allowlist above guarantees this
        // request can only originate from an allowlisted Tavus/Daily.co origin.
        const allowed = <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.camera,
          WebViewPermissionResourceType.microphone,
        };
        final onlyCameraAndMic = request.types.isNotEmpty &&
            request.types.every(allowed.contains);
        if (onlyCameraAndMic) {
          request.grant();
        } else {
          request.deny();
        }
      });
    }

    await controller.loadRequest(Uri.parse(widget.url));

    if (!mounted) return;
    setState(() => _controller = controller);
  }

  // Use WebKit params on iOS so inline media + capture work; default elsewhere.
  PlatformWebViewControllerCreationParams _platformParams() {
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      return WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    return const PlatformWebViewControllerCreationParams();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () {
                  setState(() => _error = null);
                  _init();
                },
              ),
              TextButton(
                onPressed: openAppSettings,
                child: const Text('Open app settings'),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return WebViewWidget(controller: _controller!);
  }
}
