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
    // Cố tình KHÔNG gửi header content-type nào cả. Gói http sẽ mặc định coi
    // đây là 'text/plain; charset=ISO-8859-1' và resp.body sẽ giải mã sai
    // (mojibake) các ký tự tiếng Việt nếu code dùng resp.body thay vì
    // utf8.decode(resp.bodyBytes). Đây là cách duy nhất để test này thực sự
    // "falsifying" được lỗi cũ, vì content-type 'application/json' không kèm
    // charset đã được gói http (>=1.1) tự suy ra là UTF-8, khiến test pass
    // ngay cả với code cũ (resp.body).
    final client = MockClient(
      (req) async => http.Response.bytes(utf8.encode(geminiPayload), 200),
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

  test(
    'phản hồi 200 với candidates[0] không phải Map → ném Exception (không phải Error)',
    () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'candidates': [42],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final analyzer = GeminiSceneAnalyzer(apiKey: 'k', client: client);
      expect(
        () => analyzer.analyze(jpegBytes: _fakeJpeg(), filePath: 'x.jpg'),
        throwsA(isA<Exception>()),
      );
    },
  );
}
