import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import '../filters/film_preset.dart';
import 'suggestion_rules.dart';

/// Gợi ý filter cho một khung cảnh: nhận diện nhãn bằng ML Kit (on-device)
/// kết hợp độ sáng trung bình, rồi map sang preset bằng suggestion_rules.
class FilterSuggester {
  FilterSuggester._();

  static Future<FilmPreset> suggest({
    required String filePath,
    required Uint8List bytes,
  }) async {
    final luma = await _lumaOfEncoded(bytes);
    final labels = await _detectLabels(filePath);
    final id = suggestPresetId(labels: labels, avgLuma: luma);
    return filmPresets.firstWhere(
      (p) => p.id == id,
      orElse: () => filmPresets.first,
    );
  }

  static Future<double> _lumaOfEncoded(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 48);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final raw =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (raw == null) return 0.5;
        return averageLuma(raw.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  static Future<Map<String, double>> _detectLabels(String filePath) async {
    ImageLabeler? labeler;
    try {
      labeler = ImageLabeler(
        options: ImageLabelerOptions(confidenceThreshold: 0.5),
      );
      final results =
          await labeler.processImage(InputImage.fromFilePath(filePath));
      return {
        for (final label in results) label.label.toLowerCase(): label.confidence,
      };
    } catch (_) {
      // ML Kit chưa sẵn sàng (thiếu Play Services, model chưa tải...):
      // vẫn gợi ý được bằng độ sáng.
      return const {};
    } finally {
      labeler?.close();
    }
  }
}
