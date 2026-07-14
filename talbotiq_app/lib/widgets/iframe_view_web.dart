// lib/widgets/iframe_view_web.dart
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';

// Monotonic counter used to mint a unique view type per iframe instance.
// Keying by url.hashCode risked collisions (two different URLs sharing a hash
// would reuse the wrong registered factory / cached element).
int _viewTypeCounter = 0;

// Registered view types (guards against double-registration).
final Set<String> _registeredViews = {};

// Cache of IFrameElement instances, keyed by their unique view type.
final Map<String, html.IFrameElement> _iframeCache = {};

Widget buildIframe(String url) {
  return WebIframeView(url: url, key: ValueKey(url));
}

class WebIframeView extends StatefulWidget {
  final String url;
  const WebIframeView({required this.url, super.key});

  @override
  State<WebIframeView> createState() => _WebIframeViewState();
}

class _WebIframeViewState extends State<WebIframeView> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'tavus-iframe-${_viewTypeCounter++}';
    _registerViewFactory();
  }

  void _registerViewFactory() {
    if (_registeredViews.contains(_viewType)) return;
    _registeredViews.add(_viewType);

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return _iframeCache.putIfAbsent(_viewType, () {
        return html.IFrameElement()
          ..src = widget.url
          ..style.border = 'none'
          ..width = '100%'
          ..height = '100%'
          ..allow = 'camera; microphone; autoplay; display-capture; fullscreen';
      });
    });
  }

  @override
  void dispose() {
    // Evict this instance's cached iframe + registration so they don't leak for
    // the lifetime of the app. The view type is unique per instance, so it is
    // never re-registered after removal.
    _iframeCache.remove(_viewType);
    _registeredViews.remove(_viewType);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      viewType: _viewType,
    );
  }
}

