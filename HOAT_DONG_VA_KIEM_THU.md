# Doka App — Cách hoạt động & Checklist kiểm thử

> Cập nhật: 2026-07-04. Trạng thái: GĐ1 + GĐ2 + GĐ3-v1 đã code xong.
> Đã xác minh trên PC: `flutter analyze` sạch, 45/45 unit/widget test pass, build APK debug thành công.
> Chưa xác minh: mọi thứ liên quan phần cứng thật (camera, GPU, cảm biến, ML Kit).

---

## PHẦN 1 — CÁCH HOẠT ĐỘNG

### 1.1. Kiến trúc tổng quan

```
lib/
├── main.dart                        # Khởi động, khoá dọc màn hình, theme tối
└── src/
    ├── providers.dart               # Riverpod: photoRepositoryProvider
    ├── core/
    │   └── geometry.dart            # centeredCropRect, rollRadians, isLevel (pure)
    └── features/
        ├── camera/
        │   ├── camera_screen.dart   # Màn hình chính, điều phối mọi tính năng
        │   ├── capture_aspect.dart  # Tỉ lệ 3:4 / 1:1 / 9:16
        │   └── widgets/             # preview filter, grid, level, carousel, beauty filter
        ├── filters/
        │   ├── film_preset.dart     # 10 preset màu phim (data thuần)
        │   ├── film_shader.dart     # Pack uniform + cache FragmentProgram
        │   ├── beauty_shader.dart   # Tương tự cho beauty
        │   ├── image_renderer.dart  # Các pass GPU: crop, downscale, film, beauty
        │   ├── photo_processor.dart # Pipeline chụp → lưu
        │   └── photo_encoder.dart   # RGBA → JPEG (chạy trong isolate)
        ├── composition/
        │   ├── composition_advisor.dart  # Toán bố cục + map toạ độ (pure)
        │   ├── subject_detector.dart     # ML Kit object detection trên stream
        │   ├── camera_image_converter.dart # YUV420 → NV21 (pure)
        │   └── composition_overlay.dart  # Vẽ khung/mũi tên/điểm đích
        ├── suggestion/
        │   ├── suggestion_rules.dart     # Map nhãn + độ sáng → preset (pure)
        │   └── filter_suggester.dart     # Gọi ML Kit image labeling
        ├── editor/
        │   └── edit_screen.dart     # Chỉnh màu sau chụp
        └── gallery/
            ├── photo_repository.dart # Lưu/đọc/xoá ảnh trong thư mục app
            └── gallery_screen.dart   # Grid + viewer + nút sửa/xoá

shaders/
├── film.frag    # Màu phim: exposure, contrast, saturation, WB, split-tone,
│                # fade, vignette, grain
└── beauty.frag  # Làm mịn da: mặt nạ tông da YCbCr + bilateral blur 12 tap
```

Nguyên tắc thiết kế: **mọi logic có thể sai đều là hàm thuần có unit test**
(toán crop, map toạ độ, chọn chủ thể, rule gợi ý, pack uniform, ghép NV21);
phần chạm phần cứng (camera, GPU, ML Kit) mỏng nhất có thể.

### 1.2. Pipeline filter màu phim (GĐ1)

**Preview real-time:** `CameraPreview` được bọc trong `ImageFiltered` với
`ui.ImageFilter.shader(film.frag)` — engine Impeller tự bind kích thước
(`u_size`, 2 float đầu) và texture preview (sampler đầu tiên). App chỉ set
các uniform từ index 2: exposure, contrast, saturation, temperature, tint,
fade, vignette, grain, seed, shadow/highlight tint. Nếu thiết bị không hỗ trợ
(`ImageFilter.isShaderFilterSupported == false`) thì hiển thị preview gốc —
ảnh chụp vẫn được bake filter bình thường.

**Chụp ảnh (bake full-res):** `takePicture()` (JPEG ~4K, ResolutionPreset.ultraHigh)
→ decode thành `ui.Image` → **crop giữa** theo tỉ lệ đang chọn
(`centeredCropRect`; nếu decoder trả ảnh nằm ngang do EXIF chưa áp thì tỉ lệ
tự đảo) → **beauty pass** (nếu bật) → **film pass** (cùng shader với preview,
seed hạt ngẫu nhiên) → `toByteData(rawRgba)` → **encode JPEG quality 92 trong
isolate** (không giật UI) → lưu file vào thư mục app + copy sang thư viện hệ
thống qua `gal`. Thiếu quyền thư viện thì ảnh vẫn còn trong app và có snackbar
thông báo.

