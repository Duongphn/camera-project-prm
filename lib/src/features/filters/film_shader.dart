import 'dart:ui' as ui;

import 'film_preset.dart';

/// Đóng gói các float uniform theo đúng thứ tự khai báo trong
/// shaders/film.frag (index 0,1 là u_size).
List<double> packFilmUniforms(
  FilmPreset p, {
  required double width,
  required double height,
  double seed = 7,
}) {
  return [
    width, height, // u_size (chế độ preview sẽ bị engine ghi đè)
    p.exposure,
    p.contrast,
    p.saturation,
    p.temperature,
    p.tint,
    p.fade,
    p.vignette,
    p.grain,
    seed,
    ...p.shadowTint,
    p.shadowStrength,
    ...p.highlightTint,
    p.highlightStrength,
  ];
}

/// Ghi toàn bộ uniform của [preset] vào [shader].
void applyFilmUniforms(
  ui.FragmentShader shader,
  FilmPreset preset, {
  double width = 0,
  double height = 0,
  double seed = 7,
}) {
  final values =
      packFilmUniforms(preset, width: width, height: height, seed: seed);
  for (var i = 0; i < values.length; i++) {
    shader.setFloat(i, values[i]);
  }
}

/// Cache FragmentProgram của shader phim (chỉ load 1 lần).
class FilmShaderProgram {
  FilmShaderProgram._();

  static ui.FragmentProgram? _program;

  static Future<ui.FragmentProgram> load() async =>
      _program ??= await ui.FragmentProgram.fromAsset('shaders/film.frag');
}
