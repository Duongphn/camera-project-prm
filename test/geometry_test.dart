import 'dart:math' as math;

import 'package:doka_app/src/core/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('centeredCropRect', () {
    test('crop 3:4 từ ảnh dọc 3000x4000 giữ nguyên toàn khung', () {
      final rect = centeredCropRect(3000, 4000, 3 / 4);
      expect(rect.width, 3000);
      expect(rect.height, 4000);
      expect(rect.left, 0);
      expect(rect.top, 0);
    });

    test('crop 1:1 từ ảnh dọc cắt chiều cao, căn giữa', () {
      final rect = centeredCropRect(3000, 4000, 1);
      expect(rect.width, 3000);
      expect(rect.height, 3000);
      expect(rect.left, 0);
      expect(rect.top, 500);
    });

    test('crop 9:16 từ ảnh dọc 3:4 cắt chiều rộng, căn giữa', () {
      final rect = centeredCropRect(3000, 4000, 9 / 16);
      expect(rect.height, 4000);
      expect(rect.width, closeTo(2250, 0.001));
      expect(rect.left, closeTo(375, 0.001));
      expect(rect.top, 0);
    });

    test('crop từ ảnh ngang (EXIF chưa áp) với tỉ lệ đảo', () {
      // PhotoProcessor đảo tỉ lệ khi ảnh nằm ngang: 3:4 → 4:3.
      final rect = centeredCropRect(4000, 3000, 4 / 3);
      expect(rect.width, 4000);
      expect(rect.height, 3000);
    });
  });

  group('rollRadians / isLevel', () {
    test('máy dựng thẳng → roll 0, level', () {
      final roll = rollRadians(0, 9.8);
      expect(roll, 0);
      expect(isLevel(roll), isTrue);
    });

    test('máy nghiêng 45° → không level', () {
      final roll = rollRadians(9.8, 9.8);
      expect(roll.abs(), closeTo(math.pi / 4, 0.001));
      expect(isLevel(roll), isFalse);
    });

    test('nghiêng 1.5° vẫn tính là level với dung sai 2°', () {
      final roll = 1.5 * math.pi / 180;
      expect(isLevel(roll), isTrue);
      expect(isLevel(-roll), isTrue);
    });
  });
}
