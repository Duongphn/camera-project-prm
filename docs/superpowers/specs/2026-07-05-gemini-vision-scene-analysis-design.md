# Thiết kế: Phân tích ảnh chi tiết bằng Gemini Vision (gợi ý filter + bố cục)

- Ngày: 2026-07-05
- Trạng thái: chờ duyệt
- Phạm vi: thêm một lớp phân tích ảnh bằng vision LLM (Google Gemini) để
  gợi ý filter chính xác hơn và chốt điểm bố cục "đẹp nhất", giữ nguyên
  toàn bộ trải nghiệm realtime và khả năng chạy offline.

## 1. Bối cảnh & mục tiêu

Hiện tại app phân tích ảnh hoàn toàn on-device bằng Google ML Kit:

- **Gợi ý filter** (`lib/src/features/suggestion/filter_suggester.dart`):
  ML Kit Image Labeling cho vài nhãn cảnh thô + độ sáng trung bình, rồi map
  sang preset bằng luật cứng trong `suggestion_rules.dart`.
- **Bố cục** (`lib/src/features/composition/subject_detector.dart` +
  `composition_advisor.dart`): ML Kit Object Detection (stream) tìm chủ thể;
  điểm đích được tính 1 lần bằng rule-of-thirds/tâm khung hình học
  (`adviseComposition`), rồi dẫn hướng realtime tới đó.

Cách này nhanh, miễn phí, offline nhưng "hiểu" ảnh rất nông. Mục tiêu: cho
phần phân tích **sâu hơn** (hiểu ánh sáng, tông màu, bối cảnh, chủ thể) bằng
một vision LLM đám mây, mà **không phá vỡ** realtime và **không hỏng khi
offline**.

Quyết định đã chốt với người dùng:

- Nâng **cả** gợi ý filter **lẫn** bố cục.
- Dùng **Google Gemini 2.5 Flash** (vision tốt, rẻ, có free tier, REST đơn giản).
- Xử lý key: **giai đoạn 1 dùng `--dart-define`**, giấu sau interface để
  đổi sang Firebase AI Logic khi phát hành (xem mục 9).
- Bố cục: **giữ nguyên dẫn hướng realtime** (track chủ thể, dấu + di chuyển,
  **rung khi trùng**); chỉ khác là **điểm đích do Gemini quyết định 1 lần**
  thay cho luật hình học.

## 2. Phạm vi

Trong phạm vi:

- Lớp phân tích ảnh `SceneAnalyzer` (interface) + `GeminiSceneAnalyzer`.
- Model kết quả `SceneAnalysis`.
- Nối vào `_suggestFilter()` (filter) và `_handleAnalyzingFrame()` (bố cục).
- Fallback on-device khi offline/lỗi/thiếu key.
- Cấu hình key qua `--dart-define`, tài liệu chạy.
- Test cho phần parse/map thuần.

Ngoài phạm vi (YAGNI giai đoạn này):

- Firebase AI Logic / backend proxy (chỉ nêu lộ trình, chưa làm).
- Gemini tinh chỉnh trực tiếp tham số màu (chỉ chọn preset có sẵn).
- Cache kết quả phân tích, lịch sử, phân tích hàng loạt.

## 3. Kiến trúc tổng quan

Mô hình **hybrid**: cloud phân tích sâu **1 lần trên ảnh tĩnh**, on-device lo
realtime và làm fallback.

```
                 ┌─────────────────────────────┐
   ảnh tĩnh ───▶ │      SceneAnalyzer (itf)     │
 (JPEG bytes)    ├─────────────────────────────┤
                 │ GeminiSceneAnalyzer (online) │──▶ SceneAnalysis
                 │ OfflineSceneAnalyzer (fallb.)│──▶ SceneAnalysis
                 └─────────────────────────────┘
```

- `GeminiSceneAnalyzer`: gọi Gemini, trả `SceneAnalysis` đầy đủ.
- Khi mạng lỗi/timeout/thiếu key → dùng đường on-device hiện có
  (`FilterSuggester` cho filter, `adviseComposition` cho bố cục) gói trong
  cùng kiểu `SceneAnalysis` để phía UI không cần biết nguồn.

## 4. Thành phần

