import 'package:doka_app/src/features/camera/widgets/analyzing_sparkle_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render và animate không lỗi, không chặn tap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapped = true,
              child: const SizedBox.expand(),
            ),
            const AnalyzingSparkleOverlay(),
          ],
        ),
      ),
    );
    // Chạy qua pha gom lưới (2s) + vài nhịp nhấp nháy.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(AnalyzingSparkleOverlay), findsOneWidget);
    // Overlay phải IgnorePointer — tap xuyên qua được.
    await tester.tapAt(const Offset(200, 300));
    expect(tapped, isTrue);
  });
}
