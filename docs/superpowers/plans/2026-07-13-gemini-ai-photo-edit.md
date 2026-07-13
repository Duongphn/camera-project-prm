# Chỉnh sửa ảnh bằng AI (Gemini) — Kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm tab "AI" vào `EditScreen` cho phép chỉnh sửa ảnh tạo sinh bằng Gemini (4 nút nhanh + ô lệnh tự do), xem trước rồi mới đồng ý.

**Architecture:** Mô phỏng pattern `GeminiSceneAnalyzer` sẵn có: service REST + hàm thuần build/parse tách riêng để test không cần mạng. UI thêm vào `EditScreen` một tab chuyển giữa "Chỉnh tay" (shader on-device đã có) và "AI". Ảnh AI trả về được xem trước; khi "Dùng" thì thành `_source` nền mới để chỉnh tay tiếp.

**Tech Stack:** Flutter, Dart, `http`, `image`, `flutter_riverpod`, `dart:ui`. Model `gemini-2.5-flash-image:generateContent`.

## Global Constraints

- API key lấy từ `const String.fromEnvironment('GEMINI_API_KEY')` (truyền qua `--dart-define`) — KHÔNG hard-code.
- Giải mã response bằng `utf8.decode(resp.bodyBytes)` (không dùng `resp.body`) — giữ tiếng Việt.
- Request body chỉnh ảnh KHÔNG có `responseSchema`/`responseMimeType` (khác analyzer).
- Ném `Exception` (không phải `Error`) cho mọi lỗi runtime từ Gemini để phía UI bắt được.
- Chuỗi hiển thị bằng tiếng Việt; prompt gửi Gemini bằng tiếng Anh.
- Dùng token màu/spacing sẵn có: `DokaColors`, `DokaType`, `DokaSpacing`, `DokaRadius`.
- Tái sử dụng `MissingApiKeyException` và `downscaleForVision` đã có — không định nghĩa lại.

---

### Task 1: Hàm thuần build request + parse ảnh

**Files:**
- Create: `lib/src/features/editor/ai/image_edit_request.dart`
- Test: `test/image_edit_request_test.dart`

**Interfaces:**
- Produces:
  - `Map<String, dynamic> buildImageEditRequestBody({required String base64Image, required String prompt})`
  - `Uint8List parseEditedImage(Map<String, dynamic> json)` — ném `Exception` nếu không có phần ảnh.

- [ ] **Step 1: Viết test thất bại**

Tạo `test/image_edit_request_test.dart`:

```dart
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
```

- [ ] **Step 2: Chạy test để chắc chắn FAIL**

Run: `flutter test test/image_edit_request_test.dart`
Expected: FAIL — `image_edit_request.dart` chưa tồn tại (lỗi import).

- [ ] **Step 3: Viết implementation tối thiểu**

Tạo `lib/src/features/editor/ai/image_edit_request.dart`:

```dart
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
```

- [ ] **Step 4: Chạy test để chắc chắn PASS**

Run: `flutter test test/image_edit_request_test.dart`
Expected: PASS (6 test).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/editor/ai/image_edit_request.dart test/image_edit_request_test.dart
git commit -m "feat: build/parse request chinh anh Gemini (ham thuan)"
```

---

### Task 2: Danh sách nút nhanh

**Files:**
- Create: `lib/src/features/editor/ai/quick_edits.dart`
- Test: `test/quick_edits_test.dart`

**Interfaces:**
- Produces:
  - `class QuickEdit { final String label; final String prompt; const QuickEdit(this.label, this.prompt); }`
  - `const List<QuickEdit> quickEdits` — 4 mục.

- [ ] **Step 1: Viết test thất bại**

Tạo `test/quick_edits_test.dart`:

```dart
import 'package:doka_app/src/features/editor/ai/quick_edits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('có đúng 4 nút nhanh, nhãn + prompt đều khác rỗng', () {
    expect(quickEdits.length, 4);
    for (final q in quickEdits) {
      expect(q.label.trim(), isNotEmpty);
      expect(q.prompt.trim(), isNotEmpty);
    }
  });
}
```

- [ ] **Step 2: Chạy test để chắc chắn FAIL**

Run: `flutter test test/quick_edits_test.dart`
Expected: FAIL — `quick_edits.dart` chưa tồn tại.

- [ ] **Step 3: Viết implementation tối thiểu**

Tạo `lib/src/features/editor/ai/quick_edits.dart`:

```dart
/// Một nút chỉnh nhanh: nhãn tiếng Việt hiển thị + prompt tiếng Anh gửi Gemini.
class QuickEdit {
  const QuickEdit(this.label, this.prompt);

