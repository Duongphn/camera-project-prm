# Gemini Vision Scene Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm phân tích ảnh bằng Google Gemini Vision để gợi ý filter chính xác hơn và chốt điểm bố cục "đẹp nhất" một lần, giữ nguyên dẫn hướng realtime và fallback offline.

**Architecture:** Một lớp `SceneAnalyzer` (interface) đứng trước app. `GeminiSceneAnalyzer` gọi REST Gemini 2.5 Flash trên 1 ảnh tĩnh, trả `SceneAnalysis` có cấu trúc. Khi lỗi/offline/thiếu key, phía gọi rơi về đường on-device sẵn có (`FilterSuggester` cho filter, `adviseComposition` hình học cho bố cục). Realtime tracking (ML Kit) và dẫn hướng giữ nguyên; chỉ điểm đích `_fixedTarget` được thay bằng điểm Gemini chốt 1 lần.

**Tech Stack:** Flutter, Dart, Riverpod, package `http` (REST), package `image` (resize), Google ML Kit (fallback), Google Gemini `gemini-2.5-flash`.

## Global Constraints

- Flutter SDK: `^3.11.5` (không hạ).
- Mọi comment và chuỗi hiển thị cho người dùng: **tiếng Việt**.
- `presetId` chỉ được là id có thật trong `filmPresets` (`lib/src/features/filters/film_preset.dart`); id lạ → kẹp về `'original'`.
- Model Gemini: `gemini-2.5-flash`, endpoint `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent`.
- API key đọc qua `const String.fromEnvironment('GEMINI_API_KEY')`. **Không** hardcode, **không** commit key.
- Fallback on-device phải luôn hoạt động khi không có mạng/key.
- Timeout gọi Gemini: 8 giây.
- `targetPoint` là `Offset` trong không gian viewfinder 0..1, gốc (0,0) ở góc trên-trái.
- TDD: mỗi task viết test trước (với phần thuần/inject được); phần UI camera chỉ verify thủ công trên máy thật.

---

### Task 1: Dependency `http` + model `SceneAnalysis`

**Files:**
- Modify: `pubspec.yaml` (thêm `http`)
- Create: `lib/src/features/analysis/scene_analysis.dart`
- Test: `test/scene_analysis_test.dart`

**Interfaces:**
- Produces: `class SceneAnalysis` với các trường `String presetId`, `String? reason`, `String? mood`, `Offset? targetPoint`, `List<String> tips`, `bool fromCloud`; constructor `const SceneAnalysis({required this.presetId, this.reason, this.mood, this.targetPoint, this.tips = const [], this.fromCloud = false})`.

- [ ] **Step 1: Thêm dependency**

Trong `pubspec.yaml`, dưới `google_mlkit_object_detection: ^0.15.1` thêm:

```yaml
  http: ^1.2.0
```

- [ ] **Step 2: Cài dependency**

Run: `flutter pub get`
Expected: kết thúc "Got dependencies" không lỗi.

- [ ] **Step 3: Viết test thất bại**

Tạo `test/scene_analysis_test.dart`:

```dart
import 'dart:ui';

import 'package:doka_app/src/features/analysis/scene_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mặc định: tips rỗng, fromCloud=false, các field optional null', () {
    const a = SceneAnalysis(presetId: 'dalat');
    expect(a.presetId, 'dalat');
    expect(a.tips, isEmpty);
    expect(a.fromCloud, isFalse);
    expect(a.reason, isNull);
    expect(a.targetPoint, isNull);
  });

  test('giữ nguyên giá trị truyền vào', () {
    const a = SceneAnalysis(
      presetId: 'kem',
      reason: 'da mịn',
      mood: 'ấm',
      targetPoint: Offset(0.66, 0.33),
      tips: ['hạ máy'],
      fromCloud: true,
    );
    expect(a.targetPoint, const Offset(0.66, 0.33));
    expect(a.tips.single, 'hạ máy');
    expect(a.fromCloud, isTrue);
  });
}
```

- [ ] **Step 4: Chạy test để chắc chắn fail**

Run: `flutter test test/scene_analysis_test.dart`
Expected: FAIL — không tìm thấy `scene_analysis.dart` / `SceneAnalysis`.

