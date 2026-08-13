// lib/core/utils/desktop_platform.dart
//
// Single source of truth for "is this build running as a Windows/macOS/Linux
// desktop app". Used to gate desktop-only behavior (window sizing, the
// desktop WebView, and — importantly — restricting the desktop client to
// recruiters only). kIsWeb must be checked first: dart:io's Platform getters
// throw on web.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
