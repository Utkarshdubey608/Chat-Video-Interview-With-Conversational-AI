// lib/widgets/iframe_view_web.dart
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';

// Cache to keep track of registered view types
final Set<String> _registeredViews = {};

// Cache to keep track of IFrameElement instances by URL
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
    _viewType = 'tavus-iframe-${widget.url.hashCode}';
    _registerViewFactory();
  }

  void _registerViewFactory() {
    if (_registeredViews.contains(_viewType)) return;
    _registeredViews.add(_viewType);

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return _iframeCache.putIfAbsent(widget.url, () {
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
  Widget build(BuildContext context) {
    return HtmlElementView(
      viewType: _viewType,
    );
  }
}

