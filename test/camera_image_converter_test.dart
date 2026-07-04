import 'dart:typed_data';

import 'package:doka_app/src/features/composition/camera_image_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('YUV không padding, pixelStride=1 → NV21 đúng thứ tự Y rồi VU', () {
    // Ảnh 4x2: Y = 0..7, U = [10,11], V = [20,21].
    final nv21 = nv21FromYuvPlanes(
      width: 4,
      height: 2,
      yBytes: Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]),
      yRowStride: 4,
      uBytes: Uint8List.fromList([10, 11]),
      uRowStride: 2,
      uPixelStride: 1,
      vBytes: Uint8List.fromList([20, 21]),
      vRowStride: 2,
      vPixelStride: 1,
    );
    expect(nv21, [0, 1, 2, 3, 4, 5, 6, 7, 20, 10, 21, 11]);
  });

  test('Y có padding cuối hàng (rowStride > width) → bỏ padding', () {
    final nv21 = nv21FromYuvPlanes(
      width: 2,
      height: 2,
      // rowStride 4: mỗi hàng 2 byte dữ liệu + 2 byte rác (99).
      yBytes: Uint8List.fromList([1, 2, 99, 99, 3, 4, 99, 99]),
      yRowStride: 4,
      uBytes: Uint8List.fromList([10]),
      uRowStride: 1,
      uPixelStride: 1,
      vBytes: Uint8List.fromList([20]),
      vRowStride: 1,
      vPixelStride: 1,
    );
    expect(nv21, [1, 2, 3, 4, 20, 10]);
  });

  test('U/V xen kẽ pixelStride=2 (semi-planar) → lấy đúng byte', () {
    // uBytes/vBytes là view xen kẽ: giá trị thật ở index chẵn.
    final nv21 = nv21FromYuvPlanes(
      width: 4,
      height: 2,
      yBytes: Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]),
      yRowStride: 4,
      uBytes: Uint8List.fromList([10, 99, 11, 99]),
      uRowStride: 4,
      uPixelStride: 2,
      vBytes: Uint8List.fromList([20, 99, 21, 99]),
      vRowStride: 4,
      vPixelStride: 2,
    );
    expect(nv21.sublist(8), [20, 10, 21, 11]);
  });

  test('kích thước output = w*h*1.5', () {
    final nv21 = nv21FromYuvPlanes(
      width: 8,
      height: 4,
      yBytes: Uint8List(32),
      yRowStride: 8,
      uBytes: Uint8List(8),
      uRowStride: 4,
      uPixelStride: 1,
      vBytes: Uint8List(8),
      vRowStride: 4,
      vPixelStride: 1,
    );
    expect(nv21.length, 48);
  });
}
