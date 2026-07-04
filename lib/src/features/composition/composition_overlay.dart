import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'composition_advisor.dart';

/// Vẽ hướng dẫn bố cục lên viewfinder: khung chủ thể, điểm đích,
/// mũi tên di chuyển; chuyển xanh khi đã vào bố cục.
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
    if (a == null) return;

    final color = a.isAligned
        ? Colors.greenAccent
        : (a.isLocked ? Colors.amber : Colors.white70);

    // Khung chủ thể.
    final rect = Rect.fromLTRB(
      a.subjectRect.left * size.width,
      a.subjectRect.top * size.height,
      a.subjectRect.right * size.width,
      a.subjectRect.bottom * size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.85),
    );

    // Điểm đích.
    final target = Offset(a.target.dx * size.width, a.target.dy * size.height);
    canvas.drawCircle(
      target,
      a.isAligned ? 10 : 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );

    if (a.isAligned) {
      canvas.drawCircle(target, 3.5, Paint()..color = color);
      return;
    }

    // Mũi tên từ tâm chủ thể về điểm đích.
    final from = Offset(
      a.subjectCenter.dx * size.width,
      a.subjectCenter.dy * size.height,
    );
    final direction = target - from;
    if (direction.distance < 1) return;
    final unit = direction / direction.distance;
    final start = from + unit * 14;
    final end = target - unit * 14;
    if ((end - start).distance < 8) return;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawLine(start, end, line);

    // Đầu mũi tên.
    final angle = math.atan2(unit.dy, unit.dx);
    const headLength = 9.0;
    const headAngle = 2.6;
    canvas.drawLine(
      end,
      end +
          Offset(
            headLength * math.cos(angle + headAngle),
            headLength * math.sin(angle + headAngle),
          ),
      line,
    );
    canvas.drawLine(
      end,
      end +
          Offset(
            headLength * math.cos(angle - headAngle),
            headLength * math.sin(angle - headAngle),
          ),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _CompositionPainter oldDelegate) =>
      oldDelegate.advice != advice;
}
