// lib/core/services/facefit_service.dart
//
// FaceFit — on-device pre-call facial attention/engagement capture.
//
// This service owns the FRONT camera for a few seconds BEFORE the Tavus video
// WebView takes over. It runs the google_mlkit_face_detection pipeline over the
// live camera image stream, computes attention/engagement/integrity metrics,
// and returns a fully-populated [FacialSessionSummary].
//
// Design contract:
//  - The camera plugin is requested with the platform-appropriate image format
//    (nv21 on Android, bgra8888 on iOS) so CameraImage -> ML Kit InputImage is a
//    single-plane, zero-copy hand-off (see [_inputImageFromCameraImage]).
//  - Exactly ONE frame is processed at a time. While a frame is in flight new
//    frames are dropped (see [_processingFrame]) — ML Kit cannot be re-entered.
//  - EVERYTHING is disposed: the image stream is STOPPED before the controller
//    is disposed, the FaceDetector is closed, and the live-state StreamController
//    is closed. The camera is never left open. See [dispose].
//
// This file cannot be runtime-tested here (no physical camera). QA markers below
// (search "QA:") flag the spots that need on-device validation.

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../models/app_models.dart';

/// Lightweight per-frame snapshot pushed to the preview UI via [FacefitService.liveState].
///
/// Intentionally tiny so it can be emitted every processed frame without churn.
class FacefitLiveState {
  /// A face is currently detected in the frame.
  final bool faceDetected;

  /// The (largest) face is roughly centered in the frame.
  final bool centered;

  /// The candidate is looking away (|headEulerAngleY| > [kLookingAwayYawDeg]).
  final bool lookingAway;

  /// Smiling probability of the tracked face, 0.0–1.0 (0 when no face).
  final double smile;

  const FacefitLiveState({
    required this.faceDetected,
    required this.centered,
    required this.lookingAway,
    required this.smile,
  });

  /// Neutral "nothing seen yet" state.
  const FacefitLiveState.idle()
      : faceDetected = false,
        centered = false,
        lookingAway = false,
        smile = 0.0;

  /// Guidance string for the preview overlay derived from the live state.
  String get guidance {
    if (!faceDetected) return 'Center your face in the oval';
    if (lookingAway) return 'Look at the camera';
    if (!centered) return 'Move so your face fills the oval';
    return 'Great — hold still';
  }
}

/// Owns the front camera + ML Kit face detector for a short pre-call capture.
///
/// Lifecycle: [initialize] -> (preview via [liveState]) -> [captureFor] -> [dispose].
/// [dispose] is idempotent and MUST be called by the owner (the page's dispose()).
class FacefitService {
  // ── Tunables ──────────────────────────────────────────────────────────────
  /// Yaw magnitude (degrees) beyond which the candidate is "looking away".
  static const double kLookingAwayYawDeg = 20.0;

  /// Eye-open probability at/above which an eye counts as "open".
  static const double kEyeOpenThreshold = 0.4;

  /// A face is "centered" when its bounding box center is within this fraction
  /// of the frame's half-extent from the frame center, on both axes.
  static const double kCenterToleranceFraction = 0.28;

  /// usableFramePercent thresholds for the dataQuality bucket.
  static const double kQualityHighPct = 75.0;
  static const double kQualityMediumPct = 45.0;
  static const double kQualityLowPct = 15.0;

  // ── State ───────────────────────────────────────────────────────────────────
  CameraController? _controller;
  FaceDetector? _detector;

  final StreamController<FacefitLiveState> _liveController =
      StreamController<FacefitLiveState>.broadcast();

  /// True while a single frame is being processed by ML Kit; new frames are
  /// dropped until it flips back. Prevents concurrent [FaceDetector.processImage].
  bool _processingFrame = false;

  bool _streaming = false;
  bool _disposed = false;

  /// Set only while [captureFor] is running so the frame callback aggregates.
  _CaptureAccumulator? _accumulator;

  // Android orientation compensation table (device orientation -> degrees).
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Broadcast stream of live preview state; safe to listen before/after capture.
  Stream<FacefitLiveState> get liveState => _liveController.stream;

  /// The initialized controller, exposed so the page can build a [CameraPreview].
  /// Null until [initialize] succeeds.
  CameraController? get controller => _controller;

  /// True once the camera is initialized and the frame stream is running.
  bool get isReady =>
      _controller?.value.isInitialized == true && _streaming && !_disposed;

  // ── Setup ─────────────────────────────────────────────────────────────────

