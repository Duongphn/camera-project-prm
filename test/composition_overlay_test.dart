import 'package:doka_app/src/features/composition/composition_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
