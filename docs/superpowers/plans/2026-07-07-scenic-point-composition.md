# Scenic Point Composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cho AI bố cục: người dùng chạm để chọn chủ thể; nếu không chọn, hiện một nốt tròn tĩnh tại "điểm cảnh đẹp nhất" mà Gemini chỉ ra trong khung hình.

**Architecture:** Gemini vẫn được gọi 1 lần khi bấm ⊹, nhưng trả thêm toạ độ `scenicX/scenicY` (điểm cảnh đẹp có sẵn trong ảnh) bên cạnh `targetX/targetY` (nơi đặt chủ thể). Thêm pha `point` vào máy trạng thái bố cục: khi không có chủ thể được chạm chọn, vẽ nốt tròn tĩnh tại điểm cảnh đẹp. Việc chọn/bỏ chủ thể chuyển từ long-press sang tap; bỏ cơ chế tự phát hiện chủ thể sau 3 frame.

**Tech Stack:** Flutter/Dart, Riverpod, `camera`, `google_mlkit_object_detection`, `image`, Gemini 2.5 Flash REST.

## Global Constraints

- Ngôn ngữ hiển thị: **tiếng Việt** (mọi chuỗi UI/thông báo).
- Gemini chỉ được gọi **1 lần** cho mỗi lần bấm ⊹ (không thêm request).
- `sceneResponseSchema.required` giữ nguyên `['presetId']` — `scenicX/scenicY` là tuỳ chọn.
- Toạ độ điểm luôn ở dạng số thực trong `[0,1]`, gốc `(0,0)` góc trên-trái, không gian ảnh tĩnh.
- Cổng xác minh cuối mỗi task: `flutter analyze` không lỗi/không warning mới, và `flutter test` xanh.

---

## File Structure

- `lib/src/features/analysis/scene_analysis.dart` — model `SceneAnalysis`, thêm field `scenicPoint`.
- `lib/src/features/analysis/gemini_prompt.dart` — schema, prompt, `parseGeminiJson`; thêm `scenicX/scenicY`.
- `lib/src/features/composition/composition_overlay.dart` — vẽ nốt tròn tĩnh + gợi ý lưới 1/3.
- `lib/src/features/camera/camera_screen.dart` — pha `point`, cử chỉ tap, map điểm cảnh, gỡ auto-detect & long-press.
- `test/gemini_prompt_test.dart` — test parse `scenic*`.
- `test/composition_overlay_test.dart` (mới) — widget smoke test overlay.

---

## Task 1: Gemini trả thêm điểm cảnh đẹp (scenicPoint)

**Files:**
- Modify: `lib/src/features/analysis/scene_analysis.dart`
- Modify: `lib/src/features/analysis/gemini_prompt.dart`
- Test: `test/gemini_prompt_test.dart`

**Interfaces:**
- Consumes: `parseGeminiJson(Map<String,dynamic> json, {required List<String> validIds, bool fromCloud})` (đã có).
- Produces:
  - `SceneAnalysis.scenicPoint` → `Offset?` (điểm cảnh đẹp, 0..1 không gian ảnh, null nếu thiếu/không hợp lệ).
  - `sceneResponseSchema` có thêm khoá `scenicX`, `scenicY` kiểu `NUMBER`.
  - `buildScenePrompt` chứa chuỗi con `scenicX`.

- [ ] **Step 1: Viết test thất bại** — thêm vào cuối `test/gemini_prompt_test.dart` (trước dấu `}` đóng `main`):

```dart
  test('prompt có mô tả điểm cảnh đẹp scenicX', () {
    final prompt = buildScenePrompt(filmPresets);
    expect(prompt.contains('scenicX'), isTrue);
  });

  test('parse scenicX/scenicY hợp lệ thành scenicPoint', () {
    final a = parseGeminiJson({
      'presetId': 'dalat',
      'scenicX': 0.25,
      'scenicY': 0.75,
    }, validIds: ids);
    expect(a.scenicPoint, const Offset(0.25, 0.75));
  });

  test('thiếu scenic toạ độ → scenicPoint null', () {
    final a = parseGeminiJson({'presetId': 'dalat'}, validIds: ids);
    expect(a.scenicPoint, isNull);
  });

  test('scenic toạ độ ngoài [0,1] bị loại', () {
    final a = parseGeminiJson(
      {'presetId': 'dalat', 'scenicX': -0.1, 'scenicY': 0.5},
      validIds: ids,
    );
    expect(a.scenicPoint, isNull);
  });
```

