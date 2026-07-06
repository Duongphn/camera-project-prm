import 'package:doka_app/src/features/composition/composition_advisor.dart';
import 'package:doka_app/src/features/composition/composition_overlay.dart';
import 'package:doka_app/src/features/composition/frame_guide_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CompositionOverlay vẽ vòng cầu vồng không lỗi', (tester) async {
    final advice = adviseComposition(
      const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
    );
    await tester.pumpWidget(
      MaterialApp(home: CompositionOverlay(advice: advice)),
    );
    expect(find.byType(CompositionOverlay), findsOneWidget);
  });

  testWidgets('FrameGuideOverlay vẽ khung theo rect, opacity 0 vẫn ổn',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            FrameGuideOverlay(rect: Rect.fromLTWH(0.2, 0.15, 0.6, 0.7)),
            FrameGuideOverlay(
              rect: Rect.fromLTWH(0.2, 0.15, 0.6, 0.7),
              opacity: 0,
            ),
          ],
        ),
      ),
    );
    expect(find.byType(FrameGuideOverlay), findsNWidgets(2));
  });
}