- [ ] **Step 5: Viết model**

Tạo `lib/src/features/analysis/scene_analysis.dart`:

```dart
import 'dart:ui';

/// Kết quả phân tích một ảnh tĩnh (từ Gemini hoặc fallback on-device).
class SceneAnalysis {
  const SceneAnalysis({
    required this.presetId,
    this.reason,
    this.mood,
    this.targetPoint,
    this.tips = const [],
    this.fromCloud = false,
  });

  /// Id filter được chọn — luôn là id hợp lệ trong filmPresets.
  final String presetId;

  /// Vì sao chọn preset này (hiển thị cho người dùng).
  final String? reason;

  /// Mô tả ánh sáng/tông màu/bối cảnh.
  final String? mood;

  /// Điểm đặt chủ thể đẹp nhất, 0..1 viewfinder (gốc trên-trái). Có thể null.
  final Offset? targetPoint;

  /// Mẹo bố cục ngắn (tối đa 3).
  final List<String> tips;

  /// true = từ Gemini; false = fallback on-device.
  final bool fromCloud;
}
```

- [ ] **Step 6: Chạy test để chắc chắn pass**

Run: `flutter test test/scene_analysis_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/src/features/analysis/scene_analysis.dart test/scene_analysis_test.dart
git commit -m "feat: them model SceneAnalysis va dependency http"
```

---

### Task 2: Prompt catalog, response schema, `parseGeminiJson` (thuần)

**Files:**
- Create: `lib/src/features/analysis/gemini_prompt.dart`
- Test: `test/gemini_prompt_test.dart`

**Interfaces:**
- Consumes: `SceneAnalysis` (Task 1); `filmPresets`, `FilmPreset` từ `lib/src/features/filters/film_preset.dart`.
- Produces:
  - `String buildScenePrompt(List<FilmPreset> presets)`
  - `Map<String, dynamic> sceneResponseSchema` (hằng)
  - `SceneAnalysis parseGeminiJson(Map<String, dynamic> json, {required List<String> validIds, bool fromCloud = true})`

- [ ] **Step 1: Viết test thất bại**

Tạo `test/gemini_prompt_test.dart`:

```dart
import 'dart:ui';

import 'package:doka_app/src/features/analysis/gemini_prompt.dart';
import 'package:doka_app/src/features/filters/film_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ids = [
    'original', 'saigon89', 'dalat', 'halong', 'chodem',
    'mono400', 'noir', 'retro76', 'xanhreu', 'kem',
  ];

  test('prompt liệt kê mọi id preset', () {
    final prompt = buildScenePrompt(filmPresets);
    for (final p in filmPresets) {
      expect(prompt.contains(p.id), isTrue, reason: 'thiếu ${p.id}');
    }
  });

  test('parse JSON hợp lệ thành SceneAnalysis', () {
    final a = parseGeminiJson({
      'presetId': 'kem',
      'reason': 'da mịn, sáng nhẹ',
      'mood': 'chân dung ấm',
      'targetX': 0.66,
      'targetY': 0.33,
      'tips': ['hạ máy lấy nhiều trời', 'chỉnh ngang chân trời'],
    }, validIds: ids);
    expect(a.presetId, 'kem');
    expect(a.reason, 'da mịn, sáng nhẹ');
    expect(a.targetPoint, const Offset(0.66, 0.33));
    expect(a.tips.length, 2);
    expect(a.fromCloud, isTrue);
  });

  test('presetId lạ bị kẹp về original', () {
    final a = parseGeminiJson({'presetId': 'khong-ton-tai'}, validIds: ids);
    expect(a.presetId, 'original');
  });

  test('thiếu toạ độ → targetPoint null', () {
    final a = parseGeminiJson({'presetId': 'dalat'}, validIds: ids);
    expect(a.targetPoint, isNull);
  });

  test('toạ độ ngoài [0,1] bị loại', () {
    final a = parseGeminiJson(
      {'presetId': 'dalat', 'targetX': 1.5, 'targetY': 0.2},
      validIds: ids,
    );
    expect(a.targetPoint, isNull);
  });

  test('tips cắt còn tối đa 3 và bỏ chuỗi rỗng', () {
    final a = parseGeminiJson({
      'presetId': 'dalat',
      'tips': ['a', '', 'b', 'c', 'd'],
    }, validIds: ids);
    expect(a.tips, ['a', 'b', 'c']);
  });
}
```

