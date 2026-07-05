import 'dart:ui';

import 'package:doka_app/src/features/analysis/scene_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mặc định: tips rỗng, fromCloud=false, các field optional null', () {
    const a = SceneAnalysis(presetId: 'dalat');
    expect(a.presetId, 'dalat');
    expect(a.tips, isEmpty);
    expect(a.fromCloud, isFalse);
    expect(a.reason, isNull);
    expect(a.targetPoint, isNull);
  });

  test('giữ nguyên giá trị truyền vào', () {
    const a = SceneAnalysis(
      presetId: 'kem',
      reason: 'da mịn',
      mood: 'ấm',
      targetPoint: Offset(0.66, 0.33),
      tips: ['hạ máy'],
      fromCloud: true,
    );
    expect(a.targetPoint, const Offset(0.66, 0.33));
    expect(a.tips.single, 'hạ máy');
    expect(a.fromCloud, isTrue);
  });
}