  /// Opens the FRONT camera, starts the image stream, and constructs the
  /// classifying + tracking [FaceDetector]. Throws on failure — the caller
  /// (facefit_page) catches and shows the skip/fallback path.
  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('FacefitService used after dispose()');
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw CameraException('no_cameras', 'No cameras available on device.');
    }

    final CameraDescription front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    // Low resolution keeps per-frame conversion + detection cheap; face
    // detection does not need high resolution.
    final controller = CameraController(
      front,
      ResolutionPreset.low,
      enableAudio: false,
      // nv21 (Android) / bgra8888 (iOS) give a single-plane buffer that ML Kit
      // ingests directly. QA: confirm the plugin honors nv21 on the target
      // Android build; if it falls back to yuv420 the frame is skipped safely.
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    _controller = controller;

    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // smiling + eye-open probabilities
        enableTracking: true, // stable trackingId across frames
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    await controller.initialize();
    if (_disposed) {
      // Disposed mid-initialize — tear the freshly-built resources back down.
      await _teardown();
      throw StateError('FacefitService disposed during initialize()');
    }

    await controller.startImageStream(_onFrame);
    _streaming = true;
  }

  // ── Frame pipeline ──────────────────────────────────────────────────────────

  Future<void> _onFrame(CameraImage image) async {
    // Guard: skip if disposed, torn down, or a frame is already in flight.
    if (_disposed || _detector == null || _processingFrame) return;
    _processingFrame = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        // Unsupported format/rotation this frame — emit idle so preview
        // doesn't freeze, but do NOT count it as a processed frame.
        _emit(const FacefitLiveState.idle());
        return;
      }

      final faces = await _detector!.processImage(inputImage);
      if (_disposed) return;

      final metrics = _analyzeFaces(faces, image.width, image.height);

      // Feed the running capture (if any) and the live preview.
      _accumulator?.add(metrics);
      _emit(FacefitLiveState(
        faceDetected: metrics.faceDetected,
        centered: metrics.centered,
        lookingAway: metrics.lookingAway,
        smile: metrics.smile,
      ));
    } catch (e) {
      // ML Kit / conversion hiccup on a single frame must not kill the stream.
      // QA: watch for repeated conversion failures in logs on real devices.
      debugPrint('FacefitService frame error: $e');
    } finally {
      _processingFrame = false;
    }
  }

  /// Reduces a list of detected faces (largest wins) into per-frame [_FrameMetrics].
  _FrameMetrics _analyzeFaces(List<Face> faces, int frameW, int frameH) {
    if (faces.isEmpty) {
      return const _FrameMetrics.absent();
    }

    // Pick the largest face by bounding-box area (the primary candidate).
    Face primary = faces.first;
    double bestArea = primary.boundingBox.width * primary.boundingBox.height;
    for (final f in faces.skip(1)) {
      final area = f.boundingBox.width * f.boundingBox.height;
      if (area > bestArea) {
        bestArea = area;
        primary = f;
      }
    }

    final yaw = primary.headEulerAngleY ?? 0.0; // left/right
    final lookingAway = yaw.abs() > kLookingAwayYawDeg;

    final leftEye = primary.leftEyeOpenProbability ?? 1.0;
    final rightEye = primary.rightEyeOpenProbability ?? 1.0;
    final eyesOpen =
        leftEye >= kEyeOpenThreshold && rightEye >= kEyeOpenThreshold;

    final smile = primary.smilingProbability ?? 0.0;

    // Centeredness from bounding-box center vs frame center.
    final cx = primary.boundingBox.center.dx;
    final cy = primary.boundingBox.center.dy;
    final dxFrac = frameW > 0 ? (cx - frameW / 2).abs() / (frameW / 2) : 1.0;
    final dyFrac = frameH > 0 ? (cy - frameH / 2).abs() / (frameH / 2) : 1.0;
    final centered =
        dxFrac <= kCenterToleranceFraction && dyFrac <= kCenterToleranceFraction;

    // Multiple faces in frame is an integrity signal.
    final multiFace = faces.length > 1;

    return _FrameMetrics(
      faceDetected: true,
      lookingAway: lookingAway,
      eyesOpen: eyesOpen,
      centered: centered,
      smile: smile.clamp(0.0, 1.0),
      multiFace: multiFace,
    );
  }

  /// Converts a [CameraImage] into an ML Kit [InputImage].
  ///
  /// Android: expects a single-plane nv21 buffer; rotation is derived from the
  /// sensor orientation and the current device orientation, mirrored for the
  /// front lens. iOS: expects a single-plane bgra8888 buffer; rotation maps
  /// straight from the sensor orientation (device rotation is not used on iOS).
  ///
  /// Returns null when the frame's format/rotation is unsupported (frame is then
  /// safely skipped by the caller).
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;
    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else {
      // Android: compensate for the current device orientation.
      final deviceRotation = _orientations[controller.value.deviceOrientation];
      if (deviceRotation == null) return null;
      int compensated;
      if (camera.lensDirection == CameraLensDirection.front) {
        // Front camera is mirrored — add.
        compensated = (sensorOrientation + deviceRotation) % 360;
      } else {
        compensated = (sensorOrientation - deviceRotation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(compensated);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // Enforce the single-plane contract per platform. If the plugin handed us a
    // multi-plane yuv420 buffer (e.g. nv21 unsupported), skip this frame rather
    // than misinterpret the bytes.
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
    if (image.planes.length != 1) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void _emit(FacefitLiveState state) {
    if (_disposed || _liveController.isClosed) return;
    _liveController.add(state);
  }

  // ── Capture ─────────────────────────────────────────────────────────────────

  /// Runs the capture for [duration] and returns a populated [FacialSessionSummary].
  ///
  /// The frame stream keeps running throughout; this just switches on an
  /// accumulator that the frame callback feeds. Safe to call once per service
  /// instance. If the camera is not ready, returns an 'insufficient' summary.
  Future<FacialSessionSummary> captureFor(Duration duration) async {
    if (!isReady) {
      return insufficientSummary(
        note: 'Camera was not ready when the check started.',
      );
    }

    final acc = _CaptureAccumulator();
    _accumulator = acc;
    try {
      await Future<void>.delayed(duration);
    } finally {
      _accumulator = null;
    }

    return acc.buildSummary(
      lookingAwayYawDeg: kLookingAwayYawDeg,
      qualityHighPct: kQualityHighPct,
      qualityMediumPct: kQualityMediumPct,
      qualityLowPct: kQualityLowPct,
    );
  }

  /// Builds a zero-frame 'insufficient' summary for the skip/fallback path.
  ///
  /// Static so facefit_page can produce it without a live service instance.
  static FacialSessionSummary insufficientSummary({String? note}) {
    return FacialSessionSummary(
      totalFrames: 0,
      usableFrames: 0,
      usableFramePercent: 0.0,
      perQuestion: const <QuestionFacialSummary>[],
      sessionDominantEmotions: const <Map<String, dynamic>>[],
      sessionAvgAttention: 0.0,
      sessionAvgSmile: 0.0,
      overallLookingAwayPercent: 0.0,
      dataQuality: 'insufficient',
      dataQualityNote:
          note ?? 'No facial signals were captured for this session.',
      integrityFlags: const <String>[],
      engagementFlags: const <String>[],
      concernFlags: const <String>[],
    );
  }

  // ── Teardown ─────────────────────────────────────────────────────────────────

  /// Fully releases the camera, detector, and stream. Idempotent.
  ///
  /// Order matters: stop the image stream BEFORE disposing the controller so the
  /// platform callback can't fire against a disposed controller.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _accumulator = null;
    await _teardown();
    if (!_liveController.isClosed) {
      await _liveController.close();
    }
  }

  Future<void> _teardown() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (_streaming && controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {/* already stopped/detached */}
      _streaming = false;
      try {
        await controller.dispose();
      } catch (_) {/* already disposed */}
    }

    final detector = _detector;
    _detector = null;
    if (detector != null) {
      try {
        await detector.close();
      } catch (_) {/* already closed */}
    }
  }
}

