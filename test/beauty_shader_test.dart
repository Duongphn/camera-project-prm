import 'package:doka_app/src/features/filters/beauty_shader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packBeautyUniforms đúng thứ tự u_size rồi u_intensity', () {
    final u = packBeautyUniforms(width: 100, height: 200, intensity: 0.5);
    expect(u, [100, 200, 0.5]);
  });

  test('intensity bị clamp về [0,1]', () {
    expect(packBeautyUniforms(width: 1, height: 1, intensity: 2.0).last, 1.0);
    expect(packBeautyUniforms(width: 1, height: 1, intensity: -1.0).last, 0.0);
  });
}