### 4.1. Model `SceneAnalysis` (mới)

File mới: `lib/src/features/analysis/scene_analysis.dart`

```dart
class SceneAnalysis {
  final String presetId;        // phải nằm trong filmPresets
  final String? reason;         // vì sao chọn preset (hiện cho người dùng)
  final String? mood;           // mô tả ánh sáng/tông màu/bối cảnh
  final Offset? targetPoint;    // 0..1 viewfinder, điểm bố cục đẹp nhất
  final List<String> tips;      // mẹo bố cục ngắn
  final bool fromCloud;         // true = Gemini, false = fallback on-device
}
```

- `presetId` luôn được kẹp về một id hợp lệ trong `filmPresets`; nếu Gemini
  trả id lạ → rơi về `original`.
- `targetPoint` có thể null (ví dụ đường filter không cần bố cục).

### 4.2. Interface `SceneAnalyzer` + hiện thực

File mới: `lib/src/features/analysis/scene_analyzer.dart`

```dart
abstract interface class SceneAnalyzer {
  /// Phân tích 1 ảnh tĩnh. Ném lỗi nếu không phân tích được (mạng/timeout);
  /// người gọi bắt lỗi để fallback.
  Future<SceneAnalysis> analyze({
    required Uint8List jpegBytes,
    required String filePath, // cho fallback ML Kit dùng InputImage.fromFilePath
  });
}
```

`GeminiSceneAnalyzer implements SceneAnalyzer`:

- Đọc key: `String.fromEnvironment('GEMINI_API_KEY')`. Rỗng → ném lỗi
  `MissingApiKeyException` để fallback.
- Gọi REST `generateContent` của Gemini 2.5 Flash với: ảnh (inline base64,
  đã resize để tiết kiệm — xem 4.4), prompt hệ thống, và `responseSchema`
  buộc trả JSON đúng cấu trúc.
- Timeout ~8s (`http` + `.timeout`).
- Tách hàm thuần `SceneAnalysis parseGeminiJson(Map json, {required List<String> validIds})`
  để test không cần mạng.

`OfflineSceneAnalyzer implements SceneAnalyzer` (gói đường on-device cũ):

- Filter: gọi lại logic `FilterSuggester` (ML Kit label + luma → preset).
- Bố cục: chạy ML Kit object detection **một lần** trên ảnh tĩnh (không
  stream) → `pickSubjectIndex` → `adviseComposition().target` → `targetPoint`.
- `fromCloud = false`.

Provider Riverpod trong `lib/src/providers.dart`:

```dart
final sceneAnalyzerProvider = Provider<SceneAnalyzer>((ref) => GeminiSceneAnalyzer());
final offlineAnalyzerProvider = Provider<SceneAnalyzer>((ref) => OfflineSceneAnalyzer());
```

Người gọi: thử `sceneAnalyzerProvider`, `catch` mọi lỗi → dùng
`offlineAnalyzerProvider`.

### 4.3. Prompt & JSON schema

Prompt cấp cho Gemini:

- Danh mục preset thật (id + tên + mô tả chất phim, dựng từ `filmPresets`),
  yêu cầu chỉ được chọn 1 `presetId` trong danh sách.
- Yêu cầu trả: `presetId`, `reason` (tiếng Việt, ngắn), `mood`,
  `targetPoint` {x, y} trong 0..1 (gốc trên-trái), `tips` (0..3 mục tiếng Việt).
- `responseMimeType: application/json` + `responseSchema` khớp đúng các trường.

Ràng buộc toạ độ: Gemini nhận ảnh theo khung đã chụp; `targetPoint` được
hiểu trong không gian **viewfinder crop** (giống `adviseComposition`). Nếu
tỉ lệ ảnh chụp khác tỉ lệ viewfinder, quy đổi bằng logic center-crop sẵn có
(`centeredCropRect`) trước khi dùng.

### 4.4. Tối ưu ảnh gửi lên

Trước khi gửi, resize cạnh dài về ~768px và nén JPEG (dùng package `image`
đã có) để giảm dung lượng/chi phí/latency. Không ảnh hưởng chất lượng phân
tích ở mức này.

### 4.5. Nối vào Filter

Sửa `_suggestFilter()` trong `camera_screen.dart`:

