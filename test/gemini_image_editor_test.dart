import 'dart:async';
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

/// Backoff không chờ, để test retry chạy tức thì.
Future<void> _noWait(int attempt) async {}

/// Payload 200 hợp lệ có phần ảnh inline.
String _imagePayload() => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'inlineData': {
                  'mimeType': 'image/png',
                  'data': base64Encode([1, 2, 3]),
                },
              },
            ],
          },
        },
      ],
    });

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

  test('500 liên tục → ném Exception sau khi hết retry', () {
    final client = MockClient((req) async => http.Response('boom', 500));
    final editor = GeminiImageEditor(apiKey: 'k', client: client, backoff: _noWait);
    expect(
      () => editor.editImage(jpegBytes: _fakeJpeg(), prompt: 'x'),
      throwsA(isA<Exception>()),
    );
  });

  test('500 lần đầu rồi 200 → retry và trả bytes ảnh', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      if (calls == 1) return http.Response('boom', 500);
      return http.Response.bytes(utf8.encode(_imagePayload()), 200);
    });
    final editor = GeminiImageEditor(apiKey: 'k', client: client, backoff: _noWait);
    final out = await editor.editImage(jpegBytes: _fakeJpeg(), prompt: 'x');
    expect(out, [1, 2, 3]);
    expect(calls, 2);
  });

  test('503 liên tục → thử đúng maxAttempts lần rồi ném', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response('overloaded', 503);
    });
    final editor = GeminiImageEditor(
      apiKey: 'k',
      client: client,
      backoff: _noWait,
      maxAttempts: 3,
    );
    await expectLater(
      editor.editImage(jpegBytes: _fakeJpeg(), prompt: 'x'),
      throwsA(isA<Exception>()),
    );
    expect(calls, 3);
  });

  test('timeout lần đầu rồi 200 → retry và trả bytes ảnh', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      if (calls == 1) throw TimeoutException('slow');
      return http.Response.bytes(utf8.encode(_imagePayload()), 200);
    });
    final editor = GeminiImageEditor(apiKey: 'k', client: client, backoff: _noWait);
    final out = await editor.editImage(jpegBytes: _fakeJpeg(), prompt: 'x');
    expect(out, [1, 2, 3]);
    expect(calls, 2);
  });

  test('400 (không retriable) → ném ngay, không thử lại', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response('bad request', 400);
    });
    final editor = GeminiImageEditor(apiKey: 'k', client: client, backoff: _noWait);
    await expectLater(
      editor.editImage(jpegBytes: _fakeJpeg(), prompt: 'x'),
      throwsA(isA<Exception>()),
    );
    expect(calls, 1);
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