- [ ] **Step 2: Chạy test để chắc chắn fail**

Run: `flutter test test/gemini_prompt_test.dart`
Expected: FAIL — không tìm thấy `gemini_prompt.dart`.

- [ ] **Step 3: Viết implementation**

Tạo `lib/src/features/analysis/gemini_prompt.dart`:

```dart
import 'dart:ui';

import '../filters/film_preset.dart';
import 'scene_analysis.dart';

/// Schema JSON buộc Gemini trả đúng cấu trúc.
const Map<String, dynamic> sceneResponseSchema = {
  'type': 'OBJECT',
  'properties': {
    'presetId': {'type': 'STRING'},
    'reason': {'type': 'STRING'},
    'mood': {'type': 'STRING'},
    'targetX': {'type': 'NUMBER'},
    'targetY': {'type': 'NUMBER'},
    'tips': {
      'type': 'ARRAY',
      'items': {'type': 'STRING'},
    },
  },
  'required': ['presetId'],
};

/// Prompt yêu cầu Gemini phân tích ảnh và chọn preset + điểm bố cục.
String buildScenePrompt(List<FilmPreset> presets) {
  final catalog = presets.map((p) => '- ${p.id}: ${p.name}').join('\n');
  return '''
Bạn là chuyên gia nhiếp ảnh phim. Phân tích bức ảnh và trả về JSON.

Chọn ĐÚNG MỘT presetId phù hợp nhất trong danh mục dưới đây (chỉ dùng id có trong danh sách):
$catalog

Trả về các trường:
- presetId: id filter hợp nhất với ánh sáng và tông màu của ảnh.
- reason: vì sao chọn (tiếng Việt, tối đa 15 từ).
- mood: mô tả ngắn ánh sáng/tông màu/bối cảnh (tiếng Việt).
- targetX, targetY: vị trí ĐẶT CHỦ THỂ đẹp nhất theo bố cục, số thực 0..1 (gốc 0,0 ở góc trên-trái).
- tips: tối đa 3 mẹo bố cục ngắn gọn bằng tiếng Việt.
''';
}

/// Parse JSON trả về (đã decode) thành SceneAnalysis. Thuần, không mạng.
SceneAnalysis parseGeminiJson(
  Map<String, dynamic> json, {
  required List<String> validIds,
  bool fromCloud = true,
}) {
  final rawId = (json['presetId'] as String?)?.trim() ?? '';
  final presetId = validIds.contains(rawId) ? rawId : 'original';

  Offset? target;
  final tx = (json['targetX'] as num?)?.toDouble();
  final ty = (json['targetY'] as num?)?.toDouble();
  if (tx != null && ty != null && tx >= 0 && tx <= 1 && ty >= 0 && ty <= 1) {
    target = Offset(tx, ty);
  }

  final tips = <String>[];
  final rawTips = json['tips'];
  if (rawTips is List) {
    for (final t in rawTips) {
      if (t is String && t.trim().isNotEmpty) tips.add(t.trim());
      if (tips.length == 3) break;
    }
  }

  return SceneAnalysis(
    presetId: presetId,
    reason: (json['reason'] as String?)?.trim(),
    mood: (json['mood'] as String?)?.trim(),
    targetPoint: target,
    tips: tips,
    fromCloud: fromCloud,
  );
}
```

- [ ] **Step 4: Chạy test để chắc chắn pass**

Run: `flutter test test/gemini_prompt_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/analysis/gemini_prompt.dart test/gemini_prompt_test.dart
git commit -m "feat: prompt catalog, response schema va parseGeminiJson"
```

---

### Task 3: Downscale ảnh + builder request body (thuần)

**Files:**
- Create: `lib/src/features/analysis/gemini_request.dart`
- Test: `test/gemini_request_test.dart`

**Interfaces:**
- Consumes: package `image`.
- Produces:
  - `Uint8List downscaleForVision(Uint8List jpegBytes, {int maxEdge = 768, int quality = 85})`
  - `Map<String, dynamic> buildGeminiRequestBody({required String base64Image, required String promptText, required Map<String, dynamic> schema})`

