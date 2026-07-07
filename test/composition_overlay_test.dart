import 'package:doka_app/src/features/composition/composition_advisor.dart';
import 'package:doka_app/src/features/composition/composition_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canvas giả lập chỉ đếm số lần gọi drawCircle/drawLine — đủ để phân biệt
/// 4 chế độ vẽ của [CompositionPainter] mà không cần golden image.
class _RecordingCanvas implements Canvas {
  int circles = 0;
  int lines = 0;

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles++;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, height: 400, child: child),
        ),
      );

  testWidgets('vẽ nốt tròn tĩnh khi có scenicPoint, không advice',
      (tester) async {
    await tester.pumpWidget(
      wrap(const CompositionOverlay(scenicPoint: Offset(0.5, 0.5))),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('vẽ gợi ý lưới 1/3 khi showThirdsHint và không có điểm',
      (tester) async {
    await tester.pumpWidget(
      wrap(const CompositionOverlay(showThirdsHint: true)),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });

  const size = Size(300, 400);

  CompositionAdvice buildAdvice({required bool isAligned}) {
    const subjectRect = Rect.fromLTWH(0.2, 0.2, 0.3, 0.3);
    const subjectCenter = Offset(0.35, 0.35);
    const target = Offset(1 / 3, 1 / 3);
    return CompositionAdvice(
      subjectRect: subjectRect,
      subjectCenter: subjectCenter,
      target: target,
      aimPoint: isAligned ? const Offset(0.5, 0.5) : const Offset(0.6, 0.6),
      isAligned: isAligned,
      isLocked: false,
    );
  }

  test('chế độ dẫn ngắm - chưa vào bố cục: vẽ dấu + (2 line) và nốt đích '
      '(3 circle: halo+lõi+viền)', () {
    final painter = CompositionPainter(buildAdvice(isAligned: false), null, false);
    final canvas = _RecordingCanvas();

    painter.paint(canvas, size);

    expect(canvas.lines, 2);
    expect(canvas.circles, 3);
  });

  test('chế độ dẫn ngắm - đã vào bố cục: vẫn vẽ dấu + (2 line) nhưng chỉ '
      'vòng xác nhận (1 circle)', () {
    final painter = CompositionPainter(buildAdvice(isAligned: true), null, false);
    final canvas = _RecordingCanvas();

    painter.paint(canvas, size);

    expect(canvas.lines, 2);
    expect(canvas.circles, 1);
  });

  test('chế độ nốt tròn tĩnh (scenicPoint): không có dấu +, 3 circle', () {
    final painter = CompositionPainter(null, const Offset(0.5, 0.5), false);
    final canvas = _RecordingCanvas();

    painter.paint(canvas, size);

    expect(canvas.lines, 0);
    expect(canvas.circles, 3);
  });

  test('chế độ gợi ý lưới 1/3: không có dấu +, 4 circle (4 giao điểm)', () {
    final painter = CompositionPainter(null, null, true);
    final canvas = _RecordingCanvas();

    painter.paint(canvas, size);

    expect(canvas.lines, 0);
    expect(canvas.circles, 4);
  });
}
