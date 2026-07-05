import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../filters/film_preset.dart';
import 'gemini_prompt.dart';
import 'gemini_request.dart';
import 'scene_analysis.dart';

/// Phân tích một ảnh tĩnh. Ném lỗi nếu không phân tích được (mạng/timeout/
/// thiếu key); phía gọi bắt lỗi để rơi về fallback on-device.
abstract interface class SceneAnalyzer {
  Future<SceneAnalysis> analyze({
    required Uint8List jpegBytes,
    required String filePath,
  });
}

/// Thiếu GEMINI_API_KEY (chưa truyền --dart-define).
class MissingApiKeyException implements Exception {
  @override
  String toString() => 'MissingApiKeyException: chưa cấu hình GEMINI_API_KEY';
}

/// Gọi Gemini 2.5 Flash qua REST.
class GeminiSceneAnalyzer implements SceneAnalyzer {
  GeminiSceneAnalyzer({
    http.Client? client,
    this.apiKey = const String.fromEnvironment('GEMINI_API_KEY'),
    this.presets = filmPresets,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String apiKey;
  final List<FilmPreset> presets;
  final Duration timeout;

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  @override
  Future<SceneAnalysis> analyze({
    required Uint8List jpegBytes,
    required String filePath,
  }) async {
    if (apiKey.isEmpty) throw MissingApiKeyException();

    final small = downscaleForVision(jpegBytes);
    final body = buildGeminiRequestBody(
      base64Image: base64Encode(small),
      promptText: buildScenePrompt(presets),
      schema: sceneResponseSchema,
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

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final text = decoded['candidates'][0]['content']['parts'][0]['text']
        as String;
    final inner = jsonDecode(text) as Map<String, dynamic>;
    return parseGeminiJson(
      inner,
      validIds: [for (final p in presets) p.id],
      fromCloud: true,
    );
  }
}
