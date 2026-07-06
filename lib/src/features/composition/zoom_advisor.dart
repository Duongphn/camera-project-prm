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
