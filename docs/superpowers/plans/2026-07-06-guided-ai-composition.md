# Guided AI Composition (kiểu Doka Cam) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nâng cấp luồng AI bố cục hiện có thành trải nghiệm dẫn dắt 4 pha kiểu Doka Cam: hiệu ứng phân tích chấm sáng → vòng ngắm cầu vồng → khung crop + tự động zoom → tự áp filter kèm toast giải thích tiếng Việt.

**Architecture:** Mở rộng state machine `_CompositionPhase` trong `camera_screen.dart` (off → analyzing → aiming → framing), mở rộng schema Gemini thêm `cropX/cropY/cropW/cropH` + `advice` (vẫn 1 lần gọi API), thêm 3 widget overlay mới + 1 hàm thuần `zoomForCrop`. Spec: `docs/superpowers/specs/2026-07-06-guided-ai-composition-design.md`.

**Tech Stack:** Flutter, camera ^0.12, flutter_riverpod, image, Gemini 2.5 Flash REST (đã có sẵn), flutter_test.

## Global Constraints

- Mọi text hiển thị cho người dùng bằng tiếng Việt.
- KHÔNG watermark trên ảnh (đã quyết định trong spec §1).
- Vẫn đúng MỘT lần gọi Gemini cho cả filter + điểm ngắm + crop + lời khuyên.
- Fallback offline giữ hành vi hiện tại: không cropRect/advice → không có pha framing.
- Lint: tuân `flutter_lints` (chạy `flutter analyze` sạch trước mỗi commit).
- Chạy test bằng `flutter test` từ thư mục gốc repo.
- Commit message tiếng Việt không dấu theo phong cách repo (vd `feat: them ...`).

---

### Task 1: Mở rộng SceneAnalysis + schema/parse Gemini (cropRect, advice)

**Files:**
- Modify: `lib/src/features/analysis/scene_analysis.dart`
- Modify: `lib/src/features/analysis/gemini_prompt.dart`
- Test: `test/gemini_prompt_test.dart`

**Interfaces:**
- Consumes: `SceneAnalysis`, `parseGeminiJson`, `sceneResponseSchema`, `buildScenePrompt` hiện có.
- Produces: `SceneAnalysis.cropRect` (`Rect?`, 0..1 trên ảnh, gốc trên-trái) và `SceneAnalysis.advice` (`String?`). Task 6 (integration) đọc 2 field này.

- [ ] **Step 1: Viết test fail cho parse cropRect + advice**

Thêm vào cuối `main()` trong `test/gemini_prompt_test.dart`:

```dart
  test('parse cropRect + advice hợp lệ', () {
    final a = parseGeminiJson({
      'presetId': 'dalat',
      'cropX': 0.1,
      'cropY': 0.2,
      'cropW': 0.5,
      'cropH': 0.6,
      'advice': ' Ảnh dọc, chủ thể căn giữa, chừa khoảng trống. ',
    }, validIds: ids);
    expect(a.cropRect, const Rect.fromLTWH(0.1, 0.2, 0.5, 0.6));
    expect(a.advice, 'Ảnh dọc, chủ thể căn giữa, chừa khoảng trống.');
  });

  test('cropRect thiếu trường hoặc tràn khung → null', () {
    // thiếu cropH
    expect(
      parseGeminiJson(
        {'presetId': 'dalat', 'cropX': 0.1, 'cropY': 0.1, 'cropW': 0.5},
        validIds: ids,
      ).cropRect,
      isNull,
    );
    // w = 0
    expect(
      parseGeminiJson(
        {'presetId': 'dalat', 'cropX': 0.1, 'cropY': 0.1, 'cropW': 0.0, 'cropH': 0.5},
        validIds: ids,
      ).cropRect,
      isNull,
    );
    // tràn phải: x + w > 1
    expect(
      parseGeminiJson(
        {'presetId': 'dalat', 'cropX': 0.7, 'cropY': 0.1, 'cropW': 0.5, 'cropH': 0.5},
        validIds: ids,
      ).cropRect,
      isNull,
    );
  });

  test('advice rỗng → null; mặc định cropRect/advice null', () {
    final a = parseGeminiJson(
      {'presetId': 'dalat', 'advice': '   '},
      validIds: ids,
    );
    expect(a.advice, isNull);
    expect(a.cropRect, isNull);
  });

  test('schema và prompt khai báo trường crop + advice', () {
    final props =
        sceneResponseSchema['properties'] as Map<String, dynamic>;
    expect(props.containsKey('cropX'), isTrue);
    expect(props.containsKey('cropY'), isTrue);
    expect(props.containsKey('cropW'), isTrue);
    expect(props.containsKey('cropH'), isTrue);
    expect(props.containsKey('advice'), isTrue);
    final prompt = buildScenePrompt(filmPresets);
    expect(prompt.contains('cropX'), isTrue);
    expect(prompt.contains('advice'), isTrue);
  });
```

