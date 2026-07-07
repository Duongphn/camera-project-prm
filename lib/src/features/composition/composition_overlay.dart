import 'package:flutter/material.dart';

import 'composition_advisor.dart';

/// Overlay bố cục. Ba chế độ vẽ:
/// - [advice] != null: dẫn ngắm (dấu + giữa + nốt tròn đích) — có chủ thể.
/// - [advice] == null & [scenicPoint] != null: nốt tròn tĩnh tại điểm cảnh
///   đẹp nhất (0..1 viewfinder) — không chủ thể, còn mạng.
/// - [advice] == null & [scenicPoint] == null & [showThirdsHint]: mờ 4 giao
///   điểm 1/3 — không chủ thể, offline.
class CompositionOverlay extends StatelessWidget {
  const CompositionOverlay({
    super.key,
    this.advice,
    this.scenicPoint,
    this.showThirdsHint = false,
  });

  final CompositionAdvice? advice;
  final Offset? scenicPoint;
  final bool showThirdsHint;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CompositionPainter(advice, scenicPoint, showThirdsHint),
        size: Size.infinite,
      ),
    );
  }
}

class _CompositionPainter extends CustomPainter {
  _CompositionPainter(this.advice, this.scenicPoint, this.showThirdsHint);

  final CompositionAdvice? advice;
  final Offset? scenicPoint;
  final bool showThirdsHint;

  @override
  void paint(Canvas canvas, Size size) {
    final a = advice;
    if (a != null) {
      _paintGuiding(canvas, size, a);
      return;
    }
    final sp = scenicPoint;
    if (sp != null) {
      _paintDot(canvas, Offset(sp.dx * size.width, sp.dy * size.height));
      return;
    }
    if (showThirdsHint) {
      final paint = Paint()..color = Colors.white.withValues(alpha: 0.35);
      for (final p in thirdsPoints) {
        canvas.drawCircle(
            Offset(p.dx * size.width, p.dy * size.height), 5, paint);
      }
    }
  }

  /// Nốt tròn nổi trên mọi nền: lõi đặc + viền tối + vòng ngoài mờ.
  void _paintDot(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 9, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(c, 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  void _paintGuiding(Canvas canvas, Size size, CompositionAdvice a) {
    final aligned = a.isAligned;
    final color = aligned
        ? Colors.greenAccent
        : (a.isLocked ? Colors.amber : Colors.white);

    // Dấu + cố định giữa màn hình.
    final center = Offset(size.width / 2, size.height / 2);
    final crossPaint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = aligned ? Colors.greenAccent : Colors.white.withValues(alpha: 0.9);
    const arm = 11.0;
    canvas.drawLine(
        center - const Offset(arm, 0), center + const Offset(arm, 0), crossPaint);
    canvas.drawLine(
        center - const Offset(0, arm), center + const Offset(0, arm), crossPaint);

    final aim = Offset(
      (a.aimPoint.dx.clamp(0.04, 0.96)) * size.width,
      (a.aimPoint.dy.clamp(0.04, 0.96)) * size.height,
    );

    if (aligned) {
      canvas.drawCircle(
        center,
        18,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color,
      );
      return;
    }

    canvas.drawCircle(aim, 9, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(aim, 7, Paint()..color = color);
    canvas.drawCircle(
      aim,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _CompositionPainter oldDelegate) =>
      oldDelegate.advice != advice ||
      oldDelegate.scenicPoint != scenicPoint ||
      oldDelegate.showThirdsHint != showThirdsHint;
}
