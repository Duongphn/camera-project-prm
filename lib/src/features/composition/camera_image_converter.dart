import 'dart:typed_data';

/// Ghép các plane YUV_420_888 (3 plane, có rowStride/pixelStride) thành
/// buffer NV21 (Y liền mạch + VU xen kẽ) cho ML Kit.
/// Hàm thuần trên mảng byte để test được không cần CameraImage thật.
Uint8List nv21FromYuvPlanes({
  required int width,
  required int height,
  required Uint8List yBytes,
  required int yRowStride,
  required Uint8List uBytes,
  required int uRowStride,
  required int uPixelStride,
  required Uint8List vBytes,
  required int vRowStride,
  required int vPixelStride,
}) {
  final uvWidth = width ~/ 2;
  final uvHeight = height ~/ 2;
  final out = Uint8List(width * height + 2 * uvWidth * uvHeight);

  var offset = 0;
  for (var row = 0; row < height; row++) {
    final start = row * yRowStride;
    out.setRange(offset, offset + width, yBytes, start);
    offset += width;
  }

  for (var row = 0; row < uvHeight; row++) {
    for (var col = 0; col < uvWidth; col++) {
      out[offset++] = vBytes[row * vRowStride + col * vPixelStride];
      out[offset++] = uBytes[row * uRowStride + col * uPixelStride];
    }
  }
  return out;
}