1. Chụp ảnh tĩnh (đã có).
2. `analyze(...)` qua `sceneAnalyzerProvider`; lỗi → `offlineAnalyzerProvider`.
3. Set `_presetIndex` theo `result.presetId`.
4. Hiện `result.reason`/`result.mood` ở snackbar (nếu có).
5. State loading tái dùng `_suggesting`.

### 4.6. Nối vào Bố cục (giữ realtime, target 1 lần từ Gemini)

Giữ nguyên enum `_CompositionPhase` (off → analyzing → guiding) và toàn bộ
dẫn hướng realtime, dấu +, rung khi trùng, long-press đổi chủ thể.

Thay đổi **chỉ ở khoảnh khắc chốt điểm đích** (trong/ngay sau
`_handleAnalyzingFrame` khi chủ thể đã ổn định và được lock):

- Hiện tại: `_fixedTarget = adviseComposition(viewRect).target;` (hình học).
- Mới: chụp 1 ảnh tĩnh tại thời điểm chốt → `analyze(...)`:
  - Thành công & có `targetPoint` → `_fixedTarget = result.targetPoint;`
    và hiện `result.tips`.
  - Lỗi/offline/`targetPoint == null` → giữ nguyên
    `_fixedTarget = adviseComposition(viewRect).target;` (như cũ).
- Sau khi có `_fixedTarget`, chuyển sang `guiding` — phần realtime, aim-point,
  rung khi trùng **không đổi** vì chúng chỉ đọc `_fixedTarget`.

Lưu ý timing: lời gọi Gemini ~1–2s. Trong lúc chờ giữ pha `analyzing`
(đã có spinner/thông báo "giữ nguyên máy"). Nếu quá timeout → fallback hình học.

## 5. Xử lý lỗi & offline

- Thiếu key / mạng lỗi / timeout / JSON sai → **luôn** fallback on-device,
  không chặn người dùng.
- Thông báo nhẹ khi dùng fallback: "Dùng phân tích ngoại tuyến" (không spam;
  chỉ hiện khi thực sự rơi fallback).
- Không ném lỗi ra UI; mọi exception được bắt tại lớp gọi.

## 6. Phụ thuộc & cấu hình

- Thêm `http` vào `pubspec.yaml` (đường REST). `image` đã có (resize).
- Key: `flutter run --dart-define=GEMINI_API_KEY=xxxx` (và cấu hình tương tự
  trong codemagic.yaml khi build). Không commit key.
- Ghi chú cách lấy key + cách chạy vào README/tài liệu.

## 7. Testing

Theo phong cách test thuần hiện có (`suggestion_rules_test.dart` v.v.):

- `parseGeminiJson`: JSON hợp lệ → `SceneAnalysis` đúng; presetId lạ → kẹp
  về `original`; thiếu `targetPoint` → null; toạ độ ngoài [0,1] → kẹp/loại.
- Xây prompt/catalog: đảm bảo mọi id trong `filmPresets` xuất hiện.
- Fallback: `OfflineSceneAnalyzer` cho filter trả preset hợp lệ khi không có
  nhãn (chỉ luma) — tái dùng test suggestion sẵn có.
- Không test mạng thật; mock phản hồi HTTP.

## 8. Rủi ro & YAGNI

- Chi phí/latency: giảm bằng resize 768px + chỉ gọi khi người dùng chủ động
  bấm (không tự động, không realtime).
- Toạ độ `targetPoint` lệch không gian: xử lý bằng quy đổi center-crop; có
  test cho phần này.
- Không làm cache/lịch sử/tinh chỉnh màu ở giai đoạn này.

## 9. Bảo mật & lộ trình

- **Giai đoạn 1 (bản này):** key qua `--dart-define`. Chấp nhận rủi ro lộ key
  vì chỉ dùng để thử/cá nhân, chưa phát hành rộng.
- **Trước khi phát hành:** thay `GeminiSceneAnalyzer` bằng hiện thực dùng
  **Firebase AI Logic** (`firebase_ai`) — key nằm phía Google, App Check chặn
  lạm dụng, **không cần dựng server**. Nhờ interface `SceneAnalyzer`, việc đổi
  chỉ là thay 1 lớp, không đụng UI.
