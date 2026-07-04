import 'dart:ui' as ui;

/// Đóng gói float uniform theo thứ tự khai báo trong shaders/beauty.frag
/// (index 0,1 là u_size).
List<double> packBeautyUniforms({
  required double width,
  required double height,
  required double intensity,
}) {
  return [width, height, intensity.clamp(0.0, 1.0)];
}

void applyBeautyUniforms(
  ui.FragmentShader shader, {
  double width = 0,
  double height = 0,
  required double intensity,
}) {
  final values =
      packBeautyUniforms(width: width, height: height, intensity: intensity);
  for (var i = 0; i < values.length; i++) {
    shader.setFloat(i, values[i]);
  }
}

/// Cache FragmentProgram của shader beauty (chỉ load 1 lần).
class BeautyShaderProgram {
  BeautyShaderProgram._();

  static ui.FragmentProgram? _program;

  static Future<ui.FragmentProgram> load() async =>
      _program ??= await ui.FragmentProgram.fromAsset('shaders/beauty.frag');
}
