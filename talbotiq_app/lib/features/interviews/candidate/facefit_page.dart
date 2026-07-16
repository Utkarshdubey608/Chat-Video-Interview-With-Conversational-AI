// lib/features/interviews/candidate/facefit_page.dart
//
// FaceFit pre-call capture screen.
//
// Flow (mirrors system_check_page.dart's permission-gate + AppLifecycle re-check):
//   1. Gate on camera permission (permission_handler). Retry / Open Settings.
//      Re-check on AppLifecycleState.resumed (candidate returns from OS Settings).
//   2. Initialize the FRONT camera + ML Kit pipeline (FacefitService).
//   3. Show CameraPreview with a framing oval + live guidance from the stream.
//   4. "Start check" runs a 6s capture with a visible countdown, then calls
//      widget.onCaptured(summary) and pops.
//   5. Fallback: permission denied OR camera init fails -> clear message + "Skip",
//      which calls onCaptured with an 'insufficient' summary (totalFrames: 0).
//
// The app owns the camera ONLY here; everything is disposed in dispose() before
// the Tavus video WebView takes the camera.

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/facefit_service.dart';
import '../../../models/app_models.dart';
import '../../../widgets/custom_buttons.dart';

/// Duration of the active capture window.
const Duration kFacefitCaptureDuration = Duration(seconds: 6);

class FacefitPage extends StatefulWidget {
  /// Called exactly once with the capture result (real or 'insufficient'
  /// fallback) right before the page pops.
  final ValueChanged<FacialSessionSummary> onCaptured;
  final String title;

  const FacefitPage({
    super.key,
    required this.onCaptured,
    this.title = 'Attention check',
  });

  @override
  State<FacefitPage> createState() => _FacefitPageState();
}

enum _Phase { checkingPermission, initializing, ready, capturing, failed }

class _FacefitPageState extends State<FacefitPage> with WidgetsBindingObserver {
  final FacefitService _service = FacefitService();

  _Phase _phase = _Phase.checkingPermission;
  PermissionStatus? _cam;
  String _failureMessage = '';
  bool _busy = false;

  FacefitLiveState _live = const FacefitLiveState.idle();
  StreamSubscription<FacefitLiveState>? _liveSub;

  int _countdown = kFacefitCaptureDuration.inSeconds;
  Timer? _countdownTimer;

