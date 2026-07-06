import 'package:doka_app/src/features/camera/widgets/ai_toast_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('hiện message, tự thu gọn sau autoHideAfter, bấm ↩ hiện lại',
      (tester) async {
    await tester.pumpWidget(
      wrap(const AiToastCard(
        message: 'Phong cảnh đô thị — gợi ý Đà Lạt',
        autoHideAfter: Duration(seconds: 2),
      )),
    );
    expect(find.text('Phong cảnh đô thị — gợi ý Đà Lạt'), findsOneWidget);

    // Sau autoHide: text ẩn, còn nút hiện lại.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Phong cảnh đô thị — gợi ý Đà Lạt'), findsNothing);
    expect(find.byIcon(Icons.u_turn_left), findsOneWidget);

    // Bấm nút → hiện lại.
    await tester.tap(find.byIcon(Icons.u_turn_left));
    await tester.pumpAndSettle();
    expect(find.text('Phong cảnh đô thị — gợi ý Đà Lạt'), findsOneWidget);
    // Chạy hết timer còn treo để test kết thúc sạch.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('đổi message → tự hiện lại', (tester) async {
    await tester.pumpWidget(
      wrap(const AiToastCard(
        message: 'A',
        autoHideAfter: Duration(seconds: 1),
      )),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);

    await tester.pumpWidget(
      wrap(const AiToastCard(
        message: 'B',
        autoHideAfter: Duration(seconds: 1),
      )),
    );
    await tester.pump();
    expect(find.text('B'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
