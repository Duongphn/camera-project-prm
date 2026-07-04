import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gal/gal.dart';

import '../../core/geometry.dart';
import '../gallery/photo_repository.dart';
import 'film_preset.dart';
import 'image_renderer.dart';
import 'photo_encoder.dart';

/// Kết quả xử lý một tấm ảnh.
class ProcessedPhoto {
  const ProcessedPhoto({required this.file, required this.savedToGallery});

  final File file;
  final bool savedToGallery;
}

/// Bake filter vào ảnh full-res: decode → crop theo tỉ lệ → beauty → màu phim
/// (render GPU) → encode JPEG trong isolate → lưu vào app + thư viện hệ thống.
class PhotoProcessor {
  static final _random = math.Random();

  static Future<ProcessedPhoto> processAndSave({
    required Uint8List bytes,
    required FilmPreset preset,
    required double aspect,
    required PhotoRepository repository,
    double beauty = 0,
  }) async {
    final src = await _decode(bytes);
    final intermediates = <ui.Image>[src];
    try {
      // Nếu decoder trả ảnh nằm ngang (EXIF chưa được áp), xoay tỉ lệ crop
      // cho khớp chiều ảnh thật.
      final effectiveAspect = src.width > src.height ? 1 / aspect : aspect;
      final cropRect =
          centeredCropRect(src.width, src.height, effectiveAspect);
      final outWidth = cropRect.width.round();
      final outHeight = cropRect.height.round();

      var current =
          await ImageRenderer.crop(src, cropRect, outWidth, outHeight);
      intermediates.add(current);

      if (beauty > 0) {
        current = await ImageRenderer.beautyPass(current, beauty);
        intermediates.add(current);
      }
      if (!preset.isNeutral) {
        current = await ImageRenderer.filmPass(
          current,
          preset,
          seed: _random.nextDouble() * 1000,
        );
        intermediates.add(current);
      }

      final raw = await current.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) {
        throw StateError('Không đọc được dữ liệu ảnh sau khi render.');
      }
      final rgba = raw.buffer.asUint8List();
      final jpeg = await Isolate.run(
        () => encodeRgbaToJpeg(rgba, outWidth, outHeight),
      );

      final file = await repository.savePhoto(jpeg);
      final savedToGallery = await saveToSystemGallery(file);
      return ProcessedPhoto(file: file, savedToGallery: savedToGallery);
    } finally {
      for (final image in intermediates) {
        image.dispose();
      }
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// Lưu một file ảnh vào thư viện hệ thống. Trả về false nếu thiếu quyền.
  static Future<bool> saveToSystemGallery(File file) async {
    try {
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }
      await Gal.putImage(file.path);
      return true;
    } catch (_) {
      // Không có quyền / lỗi hệ thống: ảnh vẫn còn trong thư viện của app.
      return false;
    }
  }
}
