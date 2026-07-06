import 'dart:ui';

/// Kết quả phân tích một ảnh tĩnh (từ Gemini hoặc fallback on-device).
class SceneAnalysis {
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

  /// Id filter được chọn — luôn là id hợp lệ trong filmPresets.
  final String presetId;

  /// Vì sao chọn preset này (hiển thị cho người dùng).
  final String? reason;

  /// Mô tả ánh sáng/tông màu/bối cảnh.
  final String? mood;

  /// Điểm đặt chủ thể đẹp nhất, 0..1 viewfinder (gốc trên-trái). Có thể null.
  final Offset? targetPoint;

  /// Vùng crop đẹp nhất trên ảnh, 0..1 (gốc trên-trái). Null nếu Gemini
  /// không trả hoặc không hợp lệ.
  final Rect? cropRect;

  /// Lời khuyên bố cục chi tiết (tiếng Việt) để hiện cho người dùng.
  final String? advice;

  /// Mẹo bố cục ngắn (tối đa 3).
  final List<String> tips;

  /// true = từ Gemini; false = fallback on-device.
  final bool fromCloud;
}