Cần thêm import ở đầu file test (nếu chưa có): `import 'dart:ui';` — file đã dùng `Offset` qua flutter_test nên kiểm tra `Rect` hoạt động sẵn.

- [ ] **Step 2: Chạy test xác nhận fail**

Run: `flutter test test/gemini_prompt_test.dart`
Expected: FAIL — `cropRect`/`advice` không tồn tại (lỗi compile "isn't defined").

- [ ] **Step 3: Thêm field vào SceneAnalysis**

Trong `lib/src/features/analysis/scene_analysis.dart`, constructor thêm 2 tham số và 2 field (đặt sau `targetPoint`):

```dart
  const SceneAnalysis({
    required this.presetId,
    this.reason,
    this.mood,
    this.targetPoint,
    this.cropRect,
    this.advice,
    this.tips = const [],
    this.fromCloud = false,
  });
```

```dart
  /// Vùng crop đẹp nhất trên ảnh, 0..1 (gốc trên-trái). Null nếu Gemini
  /// không trả hoặc không hợp lệ.
  final Rect? cropRect;

  /// Lời khuyên bố cục chi tiết (tiếng Việt) để hiện cho người dùng.
  final String? advice;
```

- [ ] **Step 4: Mở rộng schema + prompt + parse trong gemini_prompt.dart**

Thêm vào `sceneResponseSchema['properties']` (sau `targetY`):

```dart
    'cropX': {'type': 'NUMBER'},
    'cropY': {'type': 'NUMBER'},
    'cropW': {'type': 'NUMBER'},
    'cropH': {'type': 'NUMBER'},
    'advice': {'type': 'STRING'},
```

Trong `buildScenePrompt`, thêm 2 dòng vào danh sách "Trả về các trường:" (sau dòng targetX, targetY):

```
- cropX, cropY, cropW, cropH: vùng CROP đẹp nhất trên ảnh (khung hình lý tưởng), số thực 0..1, gốc 0,0 ở góc trên-trái; cropX+cropW ≤ 1, cropY+cropH ≤ 1.
- advice: lời khuyên bố cục chi tiết bằng tiếng Việt, tối đa 30 từ, kiểu "Ảnh dọc, chủ thể là X, bố cục căn giữa + khoảng trống, nén bớt trời và đất".
```

Trong `parseGeminiJson`, sau khối parse `target` thêm:

```dart
  Rect? cropRect;
  final cx = (json['cropX'] as num?)?.toDouble();
  final cy = (json['cropY'] as num?)?.toDouble();
  final cw = (json['cropW'] as num?)?.toDouble();
  final ch = (json['cropH'] as num?)?.toDouble();
  if (cx != null &&
      cy != null &&
      cw != null &&
      ch != null &&
      cx >= 0 &&
      cy >= 0 &&
      cw > 0 &&
      ch > 0 &&
      cx + cw <= 1 &&
      cy + ch <= 1) {
    cropRect = Rect.fromLTWH(cx, cy, cw, ch);
  }

  final rawAdvice = (json['advice'] as String?)?.trim();
```

Và trong `return SceneAnalysis(...)` thêm:

```dart
    cropRect: cropRect,
    advice: (rawAdvice == null || rawAdvice.isEmpty) ? null : rawAdvice,
```

- [ ] **Step 5: Chạy test xác nhận pass**

Run: `flutter test test/gemini_prompt_test.dart`
Expected: PASS toàn bộ (test cũ + 4 test mới).

- [ ] **Step 6: Chạy toàn bộ test + analyze rồi commit**

```bash
flutter analyze
flutter test
git add lib/src/features/analysis/scene_analysis.dart lib/src/features/analysis/gemini_prompt.dart test/gemini_prompt_test.dart
git commit -m "feat: Gemini tra them cropRect va advice cho guided composition"
```

---

### Task 2: Hàm thuần zoomForCrop

**Files:**
- Create: `lib/src/features/composition/zoom_advisor.dart`
- Test: `test/zoom_advisor_test.dart`

**Interfaces:**
- Consumes: không.
- Produces: `double zoomForCrop(Rect cropRect, {required double maxZoom})` — Task 6 gọi khi vào pha framing.

- [ ] **Step 1: Viết test fail**

Tạo `test/zoom_advisor_test.dart`:

```dart
import 'dart:ui';

import 'package:doka_app/src/features/composition/zoom_advisor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('crop toàn khung → zoom 1', () {
    expect(
      zoomForCrop(const Rect.fromLTWH(0, 0, 1, 1), maxZoom: 8),
      1.0,
    );
  });

  test('crop nửa khung → zoom 2 (theo cạnh lớn hơn)', () {
    expect(
      zoomForCrop(const Rect.fromLTWH(0.25, 0.1, 0.5, 0.3), maxZoom: 8),
      2.0,
    );
  });

  test('crop rất nhỏ bị kẹp về maxZoom', () {
    expect(
      zoomForCrop(const Rect.fromLTWH(0.4, 0.4, 0.1, 0.1), maxZoom: 4),
      4.0,
    );
  });

  test('rect suy biến (cạnh 0) → zoom 1, không chia cho 0', () {
    expect(
      zoomForCrop(const Rect.fromLTWH(0.2, 0.2, 0, 0), maxZoom: 8),
      1.0,
    );
  });
}
```