**10 preset:** Gốc (trung tính), Sài Gòn 89 (vàng ấm), Đà Lạt (pastel sương),
Hạ Long (xanh lạnh), Chợ Đêm (teal-orange), Mono 400 (B&W hạt),
Noir (B&W tương phản), Retro 76 (sepia bạc màu), Xanh Rêu (thiên xanh lá),
Kem (sáng mềm). Mỗi preset chỉ là một bộ tham số uniform — thêm preset mới
không cần sửa shader.

**Shader film.frag xử lý theo thứ tự:** phơi sáng (exp2) → cân bằng trắng theo
kênh → tương phản quanh pivot 0.46 → bão hoà → split-tone vùng tối/sáng →
fade (nâng điểm đen) → vignette → hạt phim (hash noise). Toàn bộ là color-map
theo pixel, không lấy mẫu lệch toạ độ → miễn nhiễm lỗi lật trục Y trên GLES.

### 1.3. Beauty — làm mịn da (GĐ2)

Nút mặt cười mở slider 0–100. `beauty.frag`:
1. Tính mặt nạ da theo dải YCbCr (Cb 0.30–0.50, Cr 0.52–0.68, loại vùng quá tối).
2. Blur **bilateral 12 tap** (trọng số giảm theo khác biệt màu → giữ cạnh mắt,
   tóc, nền sắc nét), bán kính tự scale theo độ phân giải để preview và ảnh
   full-res trông giống nhau.
3. Trộn theo mặt nạ × cường độ, kèm sáng da nhẹ (+5% tối đa).

Thứ tự pass: **beauty trước, film sau** (cả preview lẫn bake) — vì mặt nạ da
cần màu gốc; nếu áp sau filter B&W thì không tìm thấy da nữa.

*Khác kế hoạch gốc:* không dùng ML Kit face detection real-time — mặt nạ tông
da trong shader rẻ hơn nhiều và đủ tốt cho v1; face landmark để dành nâng cấp.

### 1.4. AI gợi ý filter (GĐ2)

Nút ✨: chụp 1 frame → chạy song song 2 tín hiệu:
- **ML Kit Image Labeling** (on-device, ngưỡng tin cậy 0.6) trên file ảnh.
- **Độ sáng trung bình** (decode thumbnail 48px, tính luma).

Map sang preset bằng rule thuần (`suggestion_rules.dart`), thứ tự ưu tiên:
tối (<0.22) → Chợ Đêm; người/selfie → Kem; đồ ăn/đồ uống → Sài Gòn 89;
hoàng hôn → Sài Gòn 89; biển/trời/nước → Hạ Long; cây cối → Xanh Rêu;
phố/kiến trúc → Retro 76; không rõ → Đà Lạt.

ML Kit lỗi (thiếu Play Services, model chưa tải) → vẫn gợi ý theo độ sáng,
không văng lỗi.

### 1.5. AI bố cục (GĐ3-v1, rule-based)

Nút ⊹ bật/tắt. Khi bật:

1. **Stream frame:** `startImageStream` — Android nhận NV21 (nếu camera trả
   YUV420 3 plane thì tự ghép NV21, xử lý cả rowStride/pixelStride), iOS nhận
   BGRA. Góc xoay tính từ sensorOrientation + hướng máy (app khoá dọc).
2. **ML Kit Object Detection** (stream mode, multipleObjects, model bundled):
   trả tối đa 5 vật thể + tracking ID. Detector bỏ qua frame khi đang bận
   (throttle tự nhiên, không dồn hàng đợi).
3. **Chọn chủ thể** (`pickSubjectIndex`): ưu tiên chủ thể đã khoá; không có
   thì chấm điểm `diện tích × (0.4 + 0.6 × độ gần tâm)`.
4. **Map toạ độ** (`mapImageRectToView`): từ không gian ảnh upright → toạ độ
   0..1 của viewfinder, xét crop cover theo tỉ lệ khung đang chọn và mirror
   nếu là camera trước.
5. **Tính lời khuyên** (`adviseComposition`): điểm đích = giao điểm
   rule-of-thirds gần nhất; chủ thể chiếm ≥35% khung → đích là tâm. Tâm chủ
   thể cách đích ≤5% → `isAligned`.
