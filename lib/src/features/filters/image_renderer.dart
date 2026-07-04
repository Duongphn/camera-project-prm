import 'dart:ui' as ui;

import 'beauty_shader.dart';
import 'film_preset.dart';
import 'film_shader.dart';

/// Các pass render ảnh trên GPU, dùng chung cho chụp (bake full-res)
/// và màn hình chỉnh ảnh (preview downscale).
class ImageRenderer {
  ImageRenderer._();

  /// Cắt [src] theo [crop] ra ảnh mới kích thước [width]x[height].
  static Future<ui.Image> crop(
    ui.Image src,
    ui.Rect crop,
    int width,
    int height,
  ) {
    return _draw(width, height, (canvas) {
      canvas.drawImageRect(
        src,
        crop,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
    });
  }

  /// Thu nhỏ [src] về chiều rộng [targetWidth], giữ tỉ lệ.
  static Future<ui.Image> downscale(ui.Image src, int targetWidth) {
    if (src.width <= targetWidth) {
      return crop(
        src,
        ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        src.width,
        src.height,
      );
    }
    final height = (src.height * targetWidth / src.width).round();
    return crop(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      targetWidth,
      height,
    );
  }

  /// Pass màu phim: áp [preset] lên toàn ảnh.
  static Future<ui.Image> filmPass(
    ui.Image src,
    FilmPreset preset, {
    double seed = 7,
  }) async {
    final program = await FilmShaderProgram.load();
    final shader = program.fragmentShader();
    try {
      applyFilmUniforms(
        shader,
        preset,
        width: src.width.toDouble(),
        height: src.height.toDouble(),
        seed: seed,
      );
      shader.setImageSampler(0, src);
      return await _shaderPass(shader, src.width, src.height);
    } finally {
      shader.dispose();
    }
  }

  /// Pass làm mịn da với cường độ [intensity] (0..1).
  static Future<ui.Image> beautyPass(ui.Image src, double intensity) async {
    final program = await BeautyShaderProgram.load();
    final shader = program.fragmentShader();
    try {
      applyBeautyUniforms(
        shader,
        width: src.width.toDouble(),
        height: src.height.toDouble(),
        intensity: intensity,
      );
      shader.setImageSampler(0, src);
      return await _shaderPass(shader, src.width, src.height);
    } finally {
      shader.dispose();
    }
  }

  static Future<ui.Image> _shaderPass(
    ui.FragmentShader shader,
    int width,
    int height,
  ) {
    return _draw(width, height, (canvas) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..shader = shader,
      );
    });
  }

  static Future<ui.Image> _draw(
    int width,
    int height,
    void Function(ui.Canvas) paint,
  ) async {
    final recorder = ui.PictureRecorder();
    paint(ui.Canvas(recorder));
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }
}
