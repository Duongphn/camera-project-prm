import 'dart:typed_data';

import 'package:doka_app/src/features/filters/photo_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('encodeRgbaToJpeg cho ra JPEG hợp lệ đúng kích thước', () {
    const w = 4, h = 2;
    final rgba = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      rgba[i * 4] = 255; // R
      rgba[i * 4 + 1] = 128; // G
      rgba[i * 4 + 2] = 0; // B
      rgba[i * 4 + 3] = 255; // A
    }

    final jpeg = encodeRgbaToJpeg(rgba, w, h);

    // Magic bytes JPEG.
    expect(jpeg[0], 0xFF);
    expect(jpeg[1], 0xD8);

    final decoded = img.decodeJpg(jpeg);
    expect(decoded, isNotNull);
    expect(decoded!.width, w);
    expect(decoded.height, h);
    final px = decoded.getPixel(0, 0);
    expect(px.r, closeTo(255, 10));
    expect(px.g, closeTo(128, 10));
    expect(px.b, closeTo(0, 10));
  });
}
