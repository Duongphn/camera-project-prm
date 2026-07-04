import 'package:flutter/material.dart';

import 'composition_advisor.dart';

/// Dẫn hướng bố cục kiểu ngắm: một nốt tròn đánh dấu điểm cần ngắm và một
/// dấu + cố định giữa màn hình. Di máy cho dấu + trùng nốt tròn là chủ thể
/// vào đúng điểm bố cục đẹp — mọi thứ chuyển xanh khi trùng.
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
    final color = aligned
        ? Colors.greenAccent
        : (a?.isLocked ?? false ? Colors.amber : Colors.white);

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

    // Nốt tròn: lõi đặc + viền tối để nổi trên mọi nền.
    canvas.drawCircle(
      aim,
      9,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
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
      oldDelegate.advice != advice;
}