- [ ] **Step 2: Chạy test xác nhận fail**

Run: `flutter test test/zoom_advisor_test.dart`
Expected: FAIL compile — file `zoom_advisor.dart` chưa tồn tại.

- [ ] **Step 3: Cài đặt tối thiểu**

Tạo `lib/src/features/composition/zoom_advisor.dart`:

```dart
import 'dart:math' as math;
import 'dart:ui';

/// Mức zoom để vùng [cropRect] (0..1, không gian viewfinder) lấp đầy khung.
///
/// Dựa trên cạnh LỚN hơn của crop để không phóng quá vùng đề xuất.
/// `CameraController.setZoomLevel` neo giữa khung, nên chỉ dùng SAU KHI
/// chủ thể đã được căn vào tâm (pha aiming xong) — xem spec §5.
double zoomForCrop(Rect cropRect, {required double maxZoom}) {
  final side = math.max(cropRect.width, cropRect.height);
  if (side <= 0) return 1.0;
  return (1.0 / side).clamp(1.0, maxZoom);
}
```

- [ ] **Step 4: Chạy test xác nhận pass**

Run: `flutter test test/zoom_advisor_test.dart`
Expected: PASS 4/4.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/composition/zoom_advisor.dart test/zoom_advisor_test.dart
git commit -m "feat: ham zoomForCrop tinh muc zoom tu vung crop de xuat"
```

---

### Task 3: Widget AnalyzingSparkleOverlay (chấm sáng gom về lưới)

**Files:**
- Create: `lib/src/features/camera/widgets/analyzing_sparkle_overlay.dart`
- Test: `test/analyzing_sparkle_overlay_test.dart`

**Interfaces:**
- Consumes: không.
- Produces: `AnalyzingSparkleOverlay` (`const AnalyzingSparkleOverlay({super.key})`) — Task 6 đặt vào viewfinder stack khi pha analyzing.

- [ ] **Step 1: Viết widget test fail**

Tạo `test/analyzing_sparkle_overlay_test.dart`:

```dart
import 'package:doka_app/src/features/camera/widgets/analyzing_sparkle_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render và animate không lỗi, không chặn tap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            GestureDetector(
              onTap: () => tapped = true,
              child: const SizedBox.expand(),
            ),
            const AnalyzingSparkleOverlay(),
          ],
        ),
      ),
    );
    // Chạy qua pha gom lưới (2s) + vài nhịp nhấp nháy.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(AnalyzingSparkleOverlay), findsOneWidget);
    // Overlay phải IgnorePointer — tap xuyên qua được.
    await tester.tapAt(const Offset(200, 300));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Chạy test xác nhận fail**

Run: `flutter test test/analyzing_sparkle_overlay_test.dart`
Expected: FAIL compile — widget chưa tồn tại.

- [ ] **Step 3: Cài đặt widget**

Tạo `lib/src/features/camera/widgets/analyzing_sparkle_overlay.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hiệu ứng pha "AI đang phân tích": ~48 chấm sáng pastel rải ngẫu nhiên,
/// nhấp nháy, rồi gom dần về các mắt lưới (kiểu Doka Cam).
class AnalyzingSparkleOverlay extends StatefulWidget {
  const AnalyzingSparkleOverlay({super.key});

  @override
  State<AnalyzingSparkleOverlay> createState() =>
      _AnalyzingSparkleOverlayState();
}

class _AnalyzingSparkleOverlayState extends State<AnalyzingSparkleOverlay>
    with TickerProviderStateMixin {
  /// Tiến độ gom về lưới: chạy 1 lần ~2s.
  late final AnimationController _gather = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..forward();

  /// Nhấp nháy liên tục.
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _gather.dispose();
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _SparklePainter(
          gather: _gather,
          twinkle: _twinkle,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.gather, required this.twinkle})
      : super(repaint: Listenable.merge([gather, twinkle]));

  final Animation<double> gather;
  final Animation<double> twinkle;

  static const int _cols = 6;
  static const int _rows = 8;
  static const List<Color> _palette = [
    Color(0xFF8DE8FF), // cyan nhạt
    Color(0xFFFFB3E2), // hồng nhạt
    Color(0xFFB8C6FF), // tím nhạt
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Seed cố định → vị trí ổn định giữa các frame.
    final random = math.Random(7);
    final t = Curves.easeInOut.transform(gather.value);
    for (var i = 0; i < _cols * _rows; i++) {
      final scatter = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final grid = Offset(
        ((i % _cols) + 0.5) / _cols * size.width,
        ((i ~/ _cols) + 0.5) / _rows * size.height,
      );
      final pos = Offset.lerp(scatter, grid, t)!;
      // Mỗi chấm lệch pha nhấp nháy khác nhau.
      final phase = random.nextDouble();
      final blink =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin((twinkle.value + phase) * 2 * math.pi));
      final color = _palette[i % _palette.length];
      canvas.drawCircle(
        pos,
        2.4,
        Paint()
          ..color = color.withValues(alpha: blink)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) => false;
}
```

