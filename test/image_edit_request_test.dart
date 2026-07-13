import 'dart:convert';

import 'package:doka_app/src/features/editor/ai/image_edit_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('request body có prompt + ảnh inline, KHÔNG có responseSchema', () {
    final body = buildImageEditRequestBody(base64Image: 'AAAA', prompt: 'remove background');
    final parts = (body['contents'] as List).first['parts'] as List;
    expect(parts[0]['text'], 'remove background');
    expect(parts[1]['inline_data']['mime_type'], 'image/jpeg');
    expect(parts[1]['inline_data']['data'], 'AAAA');
    expect(body.containsKey('generationConfig'), isFalse);
  });

  test('parse ảnh từ inlineData (camelCase) → đúng bytes', () {
    final json = {
      'candidates': [
        {
          'content': {
            'parts': [
              {'inlineData': {'mimeType': 'image/png', 'data': base64Encode([1, 2, 3])}},
            ],
          },
        },
      ],
    };
    expect(parseEditedImage(json), [1, 2, 3]);
  });

  test('parse ảnh từ inline_data (snake_case) → đúng bytes', () {
    final json = {
      'candidates': [
        {
          'content': {
            'parts': [
              {'inline_data': {'mime_type': 'image/png', 'data': base64Encode([9, 8, 7])}},
            ],
          },
        },
      ],
    };
    expect(parseEditedImage(json), [9, 8, 7]);
  });

  test('bỏ qua part text, lấy đúng part ảnh', () {
    final json = {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'Here is your image'},
              {'inlineData': {'mimeType': 'image/png', 'data': base64Encode([5])}},
            ],
          },
        },
      ],
    };
    expect(parseEditedImage(json), [5]);
  });

  test('candidates rỗng → ném Exception', () {
    expect(() => parseEditedImage({'candidates': []}), throwsA(isA<Exception>()));
  });

  test('không có part ảnh (chỉ text) → ném Exception', () {
    final json = {
      'candidates': [
        {'content': {'parts': [{'text': 'blocked'}]}},
      ],
    };
    expect(() => parseEditedImage(json), throwsA(isA<Exception>()));
  });
}
