// lib/widgets/iframe_view_web.dart
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';

Widget buildIframe(String url) {
  final String viewType = 'tavus-iframe-${url.hashCode}';
  
  // Register the view factory with dart:ui_web
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = html.IFrameElement()
      ..src = url
      ..style.border = 'none'
      ..width = '100%'
      ..height = '100%'
      ..allow = 'camera; microphone; autoplay; display-capture; fullscreen';
    return iframe;
  });

  return HtmlElementView(viewType: viewType);
}
