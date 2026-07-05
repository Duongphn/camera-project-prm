import 'package:doka_app/src/features/analysis/gemini_prompt.dart';
import 'package:doka_app/src/features/filters/film_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ids = [
    'original', 'saigon89', 'dalat', 'halong', 'chodem',
    'mono400', 'noir', 'retro76', 'xanhreu', 'kem',
  ];

  test('prompt liệt kê mọi id preset', () {
    final prompt = buildScenePrompt(filmPresets);
    for (final p in filmPresets) {
      expect(prompt.contains(p.id), isTrue, reason: 'thiếu ${p.id}');
    }
  });

  test('parse JSON hợp lệ thành SceneAnalysis', () {
    final a = parseGeminiJson({
      'presetId': 'kem',
      'reason': 'da mịn, sáng nhẹ',
      'mood': 'chân dung ấm',
      'targetX': 0.66,
      'targetY': 0.33,
      'tips': ['hạ máy lấy nhiều trời', 'chỉnh ngang chân trời'],
    }, validIds: ids);
    expect(a.presetId, 'kem');
    expect(a.reason, 'da mịn, sáng nhẹ');
    expect(a.targetPoint, const Offset(0.66, 0.33));
    expect(a.tips.length, 2);
    expect(a.fromCloud, isTrue);
  });

  test('presetId lạ bị kẹp về original', () {
    final a = parseGeminiJson({'presetId': 'khong-ton-tai'}, validIds: ids);
    expect(a.presetId, 'original');
  });

  test('thiếu toạ độ → targetPoint null', () {
    final a = parseGeminiJson({'presetId': 'dalat'}, validIds: ids);
    expect(a.targetPoint, isNull);
  });

  test('toạ độ ngoài [0,1] bị loại', () {
    final a = parseGeminiJson(
      {'presetId': 'dalat', 'targetX': 1.5, 'targetY': 0.2},
      validIds: ids,
    );
    expect(a.targetPoint, isNull);
  });

  test('tips cắt còn tối đa 3 và bỏ chuỗi rỗng', () {
    final a = parseGeminiJson({
      'presetId': 'dalat',
      'tips': ['a', '', 'b', 'c', 'd'],
    }, validIds: ids);
    expect(a.tips, ['a', 'b', 'c']);
  });
}
