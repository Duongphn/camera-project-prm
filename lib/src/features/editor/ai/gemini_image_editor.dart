import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../analysis/gemini_request.dart' show downscaleForVision;
import '../../analysis/scene_analyzer.dart' show MissingApiKeyException;
import 'image_edit_request.dart';

/// Gọi model chỉnh ảnh Gemini qua REST, trả về JPEG/PNG bytes đã chỉnh.
///
/// Không có fallback on-device: tạo sinh ảnh chỉ chạy được khi online + có key.
class GeminiImageEditor {
  GeminiImageEditor({
    http.Client? client,
    this.apiKey = const String.fromEnvironment('GEMINI_API_KEY'),
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String apiKey;
  final Duration timeout;

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent';

  Future<Uint8List> editImage({
    required Uint8List jpegBytes,
    required String prompt,
  }) async {
    if (apiKey.isEmpty) throw MissingApiKeyException();

    final small = downscaleForVision(jpegBytes, maxEdge: 1024, quality: 90);
    final body = buildImageEditRequestBody(
      base64Image: base64Encode(small),
      prompt: prompt,
    );

    final resp = await _client
        .post(
          Uri.parse('$_endpoint?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (resp.statusCode != 200) {
      throw Exception('Gemini HTTP ${resp.statusCode}: ${resp.body}');
    }

    final decoded =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return parseEditedImage(decoded);
  }
}
