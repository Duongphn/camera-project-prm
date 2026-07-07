# Kế hoạch triển khai app camera kiểu Doka Cam (Flutter)

## 1. Nghiên cứu app gốc

**Doka Cam** (Beijing Yingdong Guangnian Technology Co., Ltd.) — camera AI tối giản, hiện chỉ có iOS (161.7 MB, iOS 13+), đang viral tại Việt Nam. Định vị: "camera sạch, không mạng xã hội, không rác" — chỉ tập trung chụp ảnh đẹp.

### Tính năng cốt lõi
| Tính năng | Mô tả | Công nghệ suy đoán |
|---|---|---|
| AI Composition (bố cục thời gian thực) | Chạm 1 lần để phân tích khung cảnh, AI gợi ý bố cục bằng AR guide (mũi tên/khung dẫn hướng); long-press để đánh dấu chủ thể | Model CV on-device: subject/saliency detection + model chấm điểm bố cục (train trên ảnh smartphone đẹp), chạy real-time trên preview qua Core ML/Metal |
| AI Filter suggestion | Tự gợi ý filter phù hợp theo môi trường chụp | Model phân loại cảnh (scene classification) on-device |
| Film filters | Bộ filter màu phim cổ điển, "không over-processing" | 3D LUT + grain/halation render bằng GPU shader |
| Beauty | Làm đẹp miễn phí hoàn toàn | Face detection/landmark + skin smoothing shader |
| Camera tối giản | Không feed, không social | AVFoundation, UI thuần camera |

### Mô hình kinh doanh
- Freemium: free 5 lượt AI composition/filter mỗi ngày, một phần filter, beauty free toàn bộ.
- Pro subscription (giá VN): tuần 49.000đ, tháng 79.000–119.000đ, năm 499.000đ → unlock AI không giới hạn + toàn bộ filter.
- Privacy: thu thập vị trí + ảnh/video, không gắn danh tính. AI chạy chủ yếu on-device.

### Cơ hội thị trường
App gốc chưa có Android chính thức (người dùng VN than phiền điều này trên Threads/TikTok) → làm bản Flutter đa nền tảng là lợi thế cạnh tranh rõ ràng.

## 2. Tech stack đề xuất (Flutter)

| Lớp | Lựa chọn | Ghi chú |
|---|---|---|
| Framework | Flutter (dự án `doka_app` hiện tại) | 1 codebase iOS + Android |
| Camera | `camerawesome` hoặc `camera` + platform channel (CameraX/AVFoundation) | cần stream frame để phân tích AI |
| Render filter real-time | Flutter `FragmentProgram` (GLSL/SkSL shader) áp 3D LUT + grain lên preview; fallback native (Metal/OpenGL) nếu hiệu năng không đủ | LUT dạng .png 512x512 (33x33x33) |
| ML on-device | `google_mlkit_face_detection`, `google_mlkit_subject_segmentation`, `google_mlkit_image_labeling`; model tùy biến qua `tflite_flutter` | MediaPipe cho face mesh nếu cần beauty nâng cao |
| AI composition (giai đoạn sau) | TFLite model saliency + composition scoring (tham khảo hướng GAIC/VFN) hoặc gọi API server | bắt đầu bằng rule-based |
| Sensor | `sensors_plus` (gyro/level cân đường chân trời) | phần "AR guide" cơ bản |
| State | Riverpod hoặc Bloc | |
| Lưu ảnh | `gal` / MediaStore + PhotoKit | xử lý ảnh full-res bằng isolate |
| IAP | `in_app_purchase` hoặc RevenueCat (`purchases_flutter`) | RevenueCat khuyến nghị — đỡ tự xây backend receipt |
| Backend | Firebase: Analytics, Crashlytics, Remote Config (bật/tắt tính năng, config giá), App Check | không cần server riêng ở MVP |

## 3. Lộ trình 4 giai đoạn

