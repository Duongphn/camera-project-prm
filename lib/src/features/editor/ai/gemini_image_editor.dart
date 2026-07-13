import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../analysis/gemini_request.dart' show downscaleForVision;
import '../../analysis/scene_analyzer.dart' show MissingApiKeyException;
import 'image_edit_request.dart';

/// Chờ giữa các lần thử lại (exponential backoff): ~1s, 2s, 4s...
Future<void> _defaultBackoff(int attempt) =>
    Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));

/// Gọi model chỉnh ảnh Gemini qua REST, trả về JPEG/PNG bytes đã chỉnh.
///
/// Không có fallback on-device: tạo sinh ảnh chỉ chạy được khi online + có key.
///
/// Endpoint sinh ảnh của Gemini hay trả lỗi *tạm thời* (429/500/502/503/504)
/// khi quá tải, và bản thân việc tạo sinh ảnh khá chậm → dễ timeout. Vì vậy
/// editor tự động thử lại các lỗi tạm thời + timeout với backoff luỹ thừa
/// thay vì ném lỗi ngay lần đầu.
class GeminiImageEditor {
  GeminiImageEditor({
    http.Client? client,
    this.apiKey = const String.fromEnvironment('GEMINI_API_KEY'),
    this.timeout = const Duration(seconds: 60),
    this.maxAttempts = 3,
    Future<void> Function(int attempt)? backoff,
  })  : _client = client ?? http.Client(),
        _backoff = backoff ?? _defaultBackoff;

  final http.Client _client;
  final String apiKey;

  /// Timeout cho MỖI lần gọi (không phải tổng). Tạo sinh ảnh chậm nên để rộng.
  final Duration timeout;

  /// Tổng số lần thử (gồm lần đầu). >=1.
  final int maxAttempts;

  /// Hàm chờ giữa các lần thử; tách ra để test chạy tức thì.
  final Future<void> Function(int attempt) _backoff;

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent';

  /// HTTP status đáng thử lại (lỗi phía server / rate limit, thường thoáng qua).
  static bool _isRetriableStatus(int code) =>
      code == 429 || code == 500 || code == 502 || code == 503 || code == 504;

  Future<Uint8List> editImage({
    required Uint8List jpegBytes,
    required String prompt,
  }) async {
    if (apiKey.isEmpty) throw MissingApiKeyException();

    // Giữ độ phân giải ~1024 (khớp output Gemini) nhưng hạ quality để giảm
    // payload → upload nhanh hơn, ít chạm timeout hơn.
    final small = downscaleForVision(jpegBytes, maxEdge: 1024, quality: 85);
    final payload = jsonEncode(
      buildImageEditRequestBody(
        base64Image: base64Encode(small),
        prompt: prompt,
      ),
    );
    final uri = Uri.parse('$_endpoint?key=$apiKey');

    Object lastError = Exception('Gemini edit thất bại.');
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) await _backoff(attempt);
      final bool isLast = attempt == maxAttempts - 1;
      try {
        final resp = await _client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: payload,
            )
            .timeout(timeout);

        if (resp.statusCode == 200) {
          final decoded =
              jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
          // Lỗi parse (vd. ảnh bị chặn an toàn) KHÔNG thử lại — thử lại vô ích.
          return parseEditedImage(decoded);
        }

        lastError = Exception('Gemini HTTP ${resp.statusCode}: ${resp.body}');
        if (isLast || !_isRetriableStatus(resp.statusCode)) throw lastError;
      } on TimeoutException {
        lastError = Exception(
          'Gemini quá thời gian chờ (${timeout.inSeconds}s) sau '
          '${attempt + 1} lần thử.',
        );
        if (isLast) throw lastError;
      }
    }
    throw lastError;
  }
}