- [ ] **Step 1: Viết test thất bại**

Tạo `test/gemini_request_test.dart`:

```dart
import 'dart:typed_data';

import 'package:doka_app/src/features/analysis/gemini_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('downscale đưa cạnh dài về <= maxEdge', () {
    final src = img.Image(width: 1600, height: 900);
    final jpeg = Uint8List.fromList(img.encodeJpg(src));
    final out = downscaleForVision(jpeg, maxEdge: 768);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, lessThanOrEqualTo(768));
    expect(decoded.height, lessThanOrEqualTo(768));
    expect(decoded.width, greaterThan(decoded.height)); // giữ tỉ lệ
  });

  test('ảnh nhỏ hơn maxEdge không bị phóng to', () {
    final src = img.Image(width: 320, height: 240);
    final jpeg = Uint8List.fromList(img.encodeJpg(src));
    final out = downscaleForVision(jpeg, maxEdge: 768);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 320);
    expect(decoded.height, 240);
  });

  test('request body có prompt, ảnh inline và schema', () {
    final body = buildGeminiRequestBody(
      base64Image: 'AAAA',
      promptText: 'phân tích',
      schema: const {'type': 'OBJECT'},
    );
    final parts = (body['contents'] as List).first['parts'] as List;
    expect(parts[0]['text'], 'phân tích');
    expect(parts[1]['inline_data']['mime_type'], 'image/jpeg');
    expect(parts[1]['inline_data']['data'], 'AAAA');
    expect(body['generationConfig']['responseMimeType'], 'application/json');
    expect(body['generationConfig']['responseSchema'], const {'type': 'OBJECT'});
  });
}
```

- [ ] **Step 2: Chạy test để chắc chắn fail**

Run: `flutter test test/gemini_request_test.dart`
Expected: FAIL — không tìm thấy `gemini_request.dart`.

- [ ] **Step 3: Viết implementation**

Tạo `lib/src/features/analysis/gemini_request.dart`:

```dart
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
```

- [ ] **Step 4: Chạy test để chắc chắn pass**

Run: `flutter test test/gemini_request_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/analysis/gemini_request.dart test/gemini_request_test.dart
git commit -m "feat: downscale anh va builder request body cho Gemini"
```

---

### Task 4: `SceneAnalyzer` interface + `GeminiSceneAnalyzer`

**Files:**
- Create: `lib/src/features/analysis/scene_analyzer.dart`
- Test: `test/gemini_scene_analyzer_test.dart`

**Interfaces:**
- Consumes: `SceneAnalysis`, `buildScenePrompt`, `sceneResponseSchema`, `parseGeminiJson` (Task 2), `downscaleForVision`, `buildGeminiRequestBody` (Task 3), `filmPresets`, package `http`.
- Produces:
  - `abstract interface class SceneAnalyzer` với `Future<SceneAnalysis> analyze({required Uint8List jpegBytes, required String filePath})`.
  - `class MissingApiKeyException implements Exception`.
  - `class GeminiSceneAnalyzer implements SceneAnalyzer` với constructor `GeminiSceneAnalyzer({http.Client? client, String apiKey = const String.fromEnvironment('GEMINI_API_KEY'), List<FilmPreset> presets = filmPresets})`.

- [ ] **Step 1: Viết test thất bại**

Tạo `test/gemini_scene_analyzer_test.dart`:

```dart
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

  test('phản hồi 200 hợp lệ → SceneAnalysis từ cloud', () async {
    final geminiPayload = jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text': jsonEncode({
                  'presetId': 'kem',
                  'reason': 'chân dung ấm',
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
    final client = MockClient((req) async => http.Response(geminiPayload, 200));
    final analyzer = GeminiSceneAnalyzer(apiKey: 'k', client: client);

    final a = await analyzer.analyze(jpegBytes: _fakeJpeg(), filePath: 'x.jpg');
    expect(a.presetId, 'kem');
    expect(a.fromCloud, isTrue);
    expect(a.targetPoint!.dx, closeTo(0.66, 1e-9));
    expect(a.tips.single, 'hạ máy');
  });

  test('HTTP lỗi (500) → ném lỗi để phía gọi fallback', () async {
    final client = MockClient((req) async => http.Response('boom', 500));
    final analyzer = GeminiSceneAnalyzer(apiKey: 'k', client: client);
    expect(
      () => analyzer.analyze(jpegBytes: _fakeJpeg(), filePath: 'x.jpg'),
      throwsA(isA<Exception>()),
    );
  });
}
```