  final String label;
  final String prompt;
}

/// 4 nút nhanh cho bản đầu. Prompt tiếng Anh để Gemini xử lý ổn định hơn.
const List<QuickEdit> quickEdits = [
  QuickEdit(
    'Xoá phông',
    'Keep the main subject sharp and unchanged. Cleanly blur or remove the '
        'background so the subject stands out. Do not alter the subject.',
  ),
  QuickEdit(
    'Đổi bầu trời',
    'Replace only the sky with a beautiful clear blue sky with soft clouds. '
        'Keep the foreground, subject and lighting consistent and realistic.',
  ),
  QuickEdit(
    'Nâng chất lượng',
    'Enhance this photo: increase sharpness and detail, reduce noise. Keep the '
        'exact same composition, colors and content. Do not add or remove anything.',
  ),
  QuickEdit(
    'Style phim',
    'Apply an analog film look: warm tones, soft contrast, gentle film grain, '
        'slightly faded highlights. Keep the composition and subject unchanged.',
  ),
];
```

- [ ] **Step 4: Chạy test để chắc chắn PASS**

Run: `flutter test test/quick_edits_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/editor/ai/quick_edits.dart test/quick_edits_test.dart
git commit -m "feat: danh sach 4 nut chinh nhanh AI"
```

---

### Task 3: Service `GeminiImageEditor` + provider

**Files:**
- Create: `lib/src/features/editor/ai/gemini_image_editor.dart`
- Modify: `lib/src/providers.dart`
- Test: `test/gemini_image_editor_test.dart`

**Interfaces:**
- Consumes: `buildImageEditRequestBody`, `parseEditedImage` (Task 1); `MissingApiKeyException`, `downscaleForVision` (đã có trong repo).
- Produces:
  - `class GeminiImageEditor { GeminiImageEditor({http.Client? client, String apiKey, Duration timeout}); Future<Uint8List> editImage({required Uint8List jpegBytes, required String prompt}); }`
  - `final geminiImageEditorProvider` trong `providers.dart`.

- [ ] **Step 1: Viết test thất bại**

Tạo `test/gemini_image_editor_test.dart`:

```dart
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
```

- [ ] **Step 2: Chạy test để chắc chắn FAIL**

Run: `flutter test test/gemini_image_editor_test.dart`
Expected: FAIL — `gemini_image_editor.dart` chưa tồn tại.

- [ ] **Step 3: Viết implementation tối thiểu**

Tạo `lib/src/features/editor/ai/gemini_image_editor.dart`:

```dart
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
```

- [ ] **Step 4: Thêm provider**

Sửa `lib/src/providers.dart` — thêm import và provider:

```dart
import 'features/editor/ai/gemini_image_editor.dart';
```

Thêm vào cuối file:

```dart
/// Chỉnh sửa ảnh tạo sinh bằng Gemini (tab AI trong EditScreen).
final geminiImageEditorProvider =
    Provider<GeminiImageEditor>((ref) => GeminiImageEditor());
```

- [ ] **Step 5: Chạy test để chắc chắn PASS**

Run: `flutter test test/gemini_image_editor_test.dart`
Expected: PASS (4 test).

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/editor/ai/gemini_image_editor.dart lib/src/providers.dart test/gemini_image_editor_test.dart
git commit -m "feat: service GeminiImageEditor + provider"
```

---

### Task 4: Tích hợp tab AI vào `EditScreen`

**Files:**
- Modify: `lib/src/features/editor/edit_screen.dart` (thay toàn bộ file)

**Interfaces:**
- Consumes: `geminiImageEditorProvider` (Task 3), `quickEdits` (Task 2), `ImageRenderer.downscale`, `photoRepositoryProvider` (đã có).
- Produces: không có API cho task khác (đây là màn hình lá).

