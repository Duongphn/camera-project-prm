import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doka_app/src/features/filters/photo_encoder.dart';

/// Hàm CẤP CAO NHẤT — closure gửi sang isolate chỉ bắt tham số thuần (giống
/// bản vá `_encodeJpegInIsolate` trong edit_screen.dart). Đặt trong method của
/// class giữ ui.Image thì closure sẽ bắt luôn `this` → ui.Image không gửi được
/// → lỗi "object is unsendable" khi lưu ảnh đã chỉnh.
Future<Uint8List> encodeTopLevel(Uint8List rgba, int w, int h) {
  return Isolate.run(() => encodeRgbaToJpeg(rgba, w, h));
}

/// Mô phỏng _EditScreenState: object giữ ui.Image, uỷ thác mã hoá cho hàm cấp
/// cao nhất — không kéo `this` vào closure isolate.
class _HolderLikeState {
  _HolderLikeState(this.image);
  final ui.Image image;

  Future<Uint8List> encodeViaTopLevel(Uint8List rgba, int w, int h) {
    return encodeTopLevel(rgba, w, h);
  }
}

Future<ui.Image> _makeImage(int w, int h) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF8899AA),
  );
  return recorder.endRecording().toImage(w, h);
}

void main() {
  testWidgets(
      'object giữ ui.Image mã hoá JPEG qua isolate (hàm cấp cao nhất) không lỗi',
      (tester) async {
    await tester.runAsync(() async {
      const w = 4, h = 4;
      final rgba = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 200);
      final image = await _makeImage(w, h);
      final holder = _HolderLikeState(image);

      final jpeg = await holder.encodeViaTopLevel(rgba, w, h);

      // JPEG hợp lệ: magic bytes FF D8.
      expect(jpeg.length, greaterThan(2));
      expect(jpeg[0], 0xFF);
      expect(jpeg[1], 0xD8);
      image.dispose();
    });
  });
}