6. **Overlay:** khung bo góc quanh chủ thể + vòng tròn điểm đích + mũi tên
   chỉ hướng di máy. Trắng = bình thường, **vàng** = đã khoá chủ thể,
   **xanh + rung nhẹ** = vào bố cục (mũi tên biến mất, chấm tâm hiện ra).
7. **Long-press** lên chủ thể trong khung ngắm → khoá theo tracking ID
   (AI bám theo nó); long-press vùng trống → bỏ khoá. Chủ thể khoá ra khỏi
   khung → tự bỏ khoá.

Stream tự tạm dừng khi chụp / gợi ý filter và tự chạy lại; tự khởi động lại
sau khi flip camera hoặc app quay lại foreground.

### 1.6. Chỉnh ảnh sau chụp (GĐ2)

Gallery → mở ảnh → nút tune. 7 thanh chỉnh: Phơi sáng (−1..1), Tương phản
(0.5..1.5), Nhiệt màu (−1..1), Bão hoà (0..2), Fade, Vignette, Hạt (0..1).
Preview render bằng **film pass trên bản thu nhỏ 1080px** (kéo slider mượt,
có render-loop chống dồn lệnh); bấm ✓ thì render lại ở **full-res** và lưu
thành **ảnh mới** (không ghi đè gốc) vào app + thư viện máy. Chip nào lệch
khỏi giá trị trung tính sẽ có dấu chấm •.

### 1.7. Thư viện & lưu trữ

- Ảnh JPEG lưu tại `<app documents>/photos/DOKA_<timestamp>.jpg` — đây là
  nguồn của gallery trong app; đồng thời copy sang thư viện hệ thống.
- Gallery: grid 3 cột (thumbnail cacheWidth 360), viewer vuốt ngang +
  zoom 5x, xoá (chỉ xoá bản trong app, có dialog xác nhận nói rõ điều đó).

### 1.8. Quyền & platform

| Quyền | Android | iOS |
|---|---|---|
| Camera | `CAMERA` (plugin tự xin runtime) | `NSCameraUsageDescription` |
| Lưu thư viện | API ≤28: `WRITE_EXTERNAL_STORAGE` (maxSdkVersion 28, khớp khai báo camerax); API 29+: không cần | `NSPhotoLibraryAddUsageDescription` |
| Micro | không dùng (enableAudio: false) | key có sẵn phòng khi quay video |

Lifecycle: app vào background → dispose camera controller (stream chết theo);
quay lại → khởi tạo lại controller + stream bố cục nếu đang bật.

---

## PHẦN 2 — CHECKLIST KIỂM THỬ TRÊN MÁY THẬT

> Đã có 45 unit/widget test tự động chạy bằng `flutter test`.
> Danh sách dưới đây là những thứ **không thể** kiểm trên PC — cần điện thoại
> thật (ưu tiên 1 máy Android tầm trung ~Snapdragon 7xx và 1 máy yếu hơn).
> Cài đặt: `flutter run` hoặc APK tại `build\app\outputs\flutter-apk\app-debug.apk`.

### 2.1. Khởi động & quyền ⭐ (chặn mọi thứ khác)

- [ ] Lần đầu mở app: hiện xin quyền camera; **cho phép** → preview hiện ra.
- [ ] **Từ chối** quyền camera → app hiện trạng thái lỗi + nút "Thử lại",
      không crash; cấp quyền trong Settings rồi bấm Thử lại → chạy được.
- [ ] Chụp tấm đầu tiên: hiện xin quyền thư viện ảnh (Android 10+ có thể
      không hỏi). Từ chối → ảnh vẫn trong gallery của app + snackbar
      "Đã lưu trong app...".

### 2.2. Camera cơ bản (GĐ1)

- [ ] Preview mượt, đúng chiều, không méo ở cả 3 tỉ lệ 3:4 / 1:1 / 9:16.
- [ ] Ảnh chụp ra: **đúng chiều đứng** (kiểm tra EXIF được áp — giả định
      quan trọng), đúng tỉ lệ đã chọn, độ phân giải ~4K.
- [ ] Ảnh xuất hiện ở cả gallery trong app lẫn app Ảnh của máy.
- [ ] Flip camera trước/sau nhiều lần liên tiếp — không crash, không đen hình.
- [ ] Flash off/auto/on hoạt động với camera sau; camera trước không flash
      → không crash khi bấm.
