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

    // JSON luôn là UTF-8 (RFC 8259); ép giải mã thủ công để tránh resp.body
    // suy ra sai charset (vd. Latin-1) và làm hỏng tiếng Việt.
    final decoded =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

    // Kiểm tra hình dạng phản hồi trước khi truy cập sâu, để ném Exception
    // (không phải Error) khi Gemini trả về thiếu/rỗng candidates (vd. bị
    // chặn vì lý do an toàn).
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw Exception('Gemini không trả về kết quả (có thể ảnh bị chặn).');
    }
    final parts = candidates[0]?['content']?['parts'];
    if (parts is! List || parts.isEmpty || parts[0]?['text'] is! String) {
      throw Exception('Gemini trả về định dạng không hợp lệ.');
    }
    final text = parts[0]['text'] as String;
    final inner = jsonDecode(text) as Map<String, dynamic>;
    return parseGeminiJson(
      inner,
      validIds: [for (final p in presets) p.id],
      fromCloud: true,
    );
  }
}
