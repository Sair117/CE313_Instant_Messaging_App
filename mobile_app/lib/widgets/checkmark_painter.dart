import 'dart:math';
import 'package:flutter/material.dart';

/// Custom painter that draws the morphing checkmark animation.
/// Supports four visual states: spinning arc, single check, double check, and error X.
class CheckmarkPainter extends CustomPainter {
  /// 0.0 = spinning arc, 1.0 = full single checkmark
  final double morphProgress;

  /// 0.0 = hidden, 1.0 = fully visible second checkmark
  final double secondCheckProgress;

  /// Rotation angle for the spinning arc (radians)
  final double spinAngle;

  /// Whether to draw an error X instead
  final bool isError;

  /// Shake offset for error animation
  final double shakeOffset;

  /// Main stroke color
  final Color color;

  /// Optional glow color (for queued state pulse)
  final Color? glowColor;
  final double glowOpacity;

  CheckmarkPainter({
    required this.morphProgress,
    this.secondCheckProgress = 0.0,
    this.spinAngle = 0.0,
    this.isError = false,
    this.shakeOffset = 0.0,
    required this.color,
    this.glowColor,
    this.glowOpacity = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2 + shakeOffset, size.height / 2);
    final radius = size.width * 0.35;
    final strokeWidth = size.width * 0.12;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw glow effect (for queued state)
    if (glowColor != null && glowOpacity > 0) {
      final glowPaint = Paint()
        ..color = glowColor!.withValues(alpha: glowOpacity * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(center, radius * 0.5, glowPaint);
    }

    if (isError) {
      _drawErrorX(canvas, center, radius, paint);
      return;
    }

    if (morphProgress < 1.0) {
      // Phase 1: Spinning arc morphing into checkmark
      _drawSpinningArc(canvas, center, radius, paint);
    }

    if (morphProgress > 0.0) {
      // Phase 2: Single checkmark emerging
      _drawCheckmark(canvas, center, radius, paint, morphProgress, 0);
    }

    if (secondCheckProgress > 0.0) {
      // Phase 3: Second checkmark sliding in
      _drawCheckmark(canvas, center, radius, paint, secondCheckProgress,
          size.width * 0.18);
    }
  }

  void _drawSpinningArc(Canvas canvas, Offset center, double radius, Paint paint) {
    final sweepAngle = pi * (1.4 - morphProgress * 0.8);
    final rect = Rect.fromCircle(center: center, radius: radius);
    paint.color = color.withValues(alpha: 1.0 - morphProgress);
    canvas.drawArc(rect, spinAngle, sweepAngle, false, paint);
    paint.color = color;
  }

  void _drawCheckmark(Canvas canvas, Offset center, double radius, Paint paint,
      double progress, double xOffset) {
    // Checkmark path: from bottom-left, down to bottom-center, up to top-right
    final path = Path();
    final scale = radius * 0.9;

    final p1 = Offset(center.dx - scale * 0.45 + xOffset, center.dy + scale * 0.05);
    final p2 = Offset(center.dx - scale * 0.1 + xOffset, center.dy + scale * 0.4);
    final p3 = Offset(center.dx + scale * 0.45 + xOffset, center.dy - scale * 0.35);

    // Animate the path drawing based on progress
    if (progress <= 0.5) {
      // Draw first segment (p1 → p2)
      final t = progress * 2;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(
        p1.dx + (p2.dx - p1.dx) * t,
        p1.dy + (p2.dy - p1.dy) * t,
      );
    } else {
      // Draw both segments
      final t = (progress - 0.5) * 2;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);
      path.lineTo(
        p2.dx + (p3.dx - p2.dx) * t,
        p2.dy + (p3.dy - p2.dy) * t,
      );
    }

    canvas.drawPath(path, paint);
  }

  void _drawErrorX(Canvas canvas, Offset center, double radius, Paint paint) {
    final s = radius * 0.5;
    canvas.drawLine(
      Offset(center.dx - s, center.dy - s),
      Offset(center.dx + s, center.dy + s),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + s, center.dy - s),
      Offset(center.dx - s, center.dy + s),
      paint,
    );
  }

  @override
  bool shouldRepaint(CheckmarkPainter oldDelegate) {
    return morphProgress != oldDelegate.morphProgress ||
        secondCheckProgress != oldDelegate.secondCheckProgress ||
        spinAngle != oldDelegate.spinAngle ||
        isError != oldDelegate.isError ||
        shakeOffset != oldDelegate.shakeOffset ||
        color != oldDelegate.color ||
        glowOpacity != oldDelegate.glowOpacity;
  }
}