- [ ] **Step 2: Chạy test để xác nhận thất bại**

Run: `flutter test test/gemini_prompt_test.dart`
Expected: FAIL — `The getter 'scenicPoint' isn't defined` và test prompt scenicX fail.

- [ ] **Step 3: Thêm field vào model** — sửa `lib/src/features/analysis/scene_analysis.dart`, thêm tham số + field `scenicPoint`:

Trong constructor (sau `this.targetPoint,`):
```dart
    this.scenicPoint,
```
Sau khối doc + field `targetPoint` (sau dòng `final Offset? targetPoint;`):
```dart

  /// Điểm mà cảnh vật tại đó đẹp/thu hút nhất trong khung, 0..1 không gian
  /// ảnh (gốc trên-trái). Dùng khi người dùng không chọn chủ thể. Có thể null.
  final Offset? scenicPoint;
```

- [ ] **Step 4: Thêm schema + prompt + parse** — sửa `lib/src/features/analysis/gemini_prompt.dart`.

Trong `sceneResponseSchema['properties']`, thêm sau `'targetY': {'type': 'NUMBER'},`:
```dart
    'scenicX': {'type': 'NUMBER'},
    'scenicY': {'type': 'NUMBER'},
```

Trong `buildScenePrompt`, thêm dòng vào chuỗi mô tả (sau dòng `- targetX, targetY: ...`):
```
- scenicX, scenicY: điểm mà CẢNH VẬT TẠI ĐÓ đẹp/thu hút nhất trong khung (điểm nhấn có sẵn trong ảnh — ví dụ ánh sáng đẹp, chi tiết nổi bật, phản chiếu...), số thực 0..1 (gốc 0,0 ở góc trên-trái).
```

Trong `parseGeminiJson`, sau khối tính `target` (sau dòng `}` đóng `if (tx != null ...)`), thêm:
```dart
  Offset? scenic;
  final sx = (json['scenicX'] as num?)?.toDouble();
  final sy = (json['scenicY'] as num?)?.toDouble();
  if (sx != null && sy != null && sx >= 0 && sx <= 1 && sy >= 0 && sy <= 1) {
    scenic = Offset(sx, sy);
  }
```

Trong `return SceneAnalysis(...)`, thêm sau `targetPoint: target,`:
```dart
    scenicPoint: scenic,
```

- [ ] **Step 5: Chạy test để xác nhận đạt**

Run: `flutter test test/gemini_prompt_test.dart`
Expected: PASS (mọi test, gồm 4 test mới).

- [ ] **Step 6: Lint**