- [ ] Grid bật/tắt; **vạch cân bằng**: nghiêng máy → vạch xoay theo,
      giữ thẳng → chuyển xanh. ⚠️ Kiểm tra **chiều xoay có thuận** (vạch phải
      song song đường chân trời thật); nếu ngược → đổi dấu trong
      `rollRadians()` tại `lib/src/core/geometry.dart`.
- [ ] Ra vào app (home rồi quay lại) → preview tự hồi phục.

### 2.3. Filter real-time (GĐ1) ⭐ rủi ro số 1 của dự án

- [ ] Lướt qua cả 10 filter trên preview: màu đổi **ngay lập tức**, đúng
      "chất" mô tả (Mono/Noir phải đen trắng, Sài Gòn 89 ám vàng...).
- [ ] **FPS preview khi bật filter ≥ 30** trên máy tầm trung (bật Profile
      overlay: `flutter run --profile` + `P` hoặc quan sát độ mượt). Đây là
      tiêu chí "xong" của GĐ1. Nếu giật → ghi nhận model máy, tính đến
      phương án render native.
- [ ] **Ảnh lưu ra giống preview** (màu, vignette, hạt) — so sánh mắt thường
      cùng khung cảnh.
- [ ] Preview không bị **lật ngược** khi bật filter (nếu lật = thiết bị dùng
      GLES và có sai giả định — báo lại ngay).
- [ ] Máy không hỗ trợ shader filter (hiếm): preview hiện màu gốc nhưng ảnh
      chụp vẫn có filter.

### 2.4. Beauty (GĐ2)

- [ ] Slider 0→100 trên preview có mặt người: da mịn dần **theo thời gian
      thực**, mắt/tóc/viền mặt vẫn sắc nét (không như bôi mờ cả ảnh).
- [ ] ⚠️ Kiểm tra trên **da người Việt thực tế, nhiều tông** (sáng/ngăm) và
      dưới nắng/đèn vàng — mặt nạ YCbCr có thể cần nới dải trong
      `shaders/beauty.frag` (hàm `skinMask`).
- [ ] Kiểm tra **false positive**: vật thể màu giống da (gỗ, cát, tường be)
      có bị mịn theo không — có nhẹ là chấp nhận được ở v1, mịn rõ là bug.
- [ ] Beauty 100 + filter Chợ Đêm cùng lúc: preview vẫn mượt (2 shader pass
      chồng nhau — điểm nghi ngờ hiệu năng).
- [ ] Ảnh chụp với beauty: mức độ mịn **tương đương preview**.
- [ ] Beauty hoạt động với cả camera trước (use case chính là selfie).

### 2.5. AI gợi ý filter (GĐ2)

- [ ] Bấm ✨ lần đầu: có thể chờ 1–3s (Play Services tải model) — phải có
      spinner, không treo UI.
- [ ] Chĩa vào: đồ ăn → kỳ vọng Sài Gòn 89; cây cối → Xanh Rêu; trời/biển →
      Hạ Long; người → Kem; phòng tối → Chợ Đêm. Đúng ≥3/5 là đạt v1;
      sai nhiều → xem nhãn thực tế ML Kit trả về rồi bổ sung keyword vào
      `suggestion_rules.dart`.
- [ ] Filter được chọn tự động trên carousel + snackbar "Gợi ý filter: X ✨".
- [ ] Máy không có Google Play Services (nếu có máy như vậy): vẫn gợi ý được
      (theo độ sáng), không crash.

### 2.6. AI bố cục (GĐ3) ⭐ nhiều giả định nhất — soi kỹ

**Đúng/sai toạ độ (3 giả định đã ghi trong PLAN.md):**
- [ ] Bật ⊹, chĩa vào 1 vật thể rõ (cốc nước, người): **khung overlay ôm sát
      vật thể thật** trên màn hình. Nếu lệch ngang/dọc cố định → giả định
      center-crop sai; nếu lệch kiểu hoán đổi trục → giả định hệ toạ độ xoay
      sai. Sửa tại `mapImageRectToView` / `subject_detector.dart`.
- [ ] Thử cả 3 tỉ lệ khung 3:4 / 1:1 / 9:16 — khung vẫn ôm đúng vật thể.
- [ ] **Camera trước**: di mặt sang trái → khung di theo đúng chiều trên màn
      hình (kiểm tra giả định mirror). Ngược chiều → đổi cờ `mirrorX`.