- [ ] **Step 2: Chạy test để chắc chắn fail**

Run: `flutter test test/gemini_scene_analyzer_test.dart`
Expected: FAIL — không tìm thấy `scene_analyzer.dart`.

- [ ] **Step 3: Viết implementation**

Tạo `lib/src/features/analysis/scene_analyzer.dart`:

```dart
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
```

- [ ] **Step 4: Chạy test để chắc chắn pass**

Run: `flutter test test/gemini_scene_analyzer_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/analysis/scene_analyzer.dart test/gemini_scene_analyzer_test.dart
git commit -m "feat: GeminiSceneAnalyzer goi Gemini 2.5 Flash qua REST"
```

---

### Task 5: `OfflineSceneAnalyzer` + providers

**Files:**
- Modify: `lib/src/features/analysis/scene_analyzer.dart` (thêm `sceneFromPreset` + `OfflineSceneAnalyzer`)
- Modify: `lib/src/providers.dart`
- Test: `test/offline_scene_analyzer_test.dart`

**Interfaces:**
- Consumes: `FilterSuggester` (`lib/src/features/suggestion/filter_suggester.dart`), `FilmPreset`, `SceneAnalysis`, `SceneAnalyzer`.
- Produces:
  - `SceneAnalysis sceneFromPreset(FilmPreset preset)` (thuần, `fromCloud=false`, `targetPoint=null`).
  - `class OfflineSceneAnalyzer implements SceneAnalyzer`.
  - Providers: `sceneAnalyzerProvider` (Gemini), `offlineAnalyzerProvider` (Offline).

- [ ] **Step 1: Viết test thất bại**

Tạo `test/offline_scene_analyzer_test.dart`:

```dart
import 'package:doka_app/src/features/analysis/scene_analyzer.dart';
import 'package:doka_app/src/features/filters/film_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sceneFromPreset map preset → SceneAnalysis on-device', () {
    final preset = filmPresets.firstWhere((p) => p.id == 'dalat');
    final a = sceneFromPreset(preset);
    expect(a.presetId, 'dalat');
    expect(a.fromCloud, isFalse);
    expect(a.targetPoint, isNull);
    expect(a.reason, contains(preset.name));
  });
}
```

- [ ] **Step 2: Chạy test để chắc chắn fail**

Run: `flutter test test/offline_scene_analyzer_test.dart`
Expected: FAIL — không tìm thấy `sceneFromPreset`.

- [ ] **Step 3: Thêm `sceneFromPreset` + `OfflineSceneAnalyzer`**

Cuối `lib/src/features/analysis/scene_analyzer.dart`, thêm import và code:

```dart
// thêm vào phần import đầu file:
// import '../suggestion/filter_suggester.dart';

/// Map một preset đã chọn on-device thành SceneAnalysis (không có targetPoint).
SceneAnalysis sceneFromPreset(FilmPreset preset) => SceneAnalysis(
      presetId: preset.id,
      reason: 'Ngoại tuyến: ${preset.name}',
      fromCloud: false,
    );

/// Fallback on-device cho luồng filter (ML Kit label + độ sáng).
/// Không trả targetPoint — bố cục offline dùng hình học ngay tại camera_screen.
class OfflineSceneAnalyzer implements SceneAnalyzer {
  const OfflineSceneAnalyzer();

  @override
  Future<SceneAnalysis> analyze({
    required Uint8List jpegBytes,
    required String filePath,
  }) async {
    final preset =
        await FilterSuggester.suggest(filePath: filePath, bytes: jpegBytes);
    return sceneFromPreset(preset);
  }
}
```

Thêm `import '../suggestion/filter_suggester.dart';` vào khối import đầu file.

- [ ] **Step 4: Chạy test để chắc chắn pass**