// ── Internal aggregation types ────────────────────────────────────────────────

/// Per-frame reduced metrics (immutable snapshot).
class _FrameMetrics {
  final bool faceDetected;
  final bool lookingAway;
  final bool eyesOpen;
  final bool centered;
  final double smile;
  final bool multiFace;

  const _FrameMetrics({
    required this.faceDetected,
    required this.lookingAway,
    required this.eyesOpen,
    required this.centered,
    required this.smile,
    required this.multiFace,
  });

  const _FrameMetrics.absent()
      : faceDetected = false,
        lookingAway = false,
        eyesOpen = false,
        centered = false,
        smile = 0.0,
        multiFace = false;

  /// A frame is "usable" when a face is present, eyes are open, and the
  /// candidate is not looking away — i.e. an attentive, analyzable frame.
  bool get usable => faceDetected && eyesOpen && !lookingAway;
}

/// Accumulates [_FrameMetrics] over a capture window and produces the summary.
class _CaptureAccumulator {
  int total = 0;
  int facePresent = 0;
  int usable = 0;
  int lookingAway = 0;
  int eyesClosed = 0;
  int multiFace = 0;
  double smileSum = 0.0; // over face-present frames

  void add(_FrameMetrics m) {
    total++;
    if (m.faceDetected) {
      facePresent++;
      smileSum += m.smile;
      if (m.lookingAway) lookingAway++;
      if (!m.eyesOpen) eyesClosed++;
      if (m.multiFace) multiFace++;
    }
    if (m.usable) usable++;
  }

