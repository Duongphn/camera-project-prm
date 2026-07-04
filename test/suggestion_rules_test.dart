import 'dart:typed_data';

import 'package:doka_app/src/features/filters/film_preset.dart';
import 'package:doka_app/src/features/suggestion/suggestion_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('suggestPresetId', () {
    test('cảnh tối → Chợ Đêm, bất kể nhãn', () {
      expect(
        suggestPresetId(labels: {'food': 0.9}, avgLuma: 0.1),
        'chodem',
      );
    });

    test('đồ ăn → Sài Gòn 89', () {
      expect(
        suggestPresetId(labels: {'food': 0.8}, avgLuma: 0.5),
        'saigon89',
      );
    });

    test('người/selfie ưu tiên hơn cảnh vật → Kem', () {
      expect(
        suggestPresetId(labels: {'person': 0.9, 'sky': 0.9}, avgLuma: 0.5),
        'kem',
      );
    });

    test('biển trời → Hạ Long', () {
      expect(
        suggestPresetId(labels: {'beach': 0.7, 'sky': 0.9}, avgLuma: 0.6),
        'halong',
      );
    });

    test('cây cối → Xanh Rêu', () {
      expect(
        suggestPresetId(labels: {'plant': 0.85}, avgLuma: 0.5),
        'xanhreu',
      );
    });

    test('phố xá kiến trúc → Retro 76', () {
      expect(
        suggestPresetId(labels: {'building': 0.7}, avgLuma: 0.5),
        'retro76',
      );
    });

    test('nhãn dưới ngưỡng tin cậy bị bỏ qua → mặc định Đà Lạt', () {
      expect(
        suggestPresetId(labels: {'food': 0.3}, avgLuma: 0.5),
        'dalat',
      );
    });

    test('không có nhãn → mặc định Đà Lạt', () {
      expect(suggestPresetId(labels: {}, avgLuma: 0.5), 'dalat');
    });

    test('mọi id trả về đều tồn tại trong danh sách preset', () {
      final cases = [
        suggestPresetId(labels: {}, avgLuma: 0.1),
        suggestPresetId(labels: {}, avgLuma: 0.5),
        suggestPresetId(labels: {'person': 1}, avgLuma: 0.5),
        suggestPresetId(labels: {'food': 1}, avgLuma: 0.5),
        suggestPresetId(labels: {'sky': 1}, avgLuma: 0.5),
        suggestPresetId(labels: {'plant': 1}, avgLuma: 0.5),
        suggestPresetId(labels: {'building': 1}, avgLuma: 0.5),
        suggestPresetId(labels: {'sunset': 1}, avgLuma: 0.5),
      ];
      final ids = filmPresets.map((p) => p.id).toSet();
      for (final id in cases) {
        expect(ids.contains(id), isTrue, reason: id);
      }
    });
  });

  group('averageLuma', () {
    Uint8List rgba(List<List<int>> pixels) {
      final out = Uint8List(pixels.length * 4);
      for (var i = 0; i < pixels.length; i++) {
        out[i * 4] = pixels[i][0];
        out[i * 4 + 1] = pixels[i][1];
        out[i * 4 + 2] = pixels[i][2];
        out[i * 4 + 3] = 255;
      }
      return out;
    }

    test('ảnh trắng → ~1', () {
      expect(
        averageLuma(rgba([[255, 255, 255], [255, 255, 255]])),
        closeTo(1.0, 0.01),
      );
    });

    test('ảnh đen → 0', () {
      expect(averageLuma(rgba([[0, 0, 0]])), 0);
    });

    test('nửa đen nửa trắng → ~0.5', () {
      expect(
        averageLuma(rgba([[0, 0, 0], [255, 255, 255]])),
        closeTo(0.5, 0.01),
      );
    });

    test('buffer rỗng → 0, không chia cho 0', () {
      expect(averageLuma(Uint8List(0)), 0);
    });
  });
}
