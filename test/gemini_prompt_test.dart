import 'dart:ui';

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

  test('parse cropRect + advice hợp lệ', () {
    final a = parseGeminiJson({
      'presetId': 'dalat',
      'cropX': 0.1,
      'cropY': 0.2,
      'cropW': 0.5,
      'cropH': 0.6,
      'advice': ' Ảnh dọc, chủ thể căn giữa, chừa khoảng trống. ',
    }, validIds: ids);
    expect(a.cropRect, const Rect.fromLTWH(0.1, 0.2, 0.5, 0.6));
    expect(a.advice, 'Ảnh dọc, chủ thể căn giữa, chừa khoảng trống.');
  });

  test('cropRect thiếu trường hoặc tràn khung → null', () {
    // thiếu cropH
    expect(
      parseGeminiJson(
        {'presetId': 'dalat', 'cropX': 0.1, 'cropY': 0.1, 'cropW': 0.5},
        validIds: ids,
      ).cropRect,
      isNull,
    );
    // w = 0
    expect(
      parseGeminiJson(
        {'presetId': 'dalat', 'cropX': 0.1, 'cropY': 0.1, 'cropW': 0.0, 'cropH': 0.5},
        validIds: ids,
      ).cropRect,
      isNull,
    );
    // tràn phải: x + w > 1
    expect(
      parseGeminiJson(
        {'presetId': 'dalat', 'cropX': 0.7, 'cropY': 0.1, 'cropW': 0.5, 'cropH': 0.5},
        validIds: ids,
      ).cropRect,
      isNull,
    );
  });

  test('advice rỗng → null; mặc định cropRect/advice null', () {
    final a = parseGeminiJson(
      {'presetId': 'dalat', 'advice': '   '},
      validIds: ids,
    );
    expect(a.advice, isNull);
    expect(a.cropRect, isNull);
  });

  test('schema và prompt khai báo trường crop + advice', () {
    final props =
        sceneResponseSchema['properties'] as Map<String, dynamic>;
    expect(props.containsKey('cropX'), isTrue);
    expect(props.containsKey('cropY'), isTrue);
    expect(props.containsKey('cropW'), isTrue);
    expect(props.containsKey('cropH'), isTrue);
    expect(props.containsKey('advice'), isTrue);
    final prompt = buildScenePrompt(filmPresets);
    expect(prompt.contains('cropX'), isTrue);
    expect(prompt.contains('advice'), isTrue);
  });
}
