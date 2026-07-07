import 'package:flutter/material.dart';

import 'composition_advisor.dart';

/// Overlay bố cục. Ba chế độ vẽ:
/// - [advice] != null: dẫn ngắm (dấu + giữa + vòng tròn cầu vồng đích) — có
///   chủ thể. Di máy cho dấu + trùng vòng tròn là chủ thể vào điểm đẹp.
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
        painter: CompositionPainter(advice, scenicPoint, showThirdsHint),
        size: Size.infinite,
      ),
    );
  }
}

/// Public để test có thể vẽ trực tiếp lên canvas giả lập và kiểm tra hành vi.
class CompositionPainter extends CustomPainter {
  CompositionPainter(this.advice, this.scenicPoint, this.showThirdsHint);

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
  void _paintDot(Canvas canvas, Offset c, {Color color = Colors.white}) {
    canvas.drawCircle(c, 9, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(c, 7, Paint()..color = color);
    canvas.drawCircle(
      c,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.6),
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
      // Trùng đích: vòng xác nhận quanh dấu +.
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

    // Vòng ngắm cầu vồng: halo tối để nổi trên mọi nền + viền SweepGradient.
    canvas.drawCircle(
      aim,
      16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = Colors.black.withValues(alpha: 0.3),
    );
    final ringRect = Rect.fromCircle(center: aim, radius: 15);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF8A8A),
          Color(0xFFFFD48A),
          Color(0xFFA8FF9E),
          Color(0xFF8AD1FF),
          Color(0xFFC29EFF),
          Color(0xFFFF8A8A),
        ],
      ).createShader(ringRect);
    canvas.drawCircle(aim, 15, ringPaint);
    // Chấm nhỏ ở tâm vòng giúp ngắm chính xác.
    canvas.drawCircle(aim, 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CompositionPainter oldDelegate) =>
      oldDelegate.advice != advice ||
      oldDelegate.scenicPoint != scenicPoint ||
      oldDelegate.showThirdsHint != showThirdsHint;
}