Run: `flutter test test/offline_scene_analyzer_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Thêm providers**

Sửa `lib/src/providers.dart` thành:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/analysis/scene_analyzer.dart';
import 'features/gallery/photo_repository.dart';

final photoRepositoryProvider =
    Provider<PhotoRepository>((ref) => PhotoRepository());

/// Phân tích ảnh bằng Gemini (đường chính).
final sceneAnalyzerProvider =
    Provider<SceneAnalyzer>((ref) => GeminiSceneAnalyzer());

/// Fallback on-device khi Gemini lỗi/offline/thiếu key.
final offlineAnalyzerProvider =
    Provider<SceneAnalyzer>((ref) => const OfflineSceneAnalyzer());
```

- [ ] **Step 6: Chạy toàn bộ test + phân tích tĩnh**

Run: `flutter test && flutter analyze`
Expected: tất cả test PASS; `flutter analyze` không lỗi.

- [ ] **Step 7: Commit**

```bash
git add lib/src/features/analysis/scene_analyzer.dart lib/src/providers.dart test/offline_scene_analyzer_test.dart
git commit -m "feat: OfflineSceneAnalyzer fallback va providers phan tich anh"
```

---

### Task 6: Nối Gemini vào gợi ý filter

**Files:**
- Modify: `lib/src/features/camera/camera_screen.dart:196-223` (`_suggestFilter`)

**Interfaces:**
- Consumes: `sceneAnalyzerProvider`, `offlineAnalyzerProvider`, `SceneAnalysis` (Task 5); các hàm/biến sẵn có `_pauseCompositionStream`, `_resumeCompositionStream`, `filmPresets`, `_presetIndex`, `_showMessage`, `_suggesting`, `ref`.

- [ ] **Step 1: Thêm import**

Trong phần import của `camera_screen.dart`, thêm:

```dart
import '../analysis/scene_analysis.dart';
```

(Các provider dùng qua `ref` đã có sẵn từ `import '../../providers.dart';`.)

- [ ] **Step 2: Thay thân `_suggestFilter`**

Thay khối `try { ... }` bên trong `_suggestFilter` (giữ nguyên phần kiểm tra đầu và `finally`) bằng:

```dart
    setState(() => _suggesting = true);
    try {
      await _pauseCompositionStream();
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      SceneAnalysis analysis;
      try {
        analysis = await ref
            .read(sceneAnalyzerProvider)
            .analyze(jpegBytes: bytes, filePath: shot.path);
      } catch (_) {
        analysis = await ref
            .read(offlineAnalyzerProvider)
            .analyze(jpegBytes: bytes, filePath: shot.path);
      }
      final index = filmPresets.indexWhere((p) => p.id == analysis.presetId);
      if (mounted && index >= 0) {
        setState(() => _presetIndex = index);
        final preset = filmPresets[index];
        final reason = analysis.reason;
        final suffix = (analysis.fromCloud && reason != null) ? ' — $reason' : '';
        _showMessage('Gợi ý filter: ${preset.name} ✨$suffix');
      }
    } catch (e) {
      if (mounted) _showMessage('Không gợi ý được filter: $e');
    } finally {
      await _resumeCompositionStream();
      if (mounted) setState(() => _suggesting = false);
    }
```

- [ ] **Step 3: Phân tích tĩnh**

Run: `flutter analyze`
Expected: không lỗi.

- [ ] **Step 4: Verify thủ công trên máy thật**

Run (thay KEY bằng key Gemini thật):
`flutter run --dart-define=GEMINI_API_KEY=KEY`