  /// Guards against onCaptured firing more than once (skip + finish race).
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _liveSub?.cancel();
    // Fire-and-forget async teardown; the service disposal is idempotent and
    // stops the image stream before disposing the controller.
    _service.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Candidate may have toggled the permission in OS Settings and come back.
    if (state == AppLifecycleState.resumed &&
        _phase == _Phase.checkingPermission) {
      _bootstrap();
    }
  }

  // ── Bootstrap: permission gate -> camera init ────────────────────────────

  Future<void> _bootstrap() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _phase = _Phase.checkingPermission;
    });

    PermissionStatus status = await Permission.camera.status;
    if (!status.isGranted && !status.isPermanentlyDenied && !status.isRestricted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;

    _cam = status;
    if (!status.isGranted) {
      setState(() {
        _busy = false;
        _phase = _Phase.checkingPermission;
      });
      return;
    }

    // Permission granted -> initialize the camera + detector.
    setState(() => _phase = _Phase.initializing);
    try {
      await _service.initialize();
      if (!mounted) {
        // Unmounted during async init — release the camera we just opened.
        await _service.dispose();
        return;
      }
      _liveSub = _service.liveState.listen((s) {
        if (mounted) setState(() => _live = s);
      });
      setState(() {
        _busy = false;
        _phase = _Phase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _Phase.failed;
        _failureMessage =
            'We could not start your camera for the attention check.';
      });
    }
  }

  // ── Capture ───────────────────────────────────────────────────────────────

  Future<void> _startCapture() async {
    if (_phase != _Phase.ready) return;
    setState(() {
      _phase = _Phase.capturing;
      _countdown = kFacefitCaptureDuration.inSeconds;
    });

    _countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdown = (_countdown - 1).clamp(0, kFacefitCaptureDuration.inSeconds);
      });
      if (_countdown <= 0) timer.cancel();
    });

    final summary = await _service.captureFor(kFacefitCaptureDuration);
    _countdownTimer?.cancel();
    if (!mounted) return;
    _finish(summary);
  }

  /// Skip / fallback: hand back an 'insufficient' summary (totalFrames: 0).
  void _skip() {
    _finish(FacefitService.insufficientSummary(
      note: _cam?.isGranted == true
          ? 'Candidate skipped the attention check.'
          : 'Camera permission was not granted; attention check skipped.',
    ));
  }

  void _finish(FacialSessionSummary summary) {
    if (_completed) return;
    _completed = true;
    _countdownTimer?.cancel();
    widget.onCaptured(summary);
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  bool get _permanentlyBlocked =>
      (_cam?.isPermanentlyDenied ?? false) || (_cam?.isRestricted ?? false);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // Escape hatch is always available — this check is optional.
          TextButton(
            onPressed: _skip,
            child: Text(
              'Skip',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildBody(theme),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_phase) {
      case _Phase.checkingPermission:
        return _cam == null || _cam!.isGranted
            ? _centeredLoader(theme, 'Checking camera permission…')
            : _permissionGate(theme);
      case _Phase.initializing:
        return _centeredLoader(theme, 'Starting camera…');
      case _Phase.failed:
        return _fallback(theme, _failureMessage);
      case _Phase.ready:
      case _Phase.capturing:
        return _cameraView(theme);
    }
  }

  Widget _centeredLoader(ThemeData theme, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  // Permission not yet granted (retry / open settings).
  Widget _permissionGate(ThemeData theme) {
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Icon(Icons.videocam_outlined, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'We use your camera for a quick, on-device attention check before your '
            'interview. Nothing is recorded or uploaded.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (_permanentlyBlocked) ...[
            CustomButton(
              text: 'Open Settings',
              variant: ButtonVariant.outline,
              onPressed: openAppSettings,
            ),
            const SizedBox(height: 8),
            Text(
              'Camera access was blocked. Enable Camera for this app in Settings, '
              'then return here.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ] else
            CustomButton(
              text: 'Allow camera',
              variant: ButtonVariant.outline,
              isLoading: _busy,
              onPressed: _busy ? () {} : _bootstrap,
            ),
          const SizedBox(height: 12),
          CustomButton(
            text: 'Skip this check',
            variant: ButtonVariant.ghost,
            onPressed: _skip,
          ),
        ],
      ),
    );
  }

  // Camera failed to initialize — clear message + skip.
  Widget _fallback(ThemeData theme, String message) {
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Icon(Icons.videocam_off_outlined, size: 40, color: cs.error),
          const SizedBox(height: 16),
          Text(
            message.isEmpty ? 'The attention check is unavailable.' : message,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'You can continue to your interview without it.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          CustomButton(
            text: 'Continue',
            onPressed: _skip,
          ),
        ],
      ),
    );
  }

  // Live camera + framing oval + guidance + start/countdown.
  Widget _cameraView(ThemeData theme) {
    final cs = theme.colorScheme;
    final controller = _service.controller;
    final capturing = _phase == _Phase.capturing;

    final bool good =
        _live.faceDetected && _live.centered && !_live.lookingAway;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive square-ish preview capped for large screens.
        final previewSize = constraints.maxWidth.clamp(0.0, 420.0);
        return SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text(
                capturing
                    ? 'Hold still — analyzing…'
                    : 'Position your face inside the oval and look at the camera.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Center(
                child: SizedBox(
                  width: previewSize,
                  height: previewSize,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (controller != null &&
                            controller.value.isInitialized)
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: controller.value.previewSize?.height ??
                                  previewSize,
                              height: controller.value.previewSize?.width ??
                                  previewSize,
                              child: CameraPreview(controller),
                            ),
                          )
                        else
                          Container(color: cs.surfaceContainerHighest),
                        // Framing oval overlay.
                        CustomPaint(
                          painter: _OvalGuidePainter(
                            color: good ? Colors.green : cs.primary,
                          ),
                        ),
                        // Countdown badge during capture.
                        if (capturing)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                '${_countdown}s',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Live guidance line.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    good ? Icons.check_circle : Icons.center_focus_weak,
                    size: 18,
                    color: good ? Colors.green : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _live.guidance,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: good ? Colors.green : cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: previewSize,
                child: CustomButton(
                  text: capturing
                      ? 'Analyzing… ${_countdown}s'
                      : 'Start check',
                  isLoading: capturing,
                  onPressed: capturing ? () {} : _startCapture,
                ),
              ),
              const SizedBox(height: 8),
              if (!capturing)
                CustomButton(
                  text: 'Skip',
                  variant: ButtonVariant.ghost,
                  onPressed: _skip,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Draws the dashed framing oval guide over the preview.
class _OvalGuidePainter extends CustomPainter {
  final Color color;
  const _OvalGuidePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Scrim to focus attention on the oval.
    final scrim = Paint()..color = Colors.black.withOpacity(0.28);
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.62,
      height: size.height * 0.78,
    );
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addOval(ovalRect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, hole),
      scrim,
    );

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawOval(ovalRect, stroke);
  }

  @override
  bool shouldRepaint(covariant _OvalGuidePainter old) => old.color != color;
}
