import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:doka_app/src/features/composition/viewfinder_crop.dart';

Uint8List _solidJpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(120, 140, 160));
  return Uint8List.fromList(img.encodeJpg(im));
}

void main() {
  test('cắt ảnh 3:4 về khung 1:1 → ảnh vuông, cắt hai cạnh dài', () {
    final bytes = _solidJpeg(600, 800); // rộng/cao = 0.75
    final framed = frameToViewfinder(bytes, 1.0);
    expect(framed, isNotNull);
    // 1:1 từ 600x800 → 600x600.
    expect(framed!.size.width, framed.size.height);
    expect(framed.size.width, 600);
  });

  test('ảnh vốn đúng tỉ lệ khung → giữ nguyên kích thước', () {
    final bytes = _solidJpeg(600, 800); // 3:4
    final framed = frameToViewfinder(bytes, 3 / 4);
    expect(framed, isNotNull);
    expect(framed!.size.width, 600);
    expect(framed.size.height, 800);
  });

  test('cắt về 9:16 hẹp hơn → giảm bề rộng', () {
    final bytes = _solidJpeg(600, 800); // 3:4 = 0.75
    final framed = frameToViewfinder(bytes, 9 / 16); // 0.5625, hẹp hơn
    expect(framed, isNotNull);
    // Giữ cao 800, rộng = 800 * 9/16 = 450.
    expect(framed!.size.height, 800);
    expect(framed.size.width, 450);
  });

  test('tỉ lệ ảnh ra khớp aspect yêu cầu (sai số < 1%)', () {
    final bytes = _solidJpeg(1000, 750); // ngang 4:3
    final framed = frameToViewfinder(bytes, 3 / 4); // muốn dọc 3:4
    expect(framed, isNotNull);
    final ratio = framed!.size.width / framed.size.height;
    expect((ratio - 3 / 4).abs() < 0.01, isTrue);
  });

  test('bytes không hợp lệ → null', () {
    final framed = frameToViewfinder(Uint8List.fromList([1, 2, 3]), 1.0);
    expect(framed, isNull);
  });
}