Kiểm:
1. Có mạng + key đúng → bấm nút "AI gợi ý filter": preset đổi, snackbar hiện tên preset kèm lý do (" — ...").
2. Tắt mạng (bật máy bay) → bấm lại: vẫn đổi preset, snackbar hiện "Ngoại tuyến: ..." hoặc tên preset (không có lý do cloud), app không treo.
Expected: cả hai trường hợp đều đổi filter, không crash.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/camera/camera_screen.dart
git commit -m "feat: goi y filter dung Gemini, fallback on-device khi offline"
```

---

### Task 7: Nối Gemini vào bố cục (chốt điểm đích 1 lần)

**Files:**
- Modify: `lib/src/features/camera/camera_screen.dart` — thêm state, sửa `_resetAnalysisState`, `_toggleComposition`, `_handleAnalyzingFrame`, `_onViewfinderLongPress`; thêm `_runCloudCompositionAnalysis`.

**Interfaces:**
- Consumes: `sceneAnalyzerProvider`, `SceneAnalysis`, `adviseComposition`, `_subjectViewRect`, `_pauseCompositionStream`, `_resumeCompositionStream`, `_startCompositionStream`, `_showMessage`, các state `_fixedTarget`, `_advice`, `_compositionPhase`, `_candidateFrames`, `_wasAligned`, `_subjectDetector`.
- Produces: state mới `Offset? _cloudTarget`, `bool _cloudResolved`, `List<String> _cloudTips`; method `Future<void> _runCloudCompositionAnalysis()`.

Ghi chú thiết kế: điểm đích do Gemini chốt **một lần** khi bật ⊹. Realtime tracking, dấu +, rung khi trùng giữ nguyên (đọc `_fixedTarget`). Đổi chủ thể bằng long-press hoặc "phân tích lại" ở vùng trống dùng đích hình học (chỉ lần bật ⊹ mới gọi cloud) — chấp nhận cho bản này.

- [ ] **Step 1: Thêm state fields**

Sau dòng `bool _lostNotified = false;` (khoảng dòng 55) thêm:

```dart
  Offset? _cloudTarget;
  bool _cloudResolved = true;
  List<String> _cloudTips = const [];
```

- [ ] **Step 2: Reset state cloud trong `_resetAnalysisState`**

Trong `_resetAnalysisState()` thêm 3 dòng cuối:

```dart
  void _resetAnalysisState() {
    _fixedTarget = null;
    _candidateId = null;
    _candidateFrames = 0;
    _manualLock = false;
    _lostNotified = false;
    _wasAligned = false;
    _advice = null;
    _cloudTarget = null;
    _cloudResolved = true;
    _cloudTips = const [];
  }
```

- [ ] **Step 3: Thêm `_runCloudCompositionAnalysis`**

Ngay dưới `_resetAnalysisState()` thêm method:

```dart
  /// Chụp 1 ảnh tĩnh, hỏi Gemini điểm bố cục đẹp nhất. Tạm dừng stream khi
  /// chụp rồi bật lại. Lỗi/offline → giữ _cloudTarget null (fallback hình học).
  Future<void> _runCloudCompositionAnalysis() async {
    final controller = _controller;
    _cloudResolved = false;
    _cloudTarget = null;
    _cloudTips = const [];
    if (controller == null || !controller.value.isInitialized) {
      _cloudResolved = true;
      return;
    }
    try {
      await _pauseCompositionStream();
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      final analysis = await ref
          .read(sceneAnalyzerProvider)
          .analyze(jpegBytes: bytes, filePath: shot.path);
      _cloudTarget = analysis.targetPoint;
      _cloudTips = analysis.tips;
    } catch (_) {
      // Giữ null → dùng đích hình học.
    } finally {
      _cloudResolved = true;
      await _resumeCompositionStream();
    }
  }
```

- [ ] **Step 4: Gọi cloud khi bật ⊹ trong `_toggleComposition`**

Thay nhánh bật (phần sau `if (... != off) { ... return; }`) của `_toggleComposition`:

```dart
    _resetAnalysisState();
    _compositionPhase = _CompositionPhase.analyzing;
    if (mounted) setState(() {});
    _showMessage('Đang phân tích khung hình — giữ nguyên máy…');
    await _runCloudCompositionAnalysis();
    if (mounted) setState(() {});
