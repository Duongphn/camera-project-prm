import 'dart:convert';
import 'dart:typed_data';

import 'package:doka_app/src/features/analysis/scene_analyzer.dart' show MissingApiKeyException;
import 'package:doka_app/src/features/editor/ai/gemini_image_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

Uint8List _fakeJpeg() =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: 100, height: 100)));

void main() {
  test('thiếu API key → ném MissingApiKeyException', () {
    final editor = GeminiImageEditor(apiKey: '');
    expect(
      () => editor.editImage(jpegBytes: _fakeJpeg(), prompt: 'x'),
      throwsA(isA<MissingApiKeyException>()),
    );
  });

  test('200 hợp lệ có inlineData → trả bytes ảnh', () async {
    final payload = jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'inlineData': {'mimeType': 'image/png', 'data': base64Encode([1, 2, 3])}},
            ],
          },
        },
      ],
    });
    final client = MockClient((req) async => http.Response.bytes(utf8.encode(payload), 200));
    final editor = GeminiImageEditor(apiKey: 'k', client: client);
    final out = await editor.editImage(jpegBytes: _fakeJpeg(), prompt: 'x');
    expect(out, [1, 2, 3]);
  });

  test('HTTP 500 → ném Exception', () {
    final client = MockClient((req) async => http.Response('boom', 500));
    final editor = GeminiImageEditor(apiKey: 'k', client: client);
    expect(
      () => editor.editImage(jpegBytes: _fakeJpeg(), prompt: 'x'),
      throwsA(isA<Exception>()),
    );
  });

  test('200 nhưng candidates rỗng → ném Exception', () {
    final client = MockClient(
      (req) async => http.Response.bytes(utf8.encode(jsonEncode({'candidates': []})), 200),
    );
    final editor = GeminiImageEditor(apiKey: 'k', client: client);
    expect(
      () => editor.editImage(jpegBytes: _fakeJpeg(), prompt: 'x'),
      throwsA(isA<Exception>()),
    );
  });
}