- [ ] **Step 4: Chạy test xác nhận pass**

Run: `flutter test test/analyzing_sparkle_overlay_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/camera/widgets/analyzing_sparkle_overlay.dart test/analyzing_sparkle_overlay_test.dart
git commit -m "feat: hieu ung cham sang phan tich AI (sparkle overlay)"
```

---

### Task 4: Vòng ngắm cầu vồng trong CompositionOverlay + FrameGuideOverlay

**Files:**
- Modify: `lib/src/features/composition/composition_overlay.dart`
- Create: `lib/src/features/composition/frame_guide_overlay.dart`
- Test: `test/guide_overlays_test.dart`

**Interfaces:**
- Consumes: `CompositionAdvice` (từ `composition_advisor.dart`).
- Produces: `CompositionOverlay` (API không đổi — `CompositionOverlay({required CompositionAdvice? advice})`); `FrameGuideOverlay({required Rect rect, double opacity = 1})` với `rect` ở không gian 0..1 viewfinder — Task 6 dùng.

- [ ] **Step 1: Viết widget test fail**

Tạo `test/guide_overlays_test.dart`:

```dart
import 'dart:ui';

import 'package:doka_app/src/features/composition/composition_advisor.dart';
import 'package:doka_app/src/features/composition/composition_overlay.dart';
import 'package:doka_app/src/features/composition/frame_guide_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CompositionOverlay vẽ vòng cầu vồng không lỗi', (tester) async {
    final advice = adviseComposition(
      const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
    );
    await tester.pumpWidget(
      MaterialApp(home: CompositionOverlay(advice: advice)),
    );
    expect(find.byType(CompositionOverlay), findsOneWidget);
  });

  testWidgets('FrameGuideOverlay vẽ khung theo rect, opacity 0 vẫn ổn',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            FrameGuideOverlay(rect: Rect.fromLTWH(0.2, 0.15, 0.6, 0.7)),
            FrameGuideOverlay(
              rect: Rect.fromLTWH(0.2, 0.15, 0.6, 0.7),
              opacity: 0,
            ),
          ],
        ),
      ),
    );
    expect(find.byType(FrameGuideOverlay), findsNWidgets(2));
  });
}
```

- [ ] **Step 2: Chạy test xác nhận fail**

Run: `flutter test test/guide_overlays_test.dart`
Expected: FAIL compile — `frame_guide_overlay.dart` chưa tồn tại.

- [ ] **Step 3: Nâng cấp nốt tròn → vòng cầu vồng trong composition_overlay.dart**

Trong `_CompositionPainter.paint`, thay toàn bộ khối vẽ nốt tròn cuối hàm (3 lệnh `canvas.drawCircle` cho `aim` — lõi đặc + viền) bằng:

```dart
    // Vòng ngắm cầu vồng: halo tối để nổi trên mọi nền + viền SweepGradient.
    canvas.drawCircle(
      aim,
      16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = Colors.black.withValues(alpha: 0.3),
    );
    final ringRect = Rect.fromCircle(center: aim, radius: 15);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF8A8A),
          Color(0xFFFFD48A),
          Color(0xFFA8FF9E),
          Color(0xFF8AD1FF),
          Color(0xFFC29EFF),
          Color(0xFFFF8A8A),
        ],
      ).createShader(ringRect);
    canvas.drawCircle(aim, 15, ringPaint);
    // Chấm nhỏ ở tâm vòng giúp ngắm chính xác.
    canvas.drawCircle(aim, 2.5, Paint()..color = Colors.white);
```

Giữ nguyên: dấu +, nhánh `aligned` (vòng xanh xác nhận), biến `color` (vẫn dùng cho nhánh aligned). Nếu `color` không còn dùng ngoài nhánh aligned thì chuyển khai báo vào trong nhánh đó để analyze sạch. Cập nhật doc comment đầu class: "một vòng tròn cầu vồng đánh dấu điểm cần ngắm".

- [ ] **Step 4: Tạo frame_guide_overlay.dart**

```dart
import 'package:flutter/material.dart';

/// Khung bo góc viền gradient cầu vồng thể hiện vùng crop AI đề xuất
/// (kiểu Doka Cam). [rect] ở không gian 0..1 của viewfinder.
class FrameGuideOverlay extends StatelessWidget {
  const FrameGuideOverlay({
    super.key,
    required this.rect,
    this.opacity = 1,
  });

  final Rect rect;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: CustomPaint(
          painter: _FrameGuidePainter(rect),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _FrameGuidePainter extends CustomPainter {
  _FrameGuidePainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final px = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );
    final rrect = RRect.fromRectAndRadius(px, const Radius.circular(22));
    // Làm mờ nhẹ vùng ngoài khung để hút mắt vào vùng đề xuất.
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );
    // Viền cầu vồng.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF9E9E),
            Color(0xFFFFE29E),
            Color(0xFFB6FFAE),
            Color(0xFF9EDCFF),
            Color(0xFFD3B4FF),
          ],
        ).createShader(px),
    );
  }

  @override
  bool shouldRepaint(covariant _FrameGuidePainter oldDelegate) =>
      oldDelegate.rect != rect;
}
```

