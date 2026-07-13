# Chỉnh sửa ảnh bằng AI (Gemini) — Thiết kế

**Ngày:** 2026-07-13
**Trạng thái:** Đã duyệt thiết kế, chờ lập kế hoạch triển khai

## Mục tiêu

Thêm khả năng **chỉnh sửa ảnh tạo sinh bằng Gemini** vào `EditScreen` hiện tại,
dưới dạng một tab "AI" bên cạnh tab "Chỉnh tay" (thông số shader) đã có. Người
dùng có thể bấm **nút nhanh** (preset) hoặc gõ **lệnh tự do**; Gemini trả về một
ảnh đã chỉnh, người dùng **xem trước rồi mới đồng ý**.

Đây là bổ sung cho editor cục bộ hiện tại, không thay thế:
- **Chỉnh tay** (đang có): shader on-device, tức thì, miễn phí, chỉnh thông số
  (phơi sáng, tương phản, hạt phim…).
- **AI** (mới): chỉnh tạo sinh theo câu lệnh (xoá phông, đổi trời, nâng nét,
  style phim) — mạnh hơn nhưng cần mạng, có độ trễ, tốn chi phí API.

## Quyết định thiết kế (đã chốt với người dùng)

1. **Chức năng:** cả nút nhanh lẫn ô nhập lệnh tự do.
2. **Vị trí:** một tab "AI" **bên trong `EditScreen`** hiện tại, chuyển qua lại
   với tab "Chỉnh tay".
3. **Luồng kết quả:** **xem trước → Dùng / Huỷ.** "Dùng" thì ảnh AI trở thành
   ảnh nền mới (chỉnh tay tiếp được); "Huỷ" giữ nguyên ảnh cũ.
4. **Nút nhanh bản đầu:** 4 nút — Xoá phông/tách chủ thể, Đổi bầu trời, Nâng
   chất lượng (làm nét/giảm noise), Style phim analog (chất Doka).
5. **Độ phân giải:** dùng luôn độ phân giải Gemini (~1024px) nhưng **hiện cảnh
   báo nhẹ** "Ảnh AI có độ phân giải thấp hơn".

## Kiến trúc

Mô phỏng đúng pattern `GeminiSceneAnalyzer` đã có trong repo (service + hàm
thuần build/parse tách riêng để test được không cần mạng).

```
Tab "Chỉnh tay"  ←→  Tab "AI"
                       │
   [4 nút nhanh] [ô nhập lệnh] → gửi Gemini (loading, có Huỷ)
                       │
        Ảnh xem trước AI  →  [Dùng] → thành _source nền mới
                              │         (báo độ phân giải thấp, reset thông số,
                              │          rerender, dispose ảnh cũ)
                              [Huỷ] → giữ ảnh cũ
```

- Model: `gemini-2.5-flash-image:generateContent` (khác model analyzer
  `gemini-2.5-flash`).
- Dùng lại `GEMINI_API_KEY` qua `--dart-define`, `http.Client`, và
  `downscaleForVision` để nén ảnh gửi lên.
- **Request body khác analyzer:** KHÔNG có `responseSchema` /
  `responseMimeType: application/json`. Chỉ `contents` gồm prompt text + inline
  image. Response part chứa `inlineData.data` (base64 ảnh) → decode ra
  `Uint8List`.
- **Prompt tiếng Anh** (Gemini xử lý tốt hơn): map `{nhãn tiếng Việt → prompt
  tiếng Anh}`. Ô lệnh tự do lấy nguyên văn người dùng gõ.
- **Timeout** dài hơn analyzer (vd. 30s) vì tạo sinh ảnh chậm hơn.

## Các thành phần

| File | Việc |
|------|------|
| `lib/src/features/editor/ai/gemini_image_editor.dart` | Service `editImage({jpegBytes, prompt}) → Uint8List`. Ném lỗi rõ ràng: `MissingApiKeyException`, HTTP lỗi, "ảnh bị chặn an toàn". Timeout ~30s. |
| `lib/src/features/editor/ai/image_edit_request.dart` | Hàm thuần: `buildImageEditRequestBody(base64, prompt)` và `parseEditedImage(json) → Uint8List`. Phần test được không cần mạng. |
| `lib/src/features/editor/ai/quick_edits.dart` | Danh sách 4 nút nhanh: mỗi mục `{nhãn tiếng Việt, prompt tiếng Anh}`. |
| `lib/src/providers.dart` | Thêm `geminiImageEditorProvider` (giống provider analyzer). |
| `lib/src/features/editor/edit_screen.dart` | Thanh chuyển tab "Chỉnh tay / AI"; panel AI (4 nút + ô lệnh + nút gửi); overlay loading có Huỷ; lớp xem trước "Dùng / Huỷ"; dòng cảnh báo độ phân giải. |

### Chi tiết hành vi
- **Loading:** khi gửi, khoá panel + `CircularProgressIndicator` màu
  `DokaColors.brass`, có nút Huỷ để bỏ chờ.
- **"Dùng":** thay `_source` và `_previewBase` bằng ảnh AI đã decode, reset
  `_values` về neutral, gọi `_rerender()`. Giải phóng (`dispose`) ảnh cũ đúng
  cách như code hiện tại (dùng `addPostFrameCallback`).
- **"Huỷ":** bỏ ảnh preview AI, giữ nguyên trạng thái đang chỉnh.
- **Cảnh báo độ phân giải:** dòng chữ nhỏ khi hiện preview AI (phương án 2).

### Prompt nút nhanh (bản nháp, tinh chỉnh khi triển khai)
- **Xoá phông / tách chủ thể:** giữ nguyên chủ thể, làm nền mờ/xoá nền sạch.
- **Đổi bầu trời:** thay bầu trời (xanh trong hoặc hoàng hôn ấm), giữ tiền cảnh.
- **Nâng chất lượng:** tăng độ nét, giảm noise, giữ nguyên bố cục/nội dung.
- **Style phim analog:** áp tông màu phim analog đúng chất Doka (tông ấm, hạt
  nhẹ, tương phản mềm) — tham chiếu `film_preset.dart`.

## Xử lý lỗi
- Thiếu key → `MissingApiKeyException` → SnackBar "Chưa cấu hình GEMINI_API_KEY".
- Không mạng / timeout / HTTP lỗi → SnackBar báo lỗi, giữ nguyên ảnh.
- Response thiếu `candidates` hoặc không có phần ảnh (ảnh bị chặn an toàn) →
  ném Exception → SnackBar "Không tạo được ảnh (có thể bị chặn)".
- **Không có fallback on-device** (không thể tạo sinh offline).

## Test
- `test/image_edit_request_test.dart` — hàm thuần:
  - `buildImageEditRequestBody` đúng cấu trúc: có prompt text + inline image,
    KHÔNG có `responseSchema`.
  - `parseEditedImage` bóc đúng bytes từ JSON mẫu có `inlineData`.
  - Case thiếu `candidates` / thiếu phần ảnh → ném Exception.
- Không test gọi mạng thật (tốn tiền, cần key).

## Ngoài phạm vi bản đầu (ghi chú để sau)
- Upscale ảnh AI về độ phân giải gốc.
- Lịch sử nhiều bước undo/redo cho các lần chỉnh AI.
- Chỉnh theo vùng chọn (mask/inpaint).
- Thanh trượt so sánh gốc ↔ AI.
