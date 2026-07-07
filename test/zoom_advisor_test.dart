import 'dart:ui';

import 'package:doka_app/src/features/composition/zoom_advisor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('crop toàn khung → zoom 1', () {
    expect(
      zoomForCrop(const Rect.fromLTWH(0, 0, 1, 1), maxZoom: 8),
      1.0,
    );
  });

  test('crop nửa khung → zoom 2 (theo cạnh lớn hơn)', () {
    expect(
      zoomForCrop(const Rect.fromLTWH(0.25, 0.1, 0.5, 0.3), maxZoom: 8),
      2.0,
    );
  });

  test('crop rất nhỏ bị kẹp về maxZoom', () {
    expect(
      zoomForCrop(const Rect.fromLTWH(0.4, 0.4, 0.1, 0.1), maxZoom: 4),
      4.0,
    );
  });

  test('rect suy biến (cạnh 0) → zoom 1, không chia cho 0', () {
    expect(
      zoomForCrop(const Rect.fromLTWH(0.2, 0.2, 0, 0), maxZoom: 8),
      1.0,
    );
  });
}
