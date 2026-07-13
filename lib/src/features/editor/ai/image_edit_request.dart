import 'dart:convert';
import 'dart:typed_data';

/// Dựng body cho `generateContent` của model chỉnh ảnh Gemini.
///
/// Khác analyzer: KHÔNG có `responseSchema`/`responseMimeType` — model ảnh trả
/// về phần `inlineData` (ảnh) chứ không phải JSON theo schema.
Map<String, dynamic> buildImageEditRequestBody({
  required String base64Image,
  required String prompt,
}) {
  return {
    'contents': [
      {
        'parts': [
          {'text': prompt},
          {
            'inline_data': {
              'mime_type': 'image/jpeg',
              'data': base64Image,
            },
          },
        ],
      },
    ],
  };
}

/// Bóc bytes ảnh đã chỉnh từ phản hồi Gemini.
///
/// REST v1beta trả `inlineData` (camelCase) trong response; vẫn chấp nhận
/// `inline_data` (snake_case) cho chắc. Ném [Exception] khi thiếu phần ảnh
/// (vd. ảnh bị chặn an toàn → chỉ có part text).
Uint8List parseEditedImage(Map<String, dynamic> json) {
  final candidates = json['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    throw Exception('Gemini không trả về ảnh (có thể bị chặn).');
  }
  final candidate0 = candidates.first;
  if (candidate0 is! Map) {
    throw Exception('Gemini trả về định dạng không hợp lệ.');
  }
  final content = candidate0['content'];
  if (content is! Map) {
    throw Exception('Gemini trả về định dạng không hợp lệ.');
  }
  final parts = content['parts'];
  if (parts is! List) {
    throw Exception('Gemini trả về định dạng không hợp lệ.');
  }
  for (final part in parts) {
    if (part is! Map) continue;
    final inline = part['inlineData'] ?? part['inline_data'];
    if (inline is Map && inline['data'] is String) {
      return base64Decode(inline['data'] as String);
    }
  }
  throw Exception('Gemini không trả về ảnh (có thể bị chặn).');
}