### Giai đoạn 1 — MVP camera + filter ✅ (đã code xong, chờ test máy thật)
- Màn hình camera tối giản: preview, chụp, đổi camera trước/sau, flash, tỉ lệ khung (3:4, 9:16, 1:1), grid rule-of-thirds, level cân bằng bằng gyro.
- 8–10 filter film LUT render real-time trên preview + áp lên ảnh full-res khi lưu.
- Thư viện ảnh đã chụp trong app, lưu về máy.
- Nền tảng: Android trước (thị trường bỏ trống), iOS ngay sau.
- **Định nghĩa xong:** chụp + filter mượt ≥30fps trên máy tầm trung (Snapdragon 7xx).

### Giai đoạn 2 — Beauty + gợi ý filter ✅ (đã code xong, chờ test máy thật)
- ✅ Beauty: shader làm mịn da theo mặt nạ tông da YCbCr (bilateral, edge-preserving), slider 0–100, chạy cả preview lẫn bake. *Thay đổi so với kế hoạch: không dùng face detection real-time — mặt nạ tông da trong shader rẻ và đủ tốt cho v1; face landmark để dành nâng cấp sau.*
- ✅ AI gợi ý filter: nút ✨ chụp 1 frame → ML Kit image labeling (on-device) + độ sáng trung bình → map sang preset bằng rule thuần (có test). Fallback theo độ sáng khi ML Kit không khả dụng.
- ✅ Chỉnh ảnh sau chụp (EditScreen từ gallery): phơi sáng, tương phản, nhiệt màu, bão hoà, fade, vignette, hạt — preview GPU, lưu thành ảnh mới.

### Giai đoạn 3 — AI Composition (4–6 tuần, phần khó nhất)
- ✅ v1 rule-based (đã code xong, chờ test máy thật): ML Kit **object detection stream mode** (model bundled, có tracking ID — thay cho subject segmentation vì segmentation chỉ có Android và không realtime) xác định chủ thể → điểm thirds gần nhất (chủ thể >35% khung thì căn giữa) → overlay khung + mũi tên + điểm đích, chuyển xanh + haptic khi vào bố cục; long-press khoá chủ thể theo tracking ID.
- ✅ v1.5 guided shot kiểu Doka (đã code xong, chờ test máy thật): 4 pha off→analyzing→aiming→framing — hiệu ứng chấm sáng phân tích, vòng ngắm cầu vồng, khung crop Gemini + tự động zoom (căn tâm trước, zoom sau), tự áp filter kèm toast giải thích. Spec: docs/superpowers/specs/2026-07-06-guided-ai-composition-design.md.
- ⚠️ 3 giả định phải kiểm chứng trên máy thật: analysis frame và preview cùng center-crop; chiều mirror camera trước; hệ toạ độ box ML Kit sau xoay. Toàn bộ toán map nằm trong `composition_advisor.dart` (pure, có test) — lệch thì chỉnh một chỗ.
- ⚠️ Giả định thứ 4 (mới): cropRect Gemini trả về khớp vùng nhìn thấy sau center-crop preview; toán map nằm trong _runCloudCompositionAnalysis → mapImageRectToView.
- ⬜ v2 ML: model chấm điểm bố cục TFLite (dataset ảnh mobile đẹp) — R&D riêng, không chặn release.

### Giai đoạn 4 — Monetization + phát hành (2–3 tuần)
- Paywall: free 5 lượt AI/ngày (đếm local + Remote Config), Pro unlock tất cả; giá tham khảo app gốc.
- RevenueCat + màn hình paywall, restore purchase.
- Firebase Analytics funnel (mở app → chụp → dùng AI → paywall → mua), Crashlytics.
- Store listing (VI + EN), screenshot, privacy policy, App Store Review/Google Play Data Safety.

## 4. Rủi ro chính
1. **Hiệu năng filter real-time trong Flutter** — rủi ro cao nhất; nếu FragmentProgram không đạt, phải xuống native view + Metal/OpenGL. → Spike kỹ thuật 2–3 ngày ngay đầu giai đoạn 1.
2. **Chất lượng AI composition** — khó đạt như app gốc (họ có model tự train); v1 rule-based phải đủ "có cảm giác thông minh".
3. **Pháp lý:** không copy tên "Doka", UI, asset filter của app gốc — chỉ học concept.
4. **Ảnh full-res + shader**: xử lý ảnh 12–50MP cần pipeline riêng (isolate/native), không dùng chung path với preview.