Run: `flutter analyze lib/src/features/analysis`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/src/features/analysis/scene_analysis.dart lib/src/features/analysis/gemini_prompt.dart test/gemini_prompt_test.dart
git commit -m "feat: Gemini tra them diem canh dep nhat (scenicPoint)"
```

---

## Task 2: Overlay vẽ nốt tròn tĩnh + gợi ý lưới 1/3

**Files:**
- Modify: `lib/src/features/composition/composition_overlay.dart`
- Test: `test/composition_overlay_test.dart` (create)

**Interfaces:**
- Consumes: `CompositionAdvice` (đã có), `thirdsPoints` từ `composition_advisor.dart` (đã có).
- Produces: `CompositionOverlay({Key? key, CompositionAdvice? advice, Offset? scenicPoint, bool showThirdsHint = false})`.
  - `advice != null` → vẽ dẫn ngắm (dấu + + nốt đích) như cũ.
  - `advice == null && scenicPoint != null` → vẽ nốt tròn tĩnh tại `scenicPoint` (0..1 viewfinder).
  - `advice == null && scenicPoint == null && showThirdsHint` → vẽ mờ 4 giao điểm 1/3.

- [ ] **Step 1: Viết test thất bại** — tạo `test/composition_overlay_test.dart`:

```dart
import 'package:doka_app/src/features/composition/composition_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, height: 400, child: child),
        ),
      );

  testWidgets('vẽ nốt tròn tĩnh khi có scenicPoint, không advice',
      (tester) async {
    await tester.pumpWidget(
      wrap(const CompositionOverlay(scenicPoint: Offset(0.5, 0.5))),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('vẽ gợi ý lưới 1/3 khi showThirdsHint và không có điểm',
      (tester) async {
    await tester.pumpWidget(
      wrap(const CompositionOverlay(showThirdsHint: true)),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
```

- [ ] **Step 2: Chạy test để xác nhận thất bại**

Run: `flutter test test/composition_overlay_test.dart`
Expected: FAIL — `No named parameter with the name 'scenicPoint'`.

- [ ] **Step 3: Cập nhật widget** — thay `lib/src/features/composition/composition_overlay.dart` bằng:

```dart
import 'package:flutter/material.dart';

import 'composition_advisor.dart';

/// Overlay bố cục. Ba chế độ vẽ:
/// - [advice] != null: dẫn ngắm (dấu + giữa + nốt tròn đích) — có chủ thể.
/// - [advice] == null & [scenicPoint] != null: nốt tròn tĩnh tại điểm cảnh
///   đẹp nhất (0..1 viewfinder) — không chủ thể, còn mạng.
/// - [advice] == null & [scenicPoint] == null & [showThirdsHint]: mờ 4 giao
///   điểm 1/3 — không chủ thể, offline.
class CompositionOverlay extends StatelessWidget {
  const CompositionOverlay({
    super.key,
    this.advice,
    this.scenicPoint,
    this.showThirdsHint = false,
  });

  final CompositionAdvice? advice;
  final Offset? scenicPoint;
  final bool showThirdsHint;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CompositionPainter(advice, scenicPoint, showThirdsHint),
        size: Size.infinite,
      ),
    );
  }
}

class _CompositionPainter extends CustomPainter {
  _CompositionPainter(this.advice, this.scenicPoint, this.showThirdsHint);

  final CompositionAdvice? advice;
  final Offset? scenicPoint;
  final bool showThirdsHint;

  @override
  void paint(Canvas canvas, Size size) {
    final a = advice;
    if (a != null) {
      _paintGuiding(canvas, size, a);
      return;
    }
    final sp = scenicPoint;
    if (sp != null) {
      _paintDot(canvas, Offset(sp.dx * size.width, sp.dy * size.height));
      return;
    }
    if (showThirdsHint) {
      final paint = Paint()..color = Colors.white.withValues(alpha: 0.35);
      for (final p in thirdsPoints) {
        canvas.drawCircle(
            Offset(p.dx * size.width, p.dy * size.height), 5, paint);
      }
    }
  }

  /// Nốt tròn nổi trên mọi nền: lõi đặc + viền tối + vòng ngoài mờ.
  void _paintDot(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 9, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(c, 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  void _paintGuiding(Canvas canvas, Size size, CompositionAdvice a) {
    final aligned = a.isAligned;
    final color = aligned
        ? Colors.greenAccent
        : (a.isLocked ? Colors.amber : Colors.white);

    // Dấu + cố định giữa màn hình.
    final center = Offset(size.width / 2, size.height / 2);
    final crossPaint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = aligned ? Colors.greenAccent : Colors.white.withValues(alpha: 0.9);
    const arm = 11.0;
    canvas.drawLine(
        center - const Offset(arm, 0), center + const Offset(arm, 0), crossPaint);
    canvas.drawLine(
        center - const Offset(0, arm), center + const Offset(0, arm), crossPaint);

    final aim = Offset(
      (a.aimPoint.dx.clamp(0.04, 0.96)) * size.width,
      (a.aimPoint.dy.clamp(0.04, 0.96)) * size.height,
    );

    if (aligned) {
      canvas.drawCircle(
        center,
        18,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color,
      );
      return;
    }

    canvas.drawCircle(aim, 9, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(aim, 7, Paint()..color = color);
    canvas.drawCircle(
      aim,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _CompositionPainter oldDelegate) =>
      oldDelegate.advice != advice ||
      oldDelegate.scenicPoint != scenicPoint ||
      oldDelegate.showThirdsHint != showThirdsHint;
}
```

- [ ] **Step 4: Chạy test để xác nhận đạt**

Run: `flutter test test/composition_overlay_test.dart`
Expected: PASS (2 test).

- [ ] **Step 5: Lint**

Run: `flutter analyze lib/src/features/composition/composition_overlay.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/composition/composition_overlay.dart test/composition_overlay_test.dart
git commit -m "feat: overlay ve not tron tinh + goi y luoi 1/3"
```

---

## Task 3: camera_screen — pha `point`, chạm chọn chủ thể, map điểm cảnh

**Files:**
- Modify: `lib/src/features/camera/camera_screen.dart`

**Interfaces:**
- Consumes: `SceneAnalysis.scenicPoint`, `CompositionOverlay(scenicPoint:, showThirdsHint:)`, `mapImagePointToView`, `mapViewPointToImage`, `adviseComposition`, `SubjectDetector.lockAt/unlock/lastImageSize` (đã có).
- Produces: hành vi mới trong widget (không có API xuất ra ngoài).

> **Ghi chú xác minh:** Logic pha/stream của `camera_screen` gắn chặt với `CameraController` + image stream nên không unit-test được trong repo này (đúng theo hiện trạng: chỉ các hàm thuần trong `analysis/` và `composition/` có test). Task này xác minh bằng `flutter analyze` + `flutter test` (không hồi quy) + **checklist thủ công trên thiết bị** ở Step cuối.

- [ ] **Step 1: Thêm pha `point` vào enum** — sửa dòng `enum _CompositionPhase { off, analyzing, guiding }` thành:

```dart
enum _CompositionPhase { off, analyzing, point, guiding }
```

Và cập nhật doc ngay trên đó:
```dart
/// Trạng thái AI bố cục: tắt → đang phân tích (Gemini 1 lần) → hiện điểm cảnh
/// đẹp (không chủ thể) hoặc dẫn hướng (đã chạm chọn chủ thể).
```

- [ ] **Step 2: Thêm biến trạng thái, bỏ biến auto-detect** — trong danh sách field của `_CameraScreenState`:

Xoá 3 dòng:
```dart
  int? _candidateId;
  int _candidateFrames = 0;
  bool _manualLock = false;
```
Thêm (đặt cạnh `_cloudTarget`):
```dart
  Offset? _scenicTarget;
```

- [ ] **Step 3: Cập nhật `_resetAnalysisState`** — thay thân hàm thành:

```dart
  void _resetAnalysisState() {
    _fixedTarget = null;
    _lostNotified = false;
    _wasAligned = false;
    _advice = null;
    _cloudTarget = null;
    _scenicTarget = null;
    _cloudResolved = true;
    _cloudTips = const [];
  }
```

- [ ] **Step 4: Map cả điểm cảnh trong `_runCloudCompositionAnalysis`** — trong hàm này:

Sau dòng `_cloudTarget = null;` (đầu hàm) thêm:
```dart
    _scenicTarget = null;
```

Thay khối từ `final rawTarget = analysis.targetPoint;` đến hết khối `if (rawTarget != null) { ... }` bằng:
```dart
      final rawTarget = analysis.targetPoint;
      final rawScenic = analysis.scenicPoint;
      if (rawTarget != null || rawScenic != null) {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final upright = img.bakeOrientation(decoded);
          final imageSize =
              Size(upright.width.toDouble(), upright.height.toDouble());
          final camera = _cameras[_cameraIndex];
          final mirror = camera.lensDirection == CameraLensDirection.front;
          Offset mapPoint(Offset p) {
            final m = mapImagePointToView(
              point: p,
              imageSize: imageSize,
              viewAspect: _aspect.ratio,
              mirrorX: mirror,
            );
            return Offset(m.dx.clamp(0.0, 1.0), m.dy.clamp(0.0, 1.0));
          }

          if (rawTarget != null) _cloudTarget = mapPoint(rawTarget);
          if (rawScenic != null) _scenicTarget = mapPoint(rawScenic);
        }
      }
```

- [ ] **Step 5: Chuyển sang pha `point` sau khi phân tích xong** — trong `_toggleComposition`, thay khối:

```dart
    _showMessage('Đang phân tích khung hình — giữ nguyên máy…');
    await _runCloudCompositionAnalysis();
    if (mounted) setState(() {});
```
bằng:
```dart
    _showMessage('Đang phân tích khung hình — giữ nguyên máy…');
    await _runCloudCompositionAnalysis();
    if (!mounted) return;
    // Người dùng có thể đã chạm chọn chủ thể trong lúc phân tích → khi đó đã
    // ở pha guiding, không ghi đè.
    if (_compositionPhase == _CompositionPhase.analyzing) {
      setState(() => _compositionPhase = _CompositionPhase.point);
      if (_scenicTarget != null) {
        final tip =
            _cloudTips.isNotEmpty ? _cloudTips.first : 'Đặt điểm nhấn vào đây.';
        _showMessage('Điểm cảnh đẹp nhất đây — $tip Chạm vào chủ thể nếu muốn bám theo.');
      } else {
        _showMessage(
            'Chưa tìm được điểm đẹp (cần mạng). Dùng lưới 1/3 hoặc chạm chọn chủ thể.');
      }
    } else {
      setState(() {});
    }
```

- [ ] **Step 6: Bỏ auto-detect, chỉ xử lý frame khi guiding** — thay `_onFrame` `.then(...)` để không gọi `_handleAnalyzingFrame` nữa:

Thay khối trong `.then((result) { ... })`:
```dart
      if (!mounted ||
          _compositionPhase == _CompositionPhase.off ||
          result.skipped) {
        return;
      }
      if (_compositionPhase == _CompositionPhase.analyzing) {
        _handleAnalyzingFrame(result.subject, camera);
      } else {
        _handleGuidingFrame(result.subject, camera);
      }
```
bằng:
```dart
      if (!mounted ||
          _compositionPhase == _CompositionPhase.off ||
          result.skipped) {
        return;
      }
      // Detector.process (ở trên) đã cập nhật _lastObjects cho việc chạm chọn.
      // Chỉ pha guiding mới bám theo chủ thể đã khoá theo từng frame.
      if (_compositionPhase == _CompositionPhase.guiding) {
        _handleGuidingFrame(result.subject, camera);
      }
```

- [ ] **Step 7: Xoá `_handleAnalyzingFrame`** — xoá toàn bộ hàm `_handleAnalyzingFrame(...)` (khối doc `/// Pha phân tích: ...` + thân hàm).

- [ ] **Step 8: Cập nhật `_handleGuidingFrame`** — thay toàn bộ hàm bằng:

```dart
  /// Pha dẫn hướng: bám chủ thể đã chạm chọn; mất dấu → về hiện điểm cảnh đẹp.
  void _handleGuidingFrame(
      SubjectDetection? subject, CameraDescription camera) {
    if (subject == null || !subject.isLocked) {
      _fixedTarget = null;
      _compositionPhase = _CompositionPhase.point;
      _wasAligned = false;
      setState(() => _advice = null);
      if (!_lostNotified) {
        _lostNotified = true;
        _showMessage('Mất dấu chủ thể — hiện điểm cảnh đẹp. Chạm lại để chọn.');
      }
      return;
    }
    _lostNotified = false;
    final viewRect = _subjectViewRect(subject, camera);
    // Chốt đích MỘT LẦN, và chỉ khi Gemini đã trả lời (tránh chốt nhầm hình học
    // khi cloud chưa xong).
    if (_fixedTarget == null && _cloudResolved) {
      _fixedTarget = _cloudTarget ?? adviseComposition(viewRect).target;
    }
    if (_fixedTarget == null) return; // chờ Gemini
    final advice = adviseComposition(
      viewRect,
      isLocked: true,
      fixedTarget: _fixedTarget,
    );
    if (advice.isAligned && !_wasAligned) {
      HapticFeedback.lightImpact();
    }
    _wasAligned = advice.isAligned;
    setState(() => _advice = advice);
  }
```

- [ ] **Step 9: Thay long-press bằng tap** — thay hàm `_onViewfinderLongPress` bằng `_onViewfinderTap`:

```dart
  /// Chạm trên viewfinder: chạm trúng vật thể → khoá làm chủ thể (pha guiding);
  /// chạm vùng trống → bỏ chủ thể, quay về hiện điểm cảnh đẹp (pha point).
  void _onViewfinderTap(Offset localPosition, Size viewSize) {
    final detector = _subjectDetector;
    if (_compositionPhase == _CompositionPhase.off || detector == null) return;
    if (detector.lastImageSize == Size.zero) return;
    final camera = _cameras[_cameraIndex];
    final imagePoint = mapViewPointToImage(
      point: Offset(
        localPosition.dx / viewSize.width,
        localPosition.dy / viewSize.height,
      ),
      imageSize: detector.lastImageSize,
      viewAspect: _aspect.ratio,
      mirrorX: camera.lensDirection == CameraLensDirection.front,
    );
    final locked = detector.lockAt(imagePoint);
    HapticFeedback.selectionClick();
    if (locked) {
      _fixedTarget = null; // chốt lại đích cho chủ thể mới ở frame kế
      _lostNotified = false;
      _wasAligned = false;
      setState(() => _compositionPhase = _CompositionPhase.guiding);
      _showMessage('Đã chọn chủ thể — di máy cho dấu + trùng nốt tròn.');
    } else if (_compositionPhase == _CompositionPhase.guiding) {
      detector.unlock();
      _fixedTarget = null;
      _wasAligned = false;
      setState(() {
        _advice = null;
        _compositionPhase = _CompositionPhase.point;
      });
      _showMessage('Đã bỏ chủ thể — hiện điểm cảnh đẹp.');
    }
  }
```

- [ ] **Step 10: Đổi GestureDetector sang onTapUp** — trong `_buildViewfinder`, thay:

```dart
          builder: (context, constraints) => GestureDetector(
            onLongPressStart: (details) => _onViewfinderLongPress(
              details.localPosition,
              constraints.biggest,
            ),
            child: _buildViewfinderStack(),
          ),
```
bằng:
```dart
          builder: (context, constraints) => GestureDetector(
            onTapUp: (details) => _onViewfinderTap(
              details.localPosition,
              constraints.biggest,
            ),
            child: _buildViewfinderStack(),
          ),
```

- [ ] **Step 11: Cập nhật render overlay theo pha** — trong `_buildViewfinderStack`, thay:

```dart
            if (_compositionPhase != _CompositionPhase.off)
              CompositionOverlay(advice: _advice),
```
bằng:
```dart
            if (_compositionPhase == _CompositionPhase.guiding)
              CompositionOverlay(advice: _advice),
            if (_compositionPhase == _CompositionPhase.point)
              CompositionOverlay(
                scenicPoint: _scenicTarget,
                showThirdsHint: _scenicTarget == null,
              ),
```

- [ ] **Step 12: Lint + test hồi quy**

Run: `flutter analyze`
Expected: `No issues found!` (không lỗi/warning mới; nếu báo `_candidateId`/`_manualLock`/`_handleAnalyzingFrame`/`_onViewfinderLongPress` không dùng hoặc không tồn tại → còn sót tham chiếu, sửa cho hết).

Run: `flutter test`
Expected: mọi test xanh (không hồi quy).

- [ ] **Step 13: Kiểm thử thủ công trên thiết bị (có GEMINI_API_KEY)** — xác nhận từng mục:

```
Run: flutter run --dart-define=GEMINI_API_KEY=<key>
1. Bấm ⊹ (còn mạng), KHÔNG chạm gì → sau vài giây hiện 1 nốt tròn tĩnh
   tại điểm cảnh đẹp + thông báo "Điểm cảnh đẹp nhất đây…". [point]
2. Chạm vào một vật thể → nốt tròn đích + dấu + xuất hiện, di máy cho trùng
   → chuyển xanh + rung nhẹ. [guiding]
3. Chạm vùng trống khi đang guiding → quay lại nốt tròn tĩnh. [point]
4. Che/đưa chủ thể ra khỏi khung khi guiding → tự về nốt tròn tĩnh + báo
   "Mất dấu chủ thể…". [point]
5. Bật chế độ máy bay (offline) rồi bấm ⊹, không chạm → hiện mờ 4 giao điểm
   1/3 + báo "cần mạng…". [point offline]
6. Bấm ⊹ lần nữa → tắt overlay. [off]
```

- [ ] **Step 14: Commit**

```bash
git add lib/src/features/camera/camera_screen.dart
git commit -m "feat: cham chon chu the + not tron diem canh dep khi khong chon"
```

---

## Self-Review

**Spec coverage:**
- Máy trạng thái 4 pha → Task 3 Step 1–5, 11. ✅
- Bỏ auto-detect 3 frame → Task 3 Step 6–7. ✅
- Bỏ long-press, gom về tap → Task 3 Step 9–10. ✅
- Chạm trúng vật → guiding; chạm trống → point; mất dấu → point → Task 3 Step 8–9. ✅
- 2 điểm Gemini (`targetX/Y` + `scenicX/Y`) 1 lần gọi → Task 1. ✅
- `SceneAnalysis.scenicPoint` + parse → Task 1. ✅
- Overlay nốt tròn tĩnh cho point → Task 2 + Task 3 Step 11. ✅
- Dự phòng offline: có chủ thể → hình học (giữ nguyên trong `_handleGuidingFrame`); không chủ thể → mờ lưới 1/3 → Task 2 + Task 3 Step 11, 13. ✅
- Prompt mô tả scenic → Task 1 Step 4. ✅

**Placeholder scan:** không có TBD/TODO; mọi step có mã cụ thể.

**Type consistency:** `scenicPoint: Offset?` nhất quán giữa Task 1 (model/parse) và Task 3 (đọc `analysis.scenicPoint`, biến `_scenicTarget: Offset?`). `CompositionOverlay(advice:, scenicPoint:, showThirdsHint:)` khớp giữa Task 2 (định nghĩa) và Task 3 Step 11 (dùng). `adviseComposition(viewRect, isLocked:, fixedTarget:)` khớp chữ ký hiện có.
