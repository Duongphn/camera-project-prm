import 'package:doka_app/src/features/analysis/scene_analyzer.dart';
import 'package:doka_app/src/features/filters/film_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sceneFromPreset map preset → SceneAnalysis on-device', () {
    final preset = filmPresets.firstWhere((p) => p.id == 'dalat');
    final a = sceneFromPreset(preset);
    expect(a.presetId, 'dalat');
    expect(a.fromCloud, isFalse);
    expect(a.targetPoint, isNull);
    expect(a.reason, contains(preset.name));
  });
}
