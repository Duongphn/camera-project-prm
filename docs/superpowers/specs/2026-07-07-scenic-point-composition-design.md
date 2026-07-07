# Thiết kế: Chọn chủ thể bằng chạm + điểm cảnh đẹp nhất khi không chọn chủ thể

Ngày: 2026-07-07
Nhánh: `feat/gemini-vision-scene-analysis`

> **Cập nhật hoà giải (2026-07-08):** Sau khi thiết kế này được hiện thực, nhánh
> `main` đã merge PR #4 ("guided AI composition 4 pha kiểu Doka":
> `off/analyzing/aiming/framing` + auto-zoom + auto-filter + crop frame +
> sparkle + long-press chọn chủ thể + tự khoá sau 3 frame). Theo quyết định
> giữ luồng PR #4 làm nền, bản **thực tế merge KHÁC** tài liệu dưới đây:
> - **Không** thêm pha `point`/cử chỉ `tap` riêng, **không** bỏ auto-detect
>   hay long-press — giữ nguyên toàn bộ luồng PR #4.
> - Phần "điểm cảnh đẹp" (`scenicPoint`) được **ghép làm trạng thái nghỉ**:
>   khi phân tích xong (`_cloudResolved`) mà chưa có chủ thể nào tự khoá, hiện
>   nốt tròn tĩnh tại điểm cảnh đẹp (hoặc lưới 1/3 khi offline) trong pha
>   `analyzing`. `scenicPoint` cộng gộp với `cropRect`/`advice` của PR #4 trong
>   cùng 1 lần gọi Gemini. Phần mô tả bên dưới giữ lại làm bối cảnh thiết kế gốc.

## Mục tiêu

Cho tính năng **AI bố cục** (nút ⊹):

1. Người dùng **chủ động chạm** vào một vật thể trên viewfinder để chọn chủ thể → app dẫn hướng ngắm để đưa chủ thể vào điểm bố cục đẹp (hành vi dẫn ngắm đã có).
2. Nếu người dùng **không chọn chủ thể**, AI tự chỉ ra **một điểm mà cảnh vật tại đó đẹp/thu hút nhất trong khung hình** — điểm nhấn có sẵn trong nội dung ảnh (không phải chỗ trống để đặt chủ thể). Điểm này hiện dưới dạng **nốt tròn tĩnh** làm mốc bố cục.

## Bối cảnh hiện trạng

- `_toggleComposition` / `_runCloudCompositionAnalysis` (`camera_screen.dart`): bấm ⊹ → chụp 1 ảnh → gọi Gemini 2.5 Flash 1 lần → nhận `targetPoint` (nơi **đặt chủ thể** đẹp) + `tips`.
- `SubjectDetector` (ML Kit object detection, stream): tự phát hiện chủ thể nổi bật; `_handleAnalyzingFrame` chờ chủ thể ổn định 3 frame rồi tự khoá → pha `guiding`.
- Long-press viewfinder → khoá thủ công chủ thể tại điểm bấm; bấm vùng trống → phân tích lại.
- **Khoảng trống:** nếu ML Kit không phát hiện được chủ thể nào, pha `analyzing` không bao giờ hoàn tất → điểm Gemini tính ra không được hiển thị.
- `targetPoint` hiện có nghĩa "nơi **đặt** chủ thể", **không** phải "chỗ cảnh đẹp có sẵn". Đây là 2 ý nghĩa khác nhau.

## Máy trạng thái (4 pha)

| Pha | Ý nghĩa | Overlay |
|-----|---------|---------|
| `off` | Tắt AI bố cục | — |
| `analyzing` | Đang hỏi Gemini (chụp 1 ảnh) | spinner "đang tìm điểm đẹp" |
| `point` | **Mới** — không có chủ thể, hiện điểm cảnh đẹp nhất | nốt tròn tĩnh tại `scenicPoint` + 1 mẹo |
| `guiding` | Đã khoá chủ thể, dẫn ngắm | dấu `+` giữa + nốt tròn đích (giữ nguyên) |

### Chuyển pha

- `off` → bấm ⊹ → `analyzing` (chạy Gemini + bật stream ML Kit để có sẵn box cho việc chạm chọn).
- `analyzing` → Gemini xong, **chưa** chọn chủ thể → `point`.
- `analyzing`/`point` → **chạm trúng vật thể** → `guiding` (khoá chủ thể; điểm đích = `targetPoint` của Gemini, hoặc dự phòng hình học nếu offline).
- `guiding` → **chạm trúng vật khác** → `guiding` (đổi chủ thể, chốt lại điểm đích).
- `guiding` → **chạm vùng trống** → `point` (bỏ chủ thể, **giữ nguyên** `scenicPoint`, KHÔNG gọi lại Gemini).
- `guiding` → **mất dấu chủ thể đã khoá** → tự về `point` (thay vì kẹt như hiện tại).
- bất kỳ → bấm ⊹ → `off`.

### Gỡ bỏ

- Cơ chế **tự phát hiện + tự khoá chủ thể sau 3 frame** (`_handleAnalyzingFrame` chờ subject ổn định): bỏ — chọn chủ thể giờ hoàn toàn do người dùng chạm.
- **Long-press** trên viewfinder: bỏ — gom mọi thao tác chọn/bỏ chủ thể về `onTap`.