**Hành vi dẫn hướng:**
- [ ] Vật thể lệch góc → mũi tên chỉ về giao điểm thirds gần nhất; di máy
      theo mũi tên → khi tâm vật vào đích: overlay **chuyển xanh + rung nhẹ**,
      mũi tên biến mất.
- [ ] Vật thể to chiếm gần hết khung → điểm đích là tâm.
- [ ] Nhiều vật thể: app tự chọn vật to/gần tâm; **long-press** lên vật khác
      → khung chuyển **vàng**, bám theo vật đó kể cả khi di máy;
      long-press vùng trống → bỏ khoá.
- [ ] Không có vật thể rõ (tường trắng) → overlay tự ẩn, không nhấp nháy loạn.

**Ổn định & hiệu năng:**
- [ ] Bật ⊹ rồi: chụp ảnh, bấm ✨, flip camera, ra vào app — mọi thứ hoạt
      động lại bình thường sau mỗi hành động (stream pause/resume đúng).
- [ ] Preview không giật rõ rệt khi bật bố cục + filter + beauty cùng lúc.
- [ ] Để chạy 5 phút liên tục: không nóng máy bất thường, không leak
      (quan sát RAM trong Android Studio Profiler nếu tiện).
- [ ] Overlay không nhảy giật loạn xạ (nếu rung nhiều → cần làm mượt bằng
      nội suy vị trí, đã dự trù trong kế hoạch v2).

### 2.7. Chỉnh ảnh sau chụp (GĐ2)

- [ ] Mở ảnh 4K trong editor: load < 2s, kéo 7 slider — preview đổi **mượt,
      không đơ** (render loop chống dồn).
- [ ] Lưu: ảnh **mới** xuất hiện trong gallery (gốc còn nguyên), chất lượng
      full-res, màu khớp preview editor.
- [ ] Reset (nút ↻) đưa mọi slider về trung tính.
- [ ] Chỉnh + lưu nhiều lần liên tiếp trên cùng 1 ảnh — không crash, không
      chậm dần (kiểm tra leak `ui.Image`).

### 2.8. Gallery

- [ ] Grid load nhanh với 50+ ảnh (thumbnail có cacheWidth).
- [ ] Viewer: vuốt chuyển ảnh, zoom 5x, số thứ tự "3/12" đúng.
- [ ] Xoá ảnh: có dialog xác nhận, xoá xong grid cập nhật; bản trong app Ảnh
      hệ thống **vẫn còn** (đúng thiết kế, dialog có nói rõ).
- [ ] Xoá đến ảnh cuối cùng → viewer tự đóng, gallery hiện trạng thái rỗng.

### 2.9. Thiết bị & cấu hình nên phủ

| Ưu tiên | Thiết bị | Lý do |
|---|---|---|
| 1 | Android tầm trung (SD 7xx, Android 13+) | Tiêu chí fps của GĐ1 |
| 2 | Android yếu (RAM 4GB, Android 10–11) | Hiệu năng shader + isolate encode |
| 3 | Android flagship (Vulkan) | Xác nhận đường Impeller/Vulkan |
| 4 | Máy Android GLES fallback (máy cũ) | Giả định trục Y của shader |
| 5 | iPhone (nếu có Mac để build) | Toàn bộ nhánh iOS chưa từng chạy |

### 2.10. Cách báo lỗi cho hiệu quả

Khi thấy sai, ghi lại: **model máy + Android version**, tính năng, thao tác,
kỳ vọng vs thực tế, và nếu là lỗi overlay/màu thì kèm **ảnh chụp màn hình**.
Lỗi toạ độ bố cục mô tả theo kiểu "khung lệch sang phải ~20% màn hình" là đủ
để khoanh vùng hàm cần sửa.

---

## PHẦN 3 — VIỆC CÒN LẠI (GĐ4, chưa làm)

- Paywall freemium: đếm 5 lượt AI/ngày, màn hình mua Pro (RevenueCat),
  restore purchase.
- Firebase: Analytics funnel, Crashlytics, Remote Config.
- Store listing VI/EN, privacy policy, icon + splash chính thức, đổi
  applicationId khỏi `com.example.doka_app`, ký release keystore.
- Nâng cấp có thể làm sau: thumbnail filter live trên carousel, làm mượt
  overlay bố cục bằng nội suy, LUT thật thay preset tham số, face landmark
  cho beauty, AI composition v2 (model TFLite chấm điểm bố cục).
