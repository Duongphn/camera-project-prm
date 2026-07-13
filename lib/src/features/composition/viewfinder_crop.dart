import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../../core/geometry.dart';

/// Ảnh đã cắt khớp khung ngắm, kèm kích thước pixel của nó.
class FramedImage {
  const FramedImage({required this.jpeg, required this.size});

  final Uint8List jpeg;
  final Size size;
}

/// Xoay thẳng ảnh JPEG rồi center-crop về đúng [aspect] (rộng/cao) của khung
/// ngắm, để Gemini chỉ "thấy" đúng phần người dùng đang thấy.
///
/// Nhờ vậy toạ độ 0..1 Gemini trả về khớp 1:1 với khung ngắm — điểm bố cục
/// không còn rơi vào vùng đã bị khung ngắm cắt mất (không "nhảy ra ngoài").
///
/// Trả null nếu không giải mã được ảnh.
FramedImage? frameToViewfinder(
  Uint8List jpegBytes,
  double aspect, {
  int quality = 90,
}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(jpegBytes);
  } catch (_) {
    // Bytes hỏng/không phải ảnh → coi như không cắt được.
    return null;
  }
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  final crop = centeredCropRect(upright.width, upright.height, aspect);
  final framed = img.copyCrop(
    upright,
    x: crop.left.round(),
    y: crop.top.round(),
    width: crop.width.round(),
    height: crop.height.round(),
  );
  return FramedImage(
    jpeg: Uint8List.fromList(img.encodeJpg(framed, quality: quality)),
    size: Size(framed.width.toDouble(), framed.height.toDouble()),
  );
}
