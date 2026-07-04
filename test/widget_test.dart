import 'package:doka_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App khởi động không crash khi không có camera thật',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DokaApp()));
    // Không dùng pumpAndSettle vì spinner loading animate vô hạn.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(Scaffold), findsOneWidget);
    // Tuỳ môi trường test, app hiển thị trạng thái lỗi camera (nút Thử lại)
    // hoặc UI camera đang chờ khởi tạo (thanh công cụ với tỉ lệ 3:4).
    final showsError = find.text('Thử lại').evaluate().isNotEmpty;
    final showsCameraUi = find.text('3:4').evaluate().isNotEmpty;
    expect(showsError || showsCameraUi, isTrue,
        reason: 'Phải hiển thị UI camera hoặc trạng thái lỗi, không crash');
  });
}