## Cử chỉ chạm (tap)

Thêm `onTap` cho `GestureDetector` của viewfinder (hiện chỉ có `onLongPressStart`; không có tap-to-focus nên không xung đột):

- **Chạm trúng vật thể** (ML Kit `detector.lockAt(imagePoint)` trả true) → khoá chủ thể → `guiding`.
- **Chạm vùng trống** (`lockAt` trả false):
  - đang `guiding` → bỏ khoá, về `point`.
  - đang `point`/`analyzing` → không làm gì.

Điểm chạm (toạ độ viewfinder 0..1) → `mapViewPointToImage` → toạ độ px ảnh upright cho `lockAt` (hàm sẵn có).

## Điểm cảnh đẹp nhất (scenic point) từ Gemini

Gọi Gemini **1 lần**, trả về **2 toạ độ** trong cùng phản hồi:

| Trường | Ý nghĩa | Dùng cho |
|--------|---------|----------|
| `targetX/targetY` (đã có) | Nơi **đặt** chủ thể cho bố cục đẹp | `guiding` |
| `scenicX/scenicY` (**mới**) | Điểm mà **cảnh tại đó đẹp/thu hút nhất** trong khung | `point` |

### `gemini_prompt.dart`

- Thêm `scenicX`, `scenicY` (kiểu `NUMBER`) vào `sceneResponseSchema` (không bắt buộc — `required` giữ nguyên `['presetId']`).
- Thêm mô tả vào prompt:
  > `scenicX, scenicY`: điểm mà **cảnh vật tại đó đẹp/thu hút nhất** trong khung (điểm nhấn có sẵn trong ảnh — ví dụ ánh sáng đẹp, chi tiết nổi bật, phản chiếu...), số thực 0..1 (gốc 0,0 ở góc trên-trái).
- `parseGeminiJson`: đọc `scenicX/scenicY`, kiểm nằm trong [0,1] giống `targetX/targetY`, → `Offset?`.

### `scene_analysis.dart`

- `SceneAnalysis` thêm field `final Offset? scenicPoint;` (mặc định null), tài liệu hoá "điểm cảnh đẹp nhất, 0..1 không gian ảnh".

### `camera_screen.dart`

- Sau khi Gemini trả về: map `analysis.scenicPoint` (không gian ảnh tĩnh) → viewfinder bằng `mapImagePointToView` (bù center-crop + lật gương camera trước), kẹp về [0,1] → lưu `_scenicTarget` (Offset viewfinder), song song với `_cloudTarget` đang có.
- Pha `point` vẽ nốt tròn tĩnh tại `_scenicTarget`.

## Vẽ overlay

- **`point`:** thêm tham số `scenicPoint` (Offset? viewfinder) vào `CompositionOverlay`. Khi có `scenicPoint` và `advice == null` → vẽ **nốt tròn tĩnh** (tái dùng kiểu nốt tròn hiện có: lõi đặc + viền tối + vòng ngoài mờ), màu trắng, **không** vẽ dấu `+`, không haptics.
- **`guiding`:** giữ nguyên (dấu `+` giữa + nốt tròn đích + đổi xanh khi trùng).
- Kèm thông báo pha `point`: hiện 1 dòng gồm `tips.first` (nếu có) và gợi ý *"Chạm vào chủ thể nếu muốn bám theo"*.

## Dự phòng khi offline

- **Có chủ thể + offline:** giữ nguyên dự phòng hình học `adviseComposition` (giao điểm 1/3 gần chủ thể, hoặc tâm khung nếu chủ thể lớn).
- **Không chủ thể + offline (`point`):** "cảnh đẹp" dựa trên nội dung ảnh nên cần mô hình thị giác; offline không đánh giá được. → Hiện **mờ 4 giao điểm 1/3** làm gợi ý bố cục + báo nhẹ *"cần mạng để tìm điểm đẹp theo cảnh"*.

## Các file thay đổi

- `lib/src/features/analysis/gemini_prompt.dart` — schema + prompt + parse `scenic*`.
- `lib/src/features/analysis/scene_analysis.dart` — field `scenicPoint`.
- `lib/src/features/camera/camera_screen.dart` — pha `point`, `onTap`, map `scenicPoint`, gỡ auto-detect & long-press, dự phòng offline point.
- `lib/src/features/composition/composition_overlay.dart` — vẽ nốt tròn tĩnh.

## Kiểm thử

- `test/gemini_prompt_test.dart`: parse `scenicX/scenicY` hợp lệ → `scenicPoint`; ngoài [0,1] hoặc thiếu → null.
- Test map `scenicPoint` ảnh→viewfinder (nếu tách được hàm thuần đã có `mapImagePointToView`).
- Test logic chuyển pha thuần (nếu tách được khỏi widget): chạm trúng box → guiding; chạm trống khi guiding → point.

## Ngoài phạm vi (YAGNI)

- Không thêm on-device saliency cho điểm cảnh đẹp offline.
- Không đổi ý nghĩa `targetPoint` của chế độ có chủ thể.
- Không thêm nút gạt chế độ; việc phân nhánh point/subject do có chạm hay không quyết định.