- [ ] **Step 5: Chạy test xác nhận pass**

Run: `flutter test test/guide_overlays_test.dart`
Expected: PASS 2/2.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze
git add lib/src/features/composition/composition_overlay.dart lib/src/features/composition/frame_guide_overlay.dart test/guide_overlays_test.dart
git commit -m "feat: vong ngam cau vong va khung crop de xuat (frame guide)"
```

---

### Task 5: Widget AiToastCard (toast giải thích của AI)

**Files:**
- Create: `lib/src/features/camera/widgets/ai_toast_card.dart`
- Test: `test/ai_toast_card_test.dart`

**Interfaces:**
- Consumes: không.
- Produces: `AiToastCard({required String message, Duration autoHideAfter = const Duration(seconds: 5)})` — tự thu gọn thành nút ↩ sau `autoHideAfter`, bấm nút để hiện lại; đổi `message` thì tự hiện lại. Task 6 đặt ở đỉnh viewfinder.

- [ ] **Step 1: Viết widget test fail**

Tạo `test/ai_toast_card_test.dart`:

```dart
import 'package:doka_app/src/features/camera/widgets/ai_toast_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('hiện message, tự thu gọn sau autoHideAfter, bấm ↩ hiện lại',
      (tester) async {
    await tester.pumpWidget(
      wrap(const AiToastCard(
        message: 'Phong cảnh đô thị — gợi ý Đà Lạt',
        autoHideAfter: Duration(seconds: 2),
      )),
    );
    expect(find.text('Phong cảnh đô thị — gợi ý Đà Lạt'), findsOneWidget);

    // Sau autoHide: text ẩn, còn nút hiện lại.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Phong cảnh đô thị — gợi ý Đà Lạt'), findsNothing);
    expect(find.byIcon(Icons.u_turn_left), findsOneWidget);

    // Bấm nút → hiện lại.
    await tester.tap(find.byIcon(Icons.u_turn_left));
    await tester.pumpAndSettle();
    expect(find.text('Phong cảnh đô thị — gợi ý Đà Lạt'), findsOneWidget);
    // Chạy hết timer còn treo để test kết thúc sạch.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('đổi message → tự hiện lại', (tester) async {
    await tester.pumpWidget(
      wrap(const AiToastCard(
        message: 'A',
        autoHideAfter: Duration(seconds: 1),
      )),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);

    await tester.pumpWidget(
      wrap(const AiToastCard(
        message: 'B',
        autoHideAfter: Duration(seconds: 1),
      )),
    );
    await tester.pump();
    expect(find.text('B'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
```

- [ ] **Step 2: Chạy test xác nhận fail**

Run: `flutter test test/ai_toast_card_test.dart`
Expected: FAIL compile — widget chưa tồn tại.

- [ ] **Step 3: Cài đặt widget**

Tạo `lib/src/features/camera/widgets/ai_toast_card.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

/// Thẻ thông báo của AI (kiểu Doka Cam): pill nền tối viền gradient nhẹ,
/// tự thu gọn thành nút ↩ sau [autoHideAfter]; bấm nút để đọc lại.
/// Đổi [message] → tự hiện lại từ đầu.
class AiToastCard extends StatefulWidget {
  const AiToastCard({
    super.key,
    required this.message,
    this.autoHideAfter = const Duration(seconds: 5),
  });

  final String message;
  final Duration autoHideAfter;

  @override
  State<AiToastCard> createState() => _AiToastCardState();
}

class _AiToastCardState extends State<AiToastCard> {
  bool _expanded = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant AiToastCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      setState(() => _expanded = true);
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.autoHideAfter, () {
      if (mounted) setState(() => _expanded = false);
    });
  }

  void _show() {
    setState(() => _expanded = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _expanded ? _buildCard() : _buildReopenButton(),
    );
  }

  Widget _buildCard() {
    return Container(
      key: const ValueKey('card'),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [
            Color(0x88FF9E9E),
            Color(0x88FFE29E),
            Color(0x889EDCFF),
            Color(0x88D3B4FF),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          widget.message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  Widget _buildReopenButton() {
    return Align(
      key: const ValueKey('reopen'),
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _show,
          child: const Padding(
            padding: EdgeInsets.all(7),
            child: Icon(Icons.u_turn_left, color: Colors.white70, size: 17),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Chạy test xác nhận pass**

Run: `flutter test test/ai_toast_card_test.dart`
Expected: PASS 2/2.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/camera/widgets/ai_toast_card.dart test/ai_toast_card_test.dart
git commit -m "feat: the thong bao AI tu thu gon (AiToastCard)"
```

---

### Task 6: Tích hợp vào CameraScreen (4 pha + auto-zoom + tự áp filter)

**Files:**
- Modify: `lib/src/features/camera/camera_screen.dart`

**Interfaces:**
- Consumes: `SceneAnalysis.cropRect/advice` (Task 1), `zoomForCrop` (Task 2), `AnalyzingSparkleOverlay` (Task 3), `FrameGuideOverlay` (Task 4), `AiToastCard` (Task 5), `mapImageRectToView` (geometry sẵn có).
- Produces: hành vi hoàn chỉnh — không API mới cho task khác.

Không có unit test khả thi cho phần này (phụ thuộc plugin camera); tiêu chí xanh là `flutter analyze` sạch + toàn bộ test cũ pass + checklist thử trên máy thật ở Step 8.

- [ ] **Step 1: Đổi enum và khai báo state mới**

Đầu file thêm import:

```dart
import '../composition/frame_guide_overlay.dart';
import '../composition/zoom_advisor.dart';
import 'widgets/ai_toast_card.dart';
import 'widgets/analyzing_sparkle_overlay.dart';
```

Đổi enum (dòng ~26) và cập nhật MỌI chỗ dùng `guiding` → `aiming` (2 chỗ: `_handleAnalyzingFrame` khi chốt chủ thể, `_onViewfinderLongPress` sau khi khoá tay):

```dart
/// Trạng thái AI bố cục: tắt → phân tích (giữ yên máy) → dẫn ngắm
/// (dấu + vào vòng cầu vồng) → khung crop + tự động zoom.
enum _CompositionPhase { off, analyzing, aiming, framing }
```

Class state: đổi `with WidgetsBindingObserver` thành `with WidgetsBindingObserver, TickerProviderStateMixin`, và thêm field (cạnh `_cloudTips`):

```dart
  Rect? _cloudCrop; // 0..1 viewfinder, đã map + clamp
  String? _cloudAdvice;
  String? _aiToast;
  bool _needMoreZoom = false;
  double _maxZoom = 1;
  AnimationController? _zoomAnimation;
```

- [ ] **Step 2: Quản lý vòng đời zoom**

Thêm 2 method (đặt gần `_resetAnalysisState`):

```dart
  void _stopZoomAnimation() {
    _zoomAnimation?.dispose();
    _zoomAnimation = null;
  }

  /// Dừng animation và trả zoom về 1 (khi thoát chế độ/flip camera).
  Future<void> _resetZoom() async {
    _stopZoomAnimation();
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.setZoomLevel(1);
      } on CameraException {
        // camera đang đóng — bỏ qua
      }
    }
  }
```

Cập nhật:
- `dispose()`: thêm `_stopZoomAnimation();` trước `super.dispose()`.
- `_resetAnalysisState()`: thêm cuối hàm `_cloudCrop = null; _cloudAdvice = null; _aiToast = null; _needMoreZoom = false; _stopZoomAnimation();`
- `_toggleComposition()` nhánh tắt: thêm `await _resetZoom();` ngay sau `await _pauseCompositionStream();`.
- `_startController()`: sau `await controller.initialize();` thêm:

```dart
      double maxZoom = 1;
      try {
        maxZoom = await controller.getMaxZoomLevel();
      } on CameraException {
        // giữ 1 — coi như không zoom được
      }
```

và trong `setState` cùng hàm thêm `_maxZoom = maxZoom;`.

- [ ] **Step 3: Phân tích trả về → áp filter + toast + map crop**

Viết lại phần thân `try` của `_runCloudCompositionAnalysis` (giữ nguyên chữ ký, token, finally). Thay từ dòng `final analysis = ...` đến hết `_cloudTips = analysis.tips;` bằng:

```dart
      final analysis = await ref
          .read(sceneAnalyzerProvider)
          .analyze(jpegBytes: bytes, filePath: shot.path);
      if (token != _compositionAnalyzeToken) return; // đã bị lần mới thay

      final camera = _cameras[_cameraIndex];
      final mirror = camera.lensDirection == CameraLensDirection.front;
      if (analysis.targetPoint != null || analysis.cropRect != null) {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final upright = img.bakeOrientation(decoded);
          final imageSize =
              Size(upright.width.toDouble(), upright.height.toDouble());
          final rawTarget = analysis.targetPoint;
          if (rawTarget != null) {
            final mapped = mapImagePointToView(
              point: rawTarget,
              imageSize: imageSize,
              viewAspect: _aspect.ratio,
              mirrorX: mirror,
            );
            _cloudTarget = Offset(
              mapped.dx.clamp(0.0, 1.0),
              mapped.dy.clamp(0.0, 1.0),
            );
          }
          final crop = analysis.cropRect;
          if (crop != null) {
            final mapped = mapImageRectToView(
              rect: Rect.fromLTWH(
                crop.left * imageSize.width,
                crop.top * imageSize.height,
                crop.width * imageSize.width,
                crop.height * imageSize.height,
              ),
              imageSize: imageSize,
              viewAspect: _aspect.ratio,
              mirrorX: mirror,
            );
            final clamped = Rect.fromLTRB(
              mapped.left.clamp(0.0, 1.0),
              mapped.top.clamp(0.0, 1.0),
              mapped.right.clamp(0.0, 1.0),
              mapped.bottom.clamp(0.0, 1.0),
            );
            // Crop quá bé sau clamp = vùng đề xuất nằm ngoài phần nhìn thấy.
            if (clamped.width > 0.05 && clamped.height > 0.05) {
              _cloudCrop = clamped;
            }
          }
          // Không có điểm ngắm riêng → ngắm vào tâm vùng crop.
          _cloudTarget ??= _cloudCrop?.center;
        }
      }
      _cloudTips = analysis.tips;
      _cloudAdvice = analysis.advice;

      // Tự áp filter đề xuất + toast giải thích (kiểu Doka).
      final presetIdx =
          filmPresets.indexWhere((p) => p.id == analysis.presetId);
      if (mounted) {
        setState(() {
          if (presetIdx >= 0) _presetIndex = presetIdx;
          _aiToast = _buildFilterToast(analysis, presetIdx);
        });
      }
```

Thêm helper (đặt ngay dưới `_runCloudCompositionAnalysis`):

```dart
  /// Ghép câu giải thích: "«mood» — gợi ý «filter», «reason»".
  String? _buildFilterToast(SceneAnalysis analysis, int presetIdx) {
    if (presetIdx < 0) return null;
    final name = filmPresets[presetIdx].name;
    final parts = <String>[
      if (analysis.mood != null && analysis.mood!.isNotEmpty) analysis.mood!,
      'gợi ý filter $name',
      if (analysis.reason != null && analysis.reason!.isNotEmpty)
        analysis.reason!,
    ];
    return parts.join(' — ');
  }
```

Lưu ý: import `mapImageRectToView`/`mapImagePointToView` đến từ `composition_advisor.dart` (đã import sẵn trong file).

- [ ] **Step 4: Chuyển pha aiming → framing khi căn trúng + auto-zoom**

Trong `_handleAnalyzingFrame`, thay `_compositionPhase = _CompositionPhase.guiding;` bằng `.aiming`, và thay khối `_showMessage('Đã tìm điểm chụp đẹp — $tip');` bằng:

```dart
    // Nếu chưa có toast từ Gemini (offline) thì dùng tip rule-based.
    if (_aiToast == null) {
      final tip = _cloudTips.isNotEmpty
          ? _cloudTips.first
          : 'Di máy cho dấu + vào vòng tròn màu.';
      setState(() => _aiToast = tip);
    }
```

Trong `_handleGuidingFrame`, thay:

```dart
    if (advice.isAligned && !_wasAligned) {
      HapticFeedback.lightImpact();
    }
```

bằng:

```dart
    if (advice.isAligned && !_wasAligned) {
      HapticFeedback.lightImpact();
      if (_compositionPhase == _CompositionPhase.aiming && _cloudCrop != null) {
        _enterFraming();
      }
    }
```

Thêm 2 method mới (đặt dưới `_handleGuidingFrame`):

```dart
  /// Vào pha khung crop: hiện khung cầu vồng, toast lời khuyên, zoom mượt.
  void _enterFraming() {
    _compositionPhase = _CompositionPhase.framing;
    if (_cloudAdvice != null) _aiToast = _cloudAdvice;
    _startAutoZoom();
  }

  void _startAutoZoom() {
    final crop = _cloudCrop;
    if (_controller == null || crop == null) return;
    final side = math.max(crop.width, crop.height);
    final target = zoomForCrop(crop, maxZoom: _maxZoom);
    // Vùng crop cần zoom sâu hơn máy hỗ trợ → nhắc người dùng lại gần.
    _needMoreZoom = side > 0 && 1 / side > _maxZoom + 0.01;
    if (target <= 1.01) {
      if (mounted) setState(() {});
      return;
    }
    _stopZoomAnimation();
    final anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _zoomAnimation = anim;
    final zoom = Tween<double>(begin: 1, end: target).animate(
      CurvedAnimation(parent: anim, curve: Curves.easeInOut),
    );
    anim.addListener(() {
      final controller = _controller;
      if (controller == null) return;
      controller.setZoomLevel(zoom.value).catchError((_) {});
      if (mounted) setState(() {});
    });
    anim.forward();
  }
```

Thêm import đầu file: `import 'dart:math' as math;`.

Trong `_capture()`, ngay sau `setState(() => _processing = true);` thêm:

```dart
    _zoomAnimation?.stop(); // chụp giữa chừng zoom: giữ mức hiện tại
```

Trong `_handleGuidingFrame` nhánh mất dấu chủ thể (đầu hàm), sau `_wasAligned = false;` thêm `_zoomAnimation?.stop();`.

- [ ] **Step 5: Cập nhật UI viewfinder**

Trong `_buildViewfinderStack()`:

1. Thay banner analyzing hiện tại (khối `if (_compositionPhase == _CompositionPhase.analyzing) Positioned(...)` với `CircularProgressIndicator` + text "Giữ nguyên máy...") — GIỮ nguyên khối này nhưng đổi text thành `'AI đang phân tích — giữ yên máy…'`.
2. Thêm ngay TRƯỚC khối banner đó:

```dart
            if (_compositionPhase == _CompositionPhase.analyzing)
              const AnalyzingSparkleOverlay(),
            if (_compositionPhase == _CompositionPhase.framing &&
                _cloudCrop != null)
              FrameGuideOverlay(
                rect: _cloudCrop!,
                opacity:
                    (1 - (_zoomAnimation?.value ?? 0)).clamp(0.0, 1.0),
              ),
```

3. Thêm sau khối banner analyzing (toast AI — không hiện khi đang analyzing để khỏi đè banner):

```dart
            if (_aiToast != null &&
                _compositionPhase != _CompositionPhase.off &&
                _compositionPhase != _CompositionPhase.analyzing)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: AiToastCard(message: _aiToast!),
              ),
            if (_compositionPhase == _CompositionPhase.framing &&
                _needMoreZoom)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '✨ Tiến lại gần hoặc zoom thêm',
                      style: TextStyle(color: Colors.white, fontSize: 12.5),
                    ),
                  ),
                ),
              ),
