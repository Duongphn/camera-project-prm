import 'package:flutter/material.dart';

import 'composition_advisor.dart';

/// Dẫn hướng bố cục kiểu ngắm: một vòng tròn cầu vồng đánh dấu điểm cần ngắm
/// và một dấu + cố định giữa màn hình. Di máy cho dấu + trùng vòng tròn là
/// chủ thể vào đúng điểm bố cục đẹp — mọi thứ chuyển xanh khi trùng.
class CompositionOverlay extends StatelessWidget {
  const CompositionOverlay({super.key, required this.advice});

  final CompositionAdvice? advice;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CompositionPainter(advice),
        size: Size.infinite,
      ),
    );
  }
}

class _CompositionPainter extends CustomPainter {
  _CompositionPainter(this.advice);

  final CompositionAdvice? advice;

  @override
  void paint(Canvas canvas, Size size) {
    final a = advice;
    final aligned = a?.isAligned ?? false;

    // Dấu + cố định giữa màn hình (luôn hiện khi bật AI bố cục).
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

    if (a == null) return;

    // Nốt tròn tại điểm ngắm; nếu ra ngoài khung thì ghim vào mép để người
    // dùng vẫn thấy hướng cần di máy.
    final aim = Offset(
      (a.aimPoint.dx.clamp(0.04, 0.96)) * size.width,
      (a.aimPoint.dy.clamp(0.04, 0.96)) * size.height,
    );

    if (aligned) {
      // Trùng đích: vòng xác nhận quanh dấu +.
      final color = Colors.greenAccent;
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
  bool shouldRepaint(covariant _CompositionPainter oldDelegate) =>
      oldDelegate.advice != advice;
}