  FacialSessionSummary buildSummary({
    required double lookingAwayYawDeg,
    required double qualityHighPct,
    required double qualityMediumPct,
    required double qualityLowPct,
  }) {
    if (total == 0) {
      return FacefitService.insufficientSummary(
        note: 'No camera frames were received during the check.',
      );
    }

    final usablePct = usable / total * 100.0;
    // Attention = % of ALL frames that were face-present, eyes-open, not-away.
    final attention = usable / total * 100.0;
    // Smile = average smiling probability over face-present frames, as %.
    final avgSmile = facePresent > 0 ? (smileSum / facePresent) * 100.0 : 0.0;
    final awayPct = total > 0 ? lookingAway / total * 100.0 : 0.0;
    final facePresentPct = facePresent / total * 100.0;

    final quality = _bucket(
      usablePct,
      qualityHighPct,
      qualityMediumPct,
      qualityLowPct,
    );

    // ── Flags ─────────────────────────────────────────────────────────────
    final integrity = <String>[];
    final engagement = <String>[];
    final concern = <String>[];

    if (multiFace > 0) {
      final mfPct = multiFace / total * 100.0;
      integrity.add(
          'Multiple faces detected in ${mfPct.round()}% of frames.');
    }
    if (facePresentPct < 60.0) {
      integrity.add(
          'Face was only present in ${facePresentPct.round()}% of frames.');
    }

    if (attention >= 70.0) {
      engagement.add('Strong attention — looked at camera consistently.');
    } else if (attention >= 40.0) {
      engagement.add('Moderate attention during the check.');
    }
    if (avgSmile >= 40.0) {
      engagement.add('Positive affect (frequent smiling).');
    }

    if (awayPct >= 30.0) {
      concern.add('Looked away ${awayPct.round()}% of the time.');
    }
    if (eyesClosed > 0) {
      final ecPct = eyesClosed / total * 100.0;
      if (ecPct >= 25.0) {
        concern.add('Eyes closed/blinking in ${ecPct.round()}% of frames.');
      }
    }
    if (quality == 'low' || quality == 'insufficient') {
      concern.add('Low-quality capture — interpret metrics with caution.');
    }

    return FacialSessionSummary(
      totalFrames: total,
      usableFrames: usable,
      usableFramePercent: _round1(usablePct),
      perQuestion: const <QuestionFacialSummary>[], // pre-call: no per-question split
      sessionDominantEmotions: _dominantEmotions(avgSmile),
      sessionAvgAttention: _round1(attention),
      sessionAvgSmile: _round1(avgSmile),
      overallLookingAwayPercent: _round1(awayPct),
      dataQuality: quality,
      dataQualityNote: _qualityNote(quality, usablePct, facePresentPct),
      integrityFlags: integrity,
      engagementFlags: engagement,
      concernFlags: concern,
    );
  }

  /// ML Kit does not classify discrete emotions; we surface a coarse smile-derived
  /// affect so [sessionDominantEmotions] is non-empty and consistent with the
  /// AWS-Rekognition-shaped model (`List<Map<String,dynamic>>` of name/score).
  List<Map<String, dynamic>> _dominantEmotions(double avgSmilePct) {
    final smile01 = (avgSmilePct / 100.0).clamp(0.0, 1.0);
    return [
      // Key is `avgConfidence` to match the scorecard prompt (gemini_service).
      {'type': avgSmilePct >= 35.0 ? 'HAPPY' : 'CALM', 'avgConfidence': _round1(avgSmilePct)},
      {'type': 'NEUTRAL', 'avgConfidence': _round1((1.0 - smile01) * 100.0)},
    ];
  }

  String _bucket(double pct, double high, double medium, double low) {
    if (pct >= high) return 'high';
    if (pct >= medium) return 'medium';
    if (pct >= low) return 'low';
    return 'insufficient';
  }

  String _qualityNote(String quality, double usablePct, double facePct) {
    switch (quality) {
      case 'high':
        return 'High-quality capture — ${usablePct.round()}% usable frames.';
      case 'medium':
        return 'Usable capture — ${usablePct.round()}% usable frames; some frames were unclear.';
      case 'low':
        return 'Limited capture — only ${usablePct.round()}% usable frames (face present ${facePct.round()}%).';
      default:
        return 'Insufficient data — capture too short or face rarely visible.';
    }
  }

  double _round1(double v) => (v * 10).roundToDouble() / 10.0;
}
