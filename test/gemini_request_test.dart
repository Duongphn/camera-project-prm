import 'dart:typed_data';

import 'package:doka_app/src/features/analysis/gemini_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('downscale đưa cạnh dài về <= maxEdge', () {
    final src = img.Image(width: 1600, height: 900);
    final jpeg = Uint8List.fromList(img.encodeJpg(src));
    final out = downscaleForVision(jpeg, maxEdge: 768);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, lessThanOrEqualTo(768));
    expect(decoded.height, lessThanOrEqualTo(768));
    expect(decoded.width, greaterThan(decoded.height)); // giữ tỉ lệ
  });

  test('ảnh nhỏ hơn maxEdge không bị phóng to', () {
    final src = img.Image(width: 320, height: 240);
    final jpeg = Uint8List.fromList(img.encodeJpg(src));
    final out = downscaleForVision(jpeg, maxEdge: 768);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 320);
    expect(decoded.height, 240);
  });

  test('ảnh portrait (chiều cao > chiều rộng) được downscale theo chiều cao', () {
    final src = img.Image(width: 900, height: 1600);
    final jpeg = Uint8List.fromList(img.encodeJpg(src));
    final out = downscaleForVision(jpeg, maxEdge: 768);
    final decoded = img.decodeImage(out)!;
    expect(decoded.height, lessThanOrEqualTo(768));
    expect(decoded.width, lessThanOrEqualTo(768));
    expect(decoded.height, greaterThan(decoded.width)); // giữ tỉ lệ portrait
  });

  test('request body có prompt, ảnh inline và schema', () {
    final body = buildGeminiRequestBody(
      base64Image: 'AAAA',
      promptText: 'phân tích',
      schema: const {'type': 'OBJECT'},
    );
    final parts = (body['contents'] as List).first['parts'] as List;
    expect(parts[0]['text'], 'phân tích');
    expect(parts[1]['inline_data']['mime_type'], 'image/jpeg');
    expect(parts[1]['inline_data']['data'], 'AAAA');
    expect(body['generationConfig']['responseMimeType'], 'application/json');
    expect(body['generationConfig']['responseSchema'], const {'type': 'OBJECT'});
  });
}
