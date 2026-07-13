import 'package:doka_app/src/features/editor/ai/quick_edits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('có đúng 4 nút nhanh, nhãn + prompt đều khác rỗng', () {
    expect(quickEdits.length, 4);
    for (final q in quickEdits) {
      expect(q.label.trim(), isNotEmpty);
      expect(q.prompt.trim(), isNotEmpty);
    }
  });
}
