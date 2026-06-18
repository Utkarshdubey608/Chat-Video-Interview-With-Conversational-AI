// lib/widgets/response_widgets.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/constants/colors.dart';

// ── JSON Preview Pane ──
class JsonPreviewPane extends StatelessWidget {
  final Map<String, dynamic> data;
  final String title;
  final String method;
  final String endpoint;

  const JsonPreviewPane({
    super.key,
    required this.data,
    required this.title,
    required this.method,
    required this.endpoint,
  });

  @override
  Widget build(BuildContext context) {
    final String prettyJson = const JsonEncoder.withIndent('  ').convert(data);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundDarker,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    method,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                      fontFamily: 'Courier',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          
          // Endpoint URL bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0x0AFFFFFF),
            child: Text(
              endpoint,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'Courier',
                color: AppColors.textMuted,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          
          // Code Box
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                prettyJson,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'Courier',
                  color: AppColors.success, // Nice green syntax-like color
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── SVG-Style Overall Fit Score Ring ──
class CircularScoreRing extends StatelessWidget {
  final int score;
  final String verdict;

  const CircularScoreRing({
    super.key,
    required this.score,
    required this.verdict,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _ScoreRingPainter(
                  score: score,
                  backgroundColor: AppColors.border,
                  progressColor: AppColors.primary,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$score',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                const Text(
                  '/100',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  final int score;
  final Color backgroundColor;
  final Color progressColor;

  _ScoreRingPainter({
    required this.score,
    required this.backgroundColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 2, size.height / 2) - 6;

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke;

    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    final angle = 2 * math.pi * (score / 100.0);
    // Draw starting from -90 degrees (top center)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      angle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ── Sentiment Arc Widget ──
class SentimentArc extends StatelessWidget {
  final int score;
  final String label;

  const SentimentArc({
    super.key,
    required this.score,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 100,
              height: 60,
              child: CustomPaint(
                painter: _ArcPainter(
                  score: score,
                  bg: AppColors.border,
                  fg: AppColors.humeTeal,
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              child: Column(
                children: [
                  Text(
                    '$score%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.humeTeal,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.humeMuted,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ArcPainter extends CustomPainter {
  final int score;
  final Color bg;
  final Color fg;

  _ArcPainter({required this.score, required this.bg, required this.fg});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height * 2 - 10);
    
    final bgPaint = Paint()
      ..color = bg
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    final fgPaint = Paint()
      ..color = fg
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Background semi-circle arc
    canvas.drawArc(rect, math.pi, math.pi, false, bgPaint);

    // Score filled arc
    final sweepAngle = math.pi * (score / 100.0);
    canvas.drawArc(rect, math.pi, sweepAngle, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ── Emotion Radar Chart ──
class EmotionRadarChart extends StatelessWidget {
  final Map<String, double> categoryScores;

  const EmotionRadarChart({
    super.key,
    required this.categoryScores,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double size = math.min(constraints.maxWidth, 260);
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _RadarChartPainter(categoryScores),
            ),
          ),
        );
      },
    );
  }
}

class _RadarChartPainter extends CustomPainter {
  final Map<String, double> scores;
  static const List<String> categories = [
    'positive_high',
    'positive_calm',
    'cognitive',
    'social',
    'negative',
    'disengagement',
  ];

  static const List<String> categoryLabels = [
    'High Positive',
    'Calm Positive',
    'Cognitive',
    'Social',
    'Negative',
    'Disengaged',
  ];

  _RadarChartPainter(this.scores);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2.0 - 35;

    final axisPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.0;

    final gridPaint = Paint()
      ..color = const Color(0x1AFFFFFF)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // 1. Draw web grid rings (at 25%, 50%, 75%, 100% radius)
    final int rings = 4;
    for (int rIndex = 1; rIndex <= rings; rIndex++) {
      final ringRadius = maxRadius * (rIndex / rings);
      final Path gridPath = Path();
      for (int i = 0; i < categories.length; i++) {
        final angle = (i * 2 * math.pi / categories.length) - (math.pi / 2);
        final x = center.dx + ringRadius * math.cos(angle);
        final y = center.dy + ringRadius * math.sin(angle);
        if (i == 0) {
          gridPath.moveTo(x, y);
        } else {
          gridPath.lineTo(x, y);
        }
      }
      gridPath.close();
      canvas.drawPath(gridPath, gridPaint);
    }

    // 2. Draw axis lines & labels
    const textStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 8,
      fontWeight: FontWeight.bold,
    );

    for (int i = 0; i < categories.length; i++) {
      final angle = (i * 2 * math.pi / categories.length) - (math.pi / 2);
      final outerX = center.dx + maxRadius * math.cos(angle);
      final outerY = center.dy + maxRadius * math.sin(angle);

      // Line
      canvas.drawLine(center, Offset(outerX, outerY), axisPaint);

      // Draw label
      final labelX = center.dx + (maxRadius + 18) * math.cos(angle);
      final labelY = center.dy + (maxRadius + 10) * math.sin(angle);
      final span = TextSpan(text: categoryLabels[i], style: textStyle);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(labelX - tp.width / 2, labelY - tp.height / 2));
    }

    // 3. Draw score polygon
    final polyPath = Path();
    final valuePaint = Paint()
      ..color = AppColors.humeTeal.withOpacity(0.25)
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = AppColors.humeTeal
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    bool hasData = false;
    for (int i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final val = (scores[cat] ?? 0.0).clamp(0.0, 1.0);
      if (val > 0) hasData = true;
      final angle = (i * 2 * math.pi / categories.length) - (math.pi / 2);
      final x = center.dx + maxRadius * val * math.cos(angle);
      final y = center.dy + maxRadius * val * math.sin(angle);
      if (i == 0) {
        polyPath.moveTo(x, y);
      } else {
        polyPath.lineTo(x, y);
      }
    }
    
    if (hasData) {
      polyPath.close();
      canvas.drawPath(polyPath, valuePaint);
      canvas.drawPath(polyPath, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
