import 'dart:convert';
import 'dart:typed_data';

import 'package:doka_app/src/features/analysis/scene_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

Uint8List _fakeJpeg() =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: 100, height: 100)));

void main() {
  test('thiếu API key → ném MissingApiKeyException', () async {
    final analyzer = GeminiSceneAnalyzer(apiKey: '');
    expect(
      () => analyzer.analyze(jpegBytes: _fakeJpeg(), filePath: 'x.jpg'),
      throwsA(isA<MissingApiKeyException>()),
    );
  });

  test('phản hồi 200 hợp lệ, UTF-8 bytes không kèm charset → giữ nguyên tiếng Việt', () async {
    final geminiPayload = jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text': jsonEncode({
                  'presetId': 'kem',
                  'reason': 'chân dung ấm áp',
                  'targetX': 0.66,
                  'targetY': 0.33,
                  'tips': ['hạ máy'],
                }),
              },
            ],
          },
        },
      ],
    });
    // Cố tình KHÔNG khai báo charset trong content-type và trả về bytes UTF-8
    // thô, để chứng minh việc giải mã phải dùng utf8.decode(resp.bodyBytes)
    // thay vì dựa vào resp.body (có thể suy ra sai charset).
    final client = MockClient(
      (req) async => http.Response.bytes(
        utf8.encode(geminiPayload),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final analyzer = GeminiSceneAnalyzer(apiKey: 'k', client: client);

    final a = await analyzer.analyze(jpegBytes: _fakeJpeg(), filePath: 'x.jpg');
    expect(a.presetId, 'kem');
    expect(a.fromCloud, isTrue);
    expect(a.targetPoint!.dx, closeTo(0.66, 1e-9));
    expect(a.tips.single, 'hạ máy');
    expect(a.reason, 'chân dung ấm áp');
  });

  test('HTTP lỗi (500) → ném lỗi để phía gọi fallback', () async {
    final client = MockClient((req) async => http.Response('boom', 500));
    final analyzer = GeminiSceneAnalyzer(apiKey: 'k', client: client);
    expect(
      () => analyzer.analyze(jpegBytes: _fakeJpeg(), filePath: 'x.jpg'),
      throwsA(isA<Exception>()),
    );
  });

  test('phản hồi 200 với candidates rỗng → ném Exception (không phải Error)', () async {
    final client = MockClient(
      (req) async => http.Response(
        jsonEncode({'candidates': []}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final analyzer = GeminiSceneAnalyzer(apiKey: 'k', client: client);
    expect(
      () => analyzer.analyze(jpegBytes: _fakeJpeg(), filePath: 'x.jpg'),
      throwsA(isA<Exception>()),
    );
  });
}
