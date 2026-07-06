# Guided AI Composition (kiểu Doka Cam) — Design

Ngày: 2026-07-06. Trạng thái: đã duyệt.

## 1. Mục tiêu

Tái hiện trải nghiệm chế độ AI构图 của Doka Cam (theo video tham khảo
`snaptik.vn_7657051947840818440.mp4`): người dùng bật AI bố cục, app phân
tích cảnh bằng Gemini rồi **dẫn dắt từng bước** đến khung hình đẹp — hiệu
ứng phân tích, vòng ngắm cầu vồng, khung crop đề xuất, tự động zoom, tự áp
filter kèm lời giải thích bằng tiếng Việt.

Không làm trong đợt này: watermark trên ảnh (đã quyết định bỏ), lưu tên
filter vào metadata ảnh, màn hình chế độ riêng.

## 2. Luồng người dùng (4 pha)

Mở rộng `_CompositionPhase` hiện có trong `camera_screen.dart`:

```
off → analyzing → aiming → framing
```

1. **analyzing** — Bấm nút ⊹. Overlay chấm sáng lấp lánh phủ viewfinder
   (ngẫu nhiên → gom dần về lưới) + banner "AI đang phân tích — giữ yên
   máy". App chụp 1 frame tĩnh gửi Gemini (cơ chế
   `_runCloudCompositionAnalysis` hiện có).
2. **Kết quả trả về** — Ngay khi có `SceneAnalysis`:
   - Tự áp filter `presetId` (đổi `_presetIndex`).
   - Hiện `AiToastCard`: "«mood» — gợi ý «tên filter», «reason»".
3. **aiming** — Dấu + cố định giữa màn hình (giữ nguyên) + **vòng tròn cầu
   vồng** tại điểm bố cục (`targetPoint` từ Gemini, fallback hình học).
   Logic bám chủ thể/advisor giữ nguyên. Căn trúng → haptic như hiện tại.
4. **framing** — Chỉ vào pha này khi có `cropRect` từ Gemini và đã căn
   trúng (`isAligned`):
   - Hiện **khung bo góc viền gradient cầu vồng** thể hiện vùng crop đề
     xuất (map cropRect ảnh → toạ độ viewfinder bằng `geometry.dart`).
   - Tự động zoom mượt (~600ms, ease) tới `zoomForCrop(cropRect)`.
   - Nếu zoom đề xuất > maxZoom của camera → chip "Tiếp tục zoom vào"
     (người dùng zoom tay/di chuyển lại gần).
   - Hiện `AiToastCard` thứ hai với `advice` (lời khuyên bố cục chi tiết).
   - Khung guide mờ dần khi đạt mức zoom. Người dùng bấm chụp bình thường.

Thoát/flip camera/đổi aspect → reset về `off`/`analyzing` như logic hiện có.

## 3. Mở rộng schema Gemini

`gemini_prompt.dart` — thêm vào `sceneResponseSchema` và prompt:

- `cropX, cropY, cropW, cropH` (NUMBER, 0..1, gốc trên-trái): vùng crop
  đẹp nhất trên ảnh. Hợp lệ khi 4 giá trị đều có, w/h > 0, nằm trong 0..1.
- `advice` (STRING): lời khuyên bố cục chi tiết, tiếng Việt, ≤ 30 từ,
  kiểu "Ảnh dọc, chủ thể cầu kính với nền cao ốc, bố cục căn giữa +
  khoảng trống, nén bớt trời và mặt đất".

`SceneAnalysis` thêm field `Rect? cropRect` và `String? advice`.
`parseGeminiJson` parse + validate (rect không hợp lệ → null, không vỡ).
`OfflineSceneAnalyzer` giữ nguyên — hai field mới luôn null khi offline.

Vẫn **một lần gọi Gemini duy nhất** cho cả filter + điểm ngắm + crop +
lời khuyên.

## 4. Thành phần UI mới (lib/src/features/camera/widgets/ và composition/)

| Widget | Vai trò |
|---|---|
| `AnalyzingSparkleOverlay` | CustomPainter + AnimationController: ~60 chấm sáng nhấp nháy vị trí ngẫu nhiên, sau ~1.5s gom về các mắt lưới; chạy suốt pha analyzing. |
| `CompositionOverlay` (nâng cấp) | Nốt tròn trắng → vòng tròn viền gradient cầu vồng (SweepGradient), lõi trong suốt; trạng thái aligned vẫn chuyển xanh như cũ. |
| `FrameGuideOverlay` | Khung chữ nhật bo góc viền gradient cầu vồng vẽ theo cropRect đã map sang view; opacity giảm dần theo tiến độ zoom. |
| `AiToastCard` | Pill nền đen mờ, viền gradient nhẹ, chữ trắng (từ khoá màu nhấn); tự ẩn sau ~5s, thu về nút nhỏ ↩ bấm hiện lại. Thay SnackBar cho mọi thông báo AI trong luồng này. |
| Chip "Tiếp tục zoom vào" | Hiện ở đáy viewfinder khi cần zoom vượt max. |

## 5. Auto-zoom

- Hàm thuần `double zoomForCrop(Rect cropRect, {required double maxZoom})`
  = `1 / max(cropRect.width, cropRect.height)` clamp `[1, maxZoom]`.
- Chỉ zoom sau khi `isAligned` (chủ thể đã vào tâm) vì
  `CameraController.setZoomLevel` neo giữa khung — căn trước, zoom sau
  (đúng thứ tự trong video Doka).
- Animate bằng `AnimationController` ~600ms easeInOut, mỗi tick gọi
  `setZoomLevel`. Bỏ qua tick lỗi CameraException lẻ.
- Thoát chế độ AI bố cục → trả zoom về 1.0.

## 6. Fallback & lỗi

- Gemini lỗi/offline/thiếu key: như hiện tại — điểm ngắm hình học, toast
  dùng câu rule-based ngắn, **không có pha framing** (không cropRect).
- `cropRect` có nhưng `targetPoint` null: dùng tâm cropRect làm điểm ngắm.
- Mất dấu chủ thể trong aiming/framing: dừng zoom animation, giữ thông
  báo "Mất dấu — bấm ⊹ phân tích lại" như hiện tại.
- Chụp trong lúc đang zoom animation: cho phép — dừng animation tại chỗ
  rồi chụp.

## 7. Kiểm thử

- Unit: parse schema mới (crop hợp lệ/không hợp lệ, advice), `zoomForCrop`
  (crop nhỏ → clamp maxZoom, crop full → 1.0), map cropRect → view qua
  `geometry.dart`.
- Widget smoke: `AnalyzingSparkleOverlay`, `FrameGuideOverlay`,
  `AiToastCard` render không lỗi.
- Trên máy thật (thủ công): 3 giả định toạ độ trong PLAN.md §3 vẫn áp
  dụng; thêm giả định mới cần kiểm chứng — cropRect Gemini trả về khớp
  vùng nhìn thấy sau center-crop của preview.

## 8. Ngoài phạm vi / tương lai

- Watermark thương hiệu riêng (đã quyết định không làm).
- Ghi tên filter vào EXIF/metadata ảnh và hiện trong gallery viewer.
- Nút "vào/thoát chế độ构图" toàn màn hình như app gốc.
- Đếm lượt AI/ngày (thuộc giai đoạn monetization trong PLAN.md).
