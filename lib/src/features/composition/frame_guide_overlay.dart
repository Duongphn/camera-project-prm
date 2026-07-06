import 'package:flutter/material.dart';

/// Khung bo góc viền gradient cầu vồng thể hiện vùng crop AI đề xuất
/// (kiểu Doka Cam). [rect] ở không gian 0..1 của viewfinder.
class FrameGuideOverlay extends StatelessWidget {
  const FrameGuideOverlay({
    super.key,
    required this.rect,
    this.opacity = 1,
  });

  final Rect rect;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: CustomPaint(
          painter: _FrameGuidePainter(rect),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _FrameGuidePainter extends CustomPainter {
  _FrameGuidePainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final px = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );
    final rrect = RRect.fromRectAndRadius(px, const Radius.circular(22));
    // Làm mờ nhẹ vùng ngoài khung để hút mắt vào vùng đề xuất.
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );
    // Viền cầu vồng.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF9E9E),
            Color(0xFFFFE29E),
            Color(0xFFB6FFAE),
            Color(0xFF9EDCFF),
            Color(0xFFD3B4FF),
          ],
        ).createShader(px),
    );
  }

  @override
  bool shouldRepaint(covariant _FrameGuidePainter oldDelegate) =>
      oldDelegate.rect != rect;
}
