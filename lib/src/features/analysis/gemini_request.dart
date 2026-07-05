import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Thu nhỏ ảnh (cạnh dài về [maxEdge]) và nén JPEG để giảm chi phí/độ trễ.
/// Ảnh vốn đã nhỏ hơn [maxEdge] thì giữ nguyên kích thước.
Uint8List downscaleForVision(
  Uint8List jpegBytes, {
  int maxEdge = 768,
  int quality = 85,
}) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) return jpegBytes;
  final longEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (longEdge <= maxEdge) {
    return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  }
  final resized = decoded.width >= decoded.height
      ? img.copyResize(decoded, width: maxEdge)
      : img.copyResize(decoded, height: maxEdge);
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}

/// Dựng body cho `generateContent` của Gemini: prompt + ảnh inline + schema.
Map<String, dynamic> buildGeminiRequestBody({
  required String base64Image,
  required String promptText,
  required Map<String, dynamic> schema,
}) {
  return {
    'contents': [
      {
        'parts': [
          {'text': promptText},
          {
            'inline_data': {
              'mime_type': 'image/jpeg',
              'data': base64Image,
            },
          },
        ],
      },
    ],
    'generationConfig': {
      'responseMimeType': 'application/json',
      'responseSchema': schema,
    },
  };
}
