// lib/widgets/iframe_view_stub.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Platform-specific imports for camera/mic permission grants inside the WebView.
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

Widget buildIframe(String url) {
  return _MobileWebView(url: url);
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
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
        request.grant();
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