Không có unit test cho UI (đúng phạm vi spec — chỉ test hàm thuần). Kiểm chứng bằng `flutter analyze` + chạy thật.

- [ ] **Step 1: Thay toàn bộ `lib/src/features/editor/edit_screen.dart`**

```dart
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../filters/film_preset.dart';
import '../filters/image_renderer.dart';
import '../filters/photo_encoder.dart';
import '../filters/photo_processor.dart';
import 'ai/quick_edits.dart';

/// Chế độ chỉnh: thông số shader on-device, hoặc chỉnh tạo sinh bằng Gemini.
enum _EditMode { manual, ai }

/// Một thông số chỉnh được trong editor.
class _Adjustment {
  const _Adjustment(this.label, this.min, this.max, this.neutral);

  final String label;
  final double min;
  final double max;
  final double neutral;
}

/// Mã hoá RGBA → JPEG trong isolate riêng.
///
/// Phải là hàm CẤP CAO NHẤT (không phải method của State): closure gửi sang
/// isolate chỉ được bắt các tham số thuần (rgba/width/height đều gửi được).
/// Nếu đặt trong method, closure sẽ bắt luôn `this` → kéo theo `ui.Image` của
/// State (không gửi được) → lỗi "object is unsendable".
Future<Uint8List> _encodeJpegInIsolate(
  Uint8List rgba,
  int width,
  int height,
) {
  return Isolate.run(() => encodeRgbaToJpeg(rgba, width, height));
}

/// Chấm đồng nhỏ báo thông số đã bị chỉnh khỏi mặc định.
class _ChangedDot extends StatelessWidget {
  const _ChangedDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: DokaColors.brass,
      ),
    );
  }
}

const _adjustments = <_Adjustment>[
  _Adjustment('Phơi sáng', -1, 1, 0),
  _Adjustment('Tương phản', 0.5, 1.5, 1),
  _Adjustment('Nhiệt màu', -1, 1, 0),
  _Adjustment('Bão hoà', 0, 2, 1),
  _Adjustment('Fade', 0, 1, 0),
  _Adjustment('Vignette', 0, 1, 0),
  _Adjustment('Hạt', 0, 1, 0),
];

/// Chỉnh màu một ảnh đã chụp và lưu thành ảnh mới.
class EditScreen extends ConsumerStatefulWidget {
  const EditScreen({super.key, required this.file});

  final File file;

  @override
  ConsumerState<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends ConsumerState<EditScreen> {
  ui.Image? _source; // full-res, dùng khi lưu
  ui.Image? _previewBase; // downscale, dùng khi preview
  ui.Image? _rendered;

  final _values = [for (final a in _adjustments) a.neutral];
  int _selected = 0;
  bool _rendering = false;
  bool _dirty = false;
  bool _saving = false;

  // Trạng thái tab AI.
  _EditMode _mode = _EditMode.manual;
  final _promptController = TextEditingController();
  bool _aiBusy = false;
  int _aiRequestId = 0; // token vô hiệu request khi người dùng huỷ
  ui.Image? _aiPreview; // ảnh AI đang xem trước (chưa "Dùng")

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _source?.dispose();
    _previewBase?.dispose();
    _rendered?.dispose();
    _aiPreview?.dispose();
    _promptController.dispose();
    super.dispose();
  }

  FilmPreset _currentPreset() => FilmPreset(
        id: 'custom',
        name: 'Tuỳ chỉnh',
        exposure: _values[0],
        contrast: _values[1],
        temperature: _values[2],
        saturation: _values[3],
        fade: _values[4],
        vignette: _values[5],
        grain: _values[6],
      );

  Future<void> _load() async {
    final bytes = await widget.file.readAsBytes();
    final image = await _decodeImage(bytes);
    if (!mounted) {
      image.dispose();
      return;
    }
    _source = image;
    _previewBase = await ImageRenderer.downscale(_source!, 1080);
    if (!mounted) return;
    await _rerender();
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<void> _rerender() async {
    final base = _previewBase;
    if (base == null) return;
    if (_rendering) {
      _dirty = true;
      return;
    }
    _rendering = true;
    do {
      _dirty = false;
      final image = await ImageRenderer.filmPass(base, _currentPreset());
      if (!mounted) {
        image.dispose();
        _rendering = false;
        return;
      }
      final old = _rendered;
      setState(() => _rendered = image);
      if (old != null) {
        // Đợi frame hiện tại vẽ xong rồi mới giải phóng ảnh cũ.
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } while (_dirty);
    _rendering = false;
  }

  Future<void> _save() async {
    final source = _source;
    if (source == null || _saving) return;
    setState(() => _saving = true);
    try {
      final rendered = await ImageRenderer.filmPass(
        source,
        _currentPreset(),
        seed: math.Random().nextDouble() * 1000,
      );
      try {
        final raw =
            await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (raw == null) {
          throw StateError('Không đọc được dữ liệu ảnh sau khi render.');
        }
        final rgba = raw.buffer.asUint8List();
        final width = rendered.width;
        final height = rendered.height;
        final jpeg = await _encodeJpegInIsolate(rgba, width, height);
        final file = await ref.read(photoRepositoryProvider).savePhoto(jpeg);
        await PhotoProcessor.saveToSystemGallery(file);
      } finally {
        rendered.dispose();
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lưu thất bại: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Mã hoá ảnh nguồn hiện tại thành JPEG để gửi Gemini.
  Future<Uint8List> _sourceToJpeg(ui.Image image) async {
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) {
      throw StateError('Không đọc được dữ liệu ảnh nguồn.');
    }
    return _encodeJpegInIsolate(
      raw.buffer.asUint8List(),
      image.width,
      image.height,
    );
  }

  Future<void> _runAiEdit(String prompt) async {
    final source = _source;
    if (source == null || _aiBusy || prompt.trim().isEmpty) return;
    setState(() => _aiBusy = true);
    final requestId = ++_aiRequestId;
    try {
      final jpeg = await _sourceToJpeg(source);
      final bytes = await ref
          .read(geminiImageEditorProvider)
          .editImage(jpegBytes: jpeg, prompt: prompt);
      if (!mounted || requestId != _aiRequestId) return; // đã huỷ
      final preview = await _decodeImage(bytes);
      if (!mounted || requestId != _aiRequestId) {
        preview.dispose();
        return;
      }
      setState(() {
        _aiPreview?.dispose();
        _aiPreview = preview;
      });
    } catch (e) {
      if (mounted && requestId == _aiRequestId) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Chỉnh AI thất bại: $e')));
      }
    } finally {
      if (mounted && requestId == _aiRequestId) {
        setState(() => _aiBusy = false);
      }
    }
  }

  void _cancelAi() {
    _aiRequestId++; // vô hiệu request đang chờ
    setState(() => _aiBusy = false);
  }

  void _discardAi() {
    setState(() {
      _aiPreview?.dispose();
      _aiPreview = null;
    });
  }

  Future<void> _applyAiResult() async {
    final preview = _aiPreview;
    if (preview == null) return;
    final oldSource = _source;
    final oldPreviewBase = _previewBase;
    _source = preview; // ảnh AI thành nền mới
    _aiPreview = null;
    _previewBase = await ImageRenderer.downscale(_source!, 1080);
    for (var i = 0; i < _values.length; i++) {
      _values[i] = _adjustments[i].neutral;
    }
    if (!mounted) {
      return;
    }
    oldSource?.dispose();
    oldPreviewBase?.dispose();
    setState(() => _mode = _EditMode.manual);
    await _rerender();
  }

  @override
  Widget build(BuildContext context) {
    final adjustment = _adjustments[_selected];
    return Scaffold(
      backgroundColor: DokaColors.body,
      appBar: AppBar(
        backgroundColor: DokaColors.body,
        foregroundColor: DokaColors.ink,
        elevation: 0,
        title: const Text('Chỉnh ảnh', style: DokaType.title),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DokaColors.brass,
                ),
              ),
            )
          else
            IconButton(
              onPressed: _save,
              tooltip: 'Lưu ảnh mới',
              icon: const Icon(Icons.check, color: DokaColors.brass),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _imageArea()),
          if (_aiPreview != null)
            _aiPreviewActions()
          else ...[
            _modeToggle(),
            if (_mode == _EditMode.manual)
              ..._manualControls(adjustment)
            else
              _aiPanel(),
          ],
        ],
      ),
    );
  }

  Widget _imageArea() {
    final preview = _aiPreview;
    final Widget content;
    if (preview != null) {
      content = Padding(
        padding: const EdgeInsets.all(DokaSpacing.md),
        child: RawImage(image: preview, fit: BoxFit.contain),
      );
    } else if (_rendered == null) {
      content = const Center(
        child: CircularProgressIndicator(color: DokaColors.brassDeep),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(DokaSpacing.md),
        child: RawImage(image: _rendered, fit: BoxFit.contain),
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: content),
        if (_aiBusy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: DokaColors.brass),
                    const SizedBox(height: DokaSpacing.md),
                    Text('Đang xử lý AI…',
                        style: DokaType.chip.copyWith(color: DokaColors.ink)),
                    const SizedBox(height: DokaSpacing.md),
                    TextButton(onPressed: _cancelAi, child: const Text('Huỷ')),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _aiPreviewActions() {
    return Padding(
      padding: const EdgeInsets.all(DokaSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Ảnh AI có độ phân giải thấp hơn ảnh gốc.',
            style: DokaType.chip.copyWith(color: DokaColors.inkMuted),
          ),
          const SizedBox(height: DokaSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _discardAi,
                  child: const Text('Huỷ'),
                ),
              ),
              const SizedBox(width: DokaSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: _applyAiResult,
                  child: const Text('Dùng'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DokaSpacing.lg,
        vertical: DokaSpacing.xs,
      ),
      child: Row(
        children: [
          _modeTab('Chỉnh tay', _EditMode.manual),
          const SizedBox(width: DokaSpacing.sm),
          _modeTab('AI', _EditMode.ai),
        ],
      ),
    );
  }

  Widget _modeTab(String label, _EditMode mode) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? DokaColors.brass.withValues(alpha: 0.16)
              : DokaColors.surface,
          borderRadius: BorderRadius.circular(DokaRadius.chip),
          border: Border.all(
            color: selected
                ? DokaColors.brass.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.06),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: DokaType.chip.copyWith(
            color: selected ? DokaColors.ink : DokaColors.inkMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  List<Widget> _manualControls(_Adjustment adjustment) {
    return [
      SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: DokaSpacing.lg),
          itemCount: _adjustments.length,
          separatorBuilder: (_, _) => const SizedBox(width: DokaSpacing.sm),
          itemBuilder: (context, index) {
            final selected = index == _selected;
            final changed = _values[index] != _adjustments[index].neutral;
            return GestureDetector(
              onTap: () => setState(() => _selected = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? DokaColors.brass.withValues(alpha: 0.16)
                      : DokaColors.surface,
                  borderRadius: BorderRadius.circular(DokaRadius.chip),
                  border: Border.all(
                    color: selected
                        ? DokaColors.brass.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.06),
                    width: selected ? 1.2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _adjustments[index].label,
                      style: DokaType.chip.copyWith(
                        color: selected ? DokaColors.ink : DokaColors.inkMuted,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (changed) ...[
                      const SizedBox(width: 6),
                      const _ChangedDot(),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            DokaSpacing.lg, DokaSpacing.xs, DokaSpacing.sm, DokaSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Slider(
                value: _values[_selected],
                min: adjustment.min,
                max: adjustment.max,
                onChanged: (v) {
                  setState(() => _values[_selected] = v);
                  _rerender();
                },
              ),
            ),
            IconButton(
              tooltip: 'Đặt lại tất cả',
              onPressed: () {
                setState(() {
                  for (var i = 0; i < _values.length; i++) {
                    _values[i] = _adjustments[i].neutral;
                  }
                });
                _rerender();
              },
              icon: const Icon(Icons.refresh, color: DokaColors.inkMuted),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _aiPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          DokaSpacing.lg, DokaSpacing.xs, DokaSpacing.lg, DokaSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: DokaSpacing.sm,
            runSpacing: DokaSpacing.sm,
            children: [
              for (final q in quickEdits)
                GestureDetector(
                  onTap: _aiBusy ? null : () => _runAiEdit(q.prompt),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: DokaColors.surface,
                      borderRadius: BorderRadius.circular(DokaRadius.chip),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Text(
                      q.label,
                      style: DokaType.chip.copyWith(color: DokaColors.ink),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: DokaSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  enabled: !_aiBusy,
                  style: DokaType.chip.copyWith(color: DokaColors.ink),
                  decoration: InputDecoration(
                    hintText: 'Nhập lệnh chỉnh sửa…',
                    hintStyle:
                        DokaType.chip.copyWith(color: DokaColors.inkMuted),
                    filled: true,
                    fillColor: DokaColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DokaRadius.chip),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: _aiBusy ? null : _runAiEdit,
                ),
              ),
              const SizedBox(width: DokaSpacing.sm),
              IconButton(
                tooltip: 'Chỉnh bằng AI',
                onPressed:
                    _aiBusy ? null : () => _runAiEdit(_promptController.text),
                icon: const Icon(Icons.auto_awesome, color: DokaColors.brass),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Phân tích tĩnh**

Run: `flutter analyze lib/src/features/editor/edit_screen.dart`
Expected: No issues found.

- [ ] **Step 3: Chạy toàn bộ test (không hồi quy)**

Run: `flutter test`
Expected: Tất cả PASS (gồm 3 file test mới ở Task 1–3).

- [ ] **Step 4: Kiểm chứng thủ công trên thiết bị/emulator**

Run (cần key thật để thử nhánh thành công):
```bash
flutter run --dart-define=GEMINI_API_KEY=<key>
```
Checklist quan sát:
- Mở một ảnh → EditScreen. Thấy 2 tab "Chỉnh tay / AI".
- Tab "Chỉnh tay" hoạt động y như cũ (chip + slider + reset).
- Tab "AI": 4 nút (Xoá phông, Đổi bầu trời, Nâng chất lượng, Style phim) + ô nhập + nút gửi.
- Bấm 1 nút nhanh → overlay "Đang xử lý AI…" có nút Huỷ → hiện ảnh AI xem trước + dòng "Ảnh AI có độ phân giải thấp hơn ảnh gốc." + nút Dùng/Huỷ.
- "Dùng" → ảnh AI thành nền, quay về tab Chỉnh tay, chỉnh slider vẫn chạy, lưu ra gallery được.
- "Huỷ" → quay lại ảnh trước.
- Tắt mạng → bấm AI → SnackBar báo lỗi, ảnh giữ nguyên.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/editor/edit_screen.dart
git commit -m "feat: tab AI chinh sua anh bang Gemini trong EditScreen"
```

