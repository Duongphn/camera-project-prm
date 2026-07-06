import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hiệu ứng pha "AI đang phân tích": ~48 chấm sáng pastel rải ngẫu nhiên,
/// nhấp nháy, rồi gom dần về các mắt lưới (kiểu Doka Cam).
class AnalyzingSparkleOverlay extends StatefulWidget {
  const AnalyzingSparkleOverlay({super.key});

  @override
  State<AnalyzingSparkleOverlay> createState() =>
      _AnalyzingSparkleOverlayState();
}

class _AnalyzingSparkleOverlayState extends State<AnalyzingSparkleOverlay>
    with TickerProviderStateMixin {
  /// Tiến độ gom về lưới: chạy 1 lần ~2s.
  late final AnimationController _gather = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..forward();

  /// Nhấp nháy liên tục.
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _gather.dispose();
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _SparklePainter(
          gather: _gather,
          twinkle: _twinkle,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.gather, required this.twinkle})
      : super(repaint: Listenable.merge([gather, twinkle]));

  final Animation<double> gather;
  final Animation<double> twinkle;

  static const int _cols = 6;
  static const int _rows = 8;
  static const List<Color> _palette = [
    Color(0xFF8DE8FF), // cyan nhạt
    Color(0xFFFFB3E2), // hồng nhạt
    Color(0xFFB8C6FF), // tím nhạt
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Seed cố định → vị trí ổn định giữa các frame.
    final random = math.Random(7);
    final t = Curves.easeInOut.transform(gather.value);
    for (var i = 0; i < _cols * _rows; i++) {
      final scatter = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final grid = Offset(
        ((i % _cols) + 0.5) / _cols * size.width,
        ((i ~/ _cols) + 0.5) / _rows * size.height,
      );
      final pos = Offset.lerp(scatter, grid, t)!;
      // Mỗi chấm lệch pha nhấp nháy khác nhau.
      final phase = random.nextDouble();
      final blink =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin((twinkle.value + phase) * 2 * math.pi));
      final color = _palette[i % _palette.length];
      canvas.drawCircle(
        pos,
        2.4,
        Paint()
          ..color = color.withValues(alpha: blink)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) => false;
}