```

(`_runCloudCompositionAnalysis` tự bật lại stream qua `_resumeCompositionStream`; không cần gọi `_startCompositionStream` riêng.)

- [ ] **Step 5: Dùng đích Gemini trong `_handleAnalyzingFrame`**

Thay đoạn từ `if (_candidateFrames < 3) return;` tới hết method bằng:

```dart
    if (_candidateFrames < 3) return;
    if (!_cloudResolved) return; // chờ Gemini trả điểm bố cục

    _subjectDetector!.lockTo(id);
    final viewRect = _subjectViewRect(subject, camera);
    _fixedTarget = _cloudTarget ?? adviseComposition(viewRect).target;
    final advice = adviseComposition(viewRect, fixedTarget: _fixedTarget);
    _compositionPhase = _CompositionPhase.guiding;
    _wasAligned = advice.isAligned;
    setState(() => _advice = advice);
    HapticFeedback.selectionClick();
    final tip = _cloudTips.isNotEmpty
        ? _cloudTips.first
        : 'di máy cho dấu + trùng nốt tròn.';
    _showMessage('Đã tìm điểm chụp đẹp — $tip');
```

- [ ] **Step 6: Phân tích tĩnh + test hồi quy**

Run: `flutter analyze && flutter test`
Expected: không lỗi; toàn bộ test cũ vẫn PASS (logic hình học `adviseComposition` không đổi).

- [ ] **Step 7: Verify thủ công trên máy thật**

Run: `flutter run --dart-define=GEMINI_API_KEY=KEY`

Kiểm:
1. Có mạng: bấm ⊹ → snackbar "Đang phân tích…", sau ~1-2s hiện nốt tròn tại điểm Gemini + mẹo; di máy cho dấu + trùng nốt tròn → **rung nhẹ** khi trùng.
2. Tắt mạng: bấm ⊹ → sau timeout hiện nốt tròn theo rule-of-thirds (hình học), vẫn rung khi trùng, không treo.
3. Long-press vào chủ thể khác → khoá và dẫn hướng theo đích hình học (không cần cloud).
Expected: đúng cả ba, preview không đứng hình lâu, không crash.

- [ ] **Step 8: Commit**

```bash
git add lib/src/features/camera/camera_screen.dart
git commit -m "feat: bo cuc dung diem dep nhat tu Gemini, chot 1 lan, fallback hinh hoc"
```

---

### Task 8: Tài liệu cấu hình key

**Files:**
- Modify: `README.md` (tạo nếu chưa có)

**Interfaces:** không có code.

- [ ] **Step 1: Thêm mục hướng dẫn**

Thêm vào `README.md` (tạo file nếu chưa có):

```markdown
## AI phân tích ảnh (Gemini)

App dùng Google Gemini 2.5 Flash để gợi ý filter và điểm bố cục. Cần API key
(lấy tại https://aistudio.google.com/apikey).

Chạy với key:

    flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY

Build:

    flutter build apk --dart-define=GEMINI_API_KEY=YOUR_KEY

Không có key hoặc mất mạng → app tự dùng phân tích on-device (ML Kit). Không
commit key vào git.

> Lộ trình: trước khi phát hành rộng nên chuyển sang Firebase AI Logic để
> không nhúng key trong app (xem docs/superpowers/specs, mục 9).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: huong dan cau hinh GEMINI_API_KEY"
```

---

## Self-Review

**Spec coverage:**
- Model `SceneAnalysis` → Task 1. ✓
- Interface `SceneAnalyzer` + `GeminiSceneAnalyzer` → Task 4. ✓
- Prompt + JSON schema → Task 2. ✓
- Tối ưu ảnh (768px) → Task 3. ✓
- Nối Filter → Task 6. ✓
- Nối Bố cục (giữ realtime, target 1 lần, rung khi trùng) → Task 7. ✓
- Fallback offline (filter: OfflineSceneAnalyzer; bố cục: hình học inline) → Task 5 + Task 6/7. ✓
- Cấu hình key `--dart-define` + tài liệu → Task 8. ✓
- Testing phần thuần → Task 1-5. ✓
- Lộ trình Firebase AI Logic → nêu trong Task 8 doc + spec. ✓

**Placeholder scan:** không có TBD/TODO; mọi step có code/lệnh cụ thể.

**Type consistency:** `analyze({required Uint8List jpegBytes, required String filePath})` dùng nhất quán ở interface, Gemini, Offline và cả hai điểm gọi. `SceneAnalysis` field names (`presetId`, `reason`, `mood`, `targetPoint`, `tips`, `fromCloud`) khớp giữa Task 1/2/4/5. `_cloudTarget`/`_cloudResolved`/`_cloudTips` khớp giữa các step Task 7.