---

## Self-Review

**Spec coverage:**
- Nút nhanh + ô lệnh tự do → Task 2 (data) + Task 4 (UI). ✓
- Tab AI trong EditScreen → Task 4. ✓
- Xem trước → Dùng/Huỷ; Dùng thành nền mới, reset thông số → `_applyAiResult`, `_discardAi` (Task 4). ✓
- 4 nút nhanh (Xoá phông, Đổi bầu trời, Nâng chất lượng, Style phim) → Task 2. ✓
- Cảnh báo độ phân giải (phương án 2) → `_aiPreviewActions` (Task 4). ✓
- Model `gemini-2.5-flash-image`, reuse key/http/downscale, body không schema → Task 1 + Task 3. ✓
- Xử lý lỗi: thiếu key / HTTP / bị chặn → SnackBar → Task 3 (ném) + Task 4 (bắt). ✓
- Test hàm thuần, không gọi mạng thật → Task 1 + Task 3 (MockClient). ✓
- Ngoài phạm vi (upscale, undo nhiều bước, mask, so sánh trượt) → không có task. ✓

**Placeholder scan:** Không có TBD/TODO; mọi step có code/command + kết quả kỳ vọng. ✓

**Type consistency:** `buildImageEditRequestBody({base64Image, prompt})`, `parseEditedImage(json)→Uint8List`, `GeminiImageEditor.editImage({jpegBytes, prompt})→Uint8List`, `geminiImageEditorProvider`, `QuickEdit{label, prompt}`, `quickEdits` — dùng nhất quán qua Task 1→4. ✓
