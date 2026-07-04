import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Encode buffer RGBA thô thành JPEG. Hàm thuần để chạy được trong isolate.
Uint8List encodeRgbaToJpeg(
  Uint8List rgba,
  int width,
  int height, {
  int quality = 92,
}) {
  final im = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    rowStride: width * 4,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(im, quality: quality);
}