```

4. `_toggleComposition()` nhánh bật: xoá dòng `_showMessage('Đang phân tích khung hình — giữ nguyên máy…');` (banner + sparkle đã nói điều này).

- [ ] **Step 6: Analyze + toàn bộ test**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: PASS toàn bộ (test cũ + mới, không test nào đụng camera plugin).

- [ ] **Step 7: Commit**

```bash
git add lib/src/features/camera/camera_screen.dart
git commit -m "feat: luong guided AI composition 4 pha kieu Doka (sparkle, vong cau vong, khung crop, auto-zoom, tu ap filter)"
```

- [ ] **Step 8: Checklist thử trên máy thật (ghi lại kết quả, không chặn merge code)**

Chạy `flutter run --dart-define=GEMINI_API_KEY=<key>` trên Android thật:

1. Bấm ⊹ → thấy chấm sáng gom về lưới + banner "AI đang phân tích".
2. Khi Gemini trả về: filter đổi + toast giải thích hiện ở đỉnh, tự thu gọn sau 5s, bấm ↩ hiện lại.
3. Vòng cầu vồng hiện tại điểm đề xuất; di máy cho dấu + vào vòng → haptic.
4. Căn trúng → khung cầu vồng hiện rồi mờ dần, camera zoom mượt; toast đổi sang lời khuyên bố cục.
5. Crop đòi zoom sâu hơn max máy → chip "Tiến lại gần hoặc zoom thêm".
6. Chụp giữa lúc zoom → ảnh lưu ở mức zoom hiện tại, không crash.
7. Thoát ⊹ / flip camera → zoom về 1, overlay biến mất.
8. Tắt mạng → luồng cũ chạy: vòng cầu vồng với điểm hình học, toast là tip rule-based, KHÔNG có pha framing.

---

### Task 7: Cập nhật tài liệu (PLAN.md + README)

**Files:**
- Modify: `PLAN.md` (mục Giai đoạn 3)
- Modify: `README.md` (mục AI phân tích ảnh)

**Interfaces:** không.

- [ ] **Step 1: Ghi nhận tính năng vào PLAN.md**

Trong `PLAN.md` §3 "Giai đoạn 3 — AI Composition", thêm bullet sau dòng v1 rule-based:

```markdown
- ✅ v1.5 guided shot kiểu Doka (đã code xong, chờ test máy thật): 4 pha off→analyzing→aiming→framing — hiệu ứng chấm sáng phân tích, vòng ngắm cầu vồng, khung crop Gemini + tự động zoom (căn tâm trước, zoom sau), tự áp filter kèm toast giải thích. Spec: docs/superpowers/specs/2026-07-06-guided-ai-composition-design.md.
```

Và trong danh sách "giả định phải kiểm chứng trên máy thật" (Giai đoạn 3) thêm:

```markdown
- ⚠️ Giả định thứ 4 (mới): cropRect Gemini trả về khớp vùng nhìn thấy sau center-crop preview; toán map nằm trong _runCloudCompositionAnalysis → mapImageRectToView.
```

- [ ] **Step 2: Cập nhật README**

Trong `README.md` mục "AI phân tích ảnh (Gemini)", thêm sau đoạn mô tả đầu:

```markdown
Chế độ AI bố cục (nút ⊹) dẫn dắt theo 4 bước kiểu guided-shot: phân tích
cảnh → ngắm theo vòng tròn màu → khung crop đề xuất + tự động zoom → tự áp
filter kèm giải thích. Offline vẫn dùng được với dẫn hướng hình học.
```

- [ ] **Step 3: Commit**

```bash
git add PLAN.md README.md
git commit -m "docs: ghi nhan guided AI composition vao PLAN va README"
```
