import 'package:flutter/material.dart';

import '../features/filters/film_preset.dart';

/// Hệ màu & kiểu chữ của Doka — cảm hứng từ một chiếc máy phim analog:
/// thân máy than ấm, điểm nhấn vàng đồng như đồng hồ đo sáng, chữ màu giấy phim.
///
/// Dùng token ở đây thay cho `Colors.black` / `Colors.amber` rải rác để cả app
/// đồng bộ một chất liệu.
abstract final class DokaColors {
  /// Thân máy — đen ngả nâu ấm, không phải đen tuyền OLED.
  static const body = Color(0xFF14110D);

  /// Bề mặt nổi nhẹ: thanh công cụ, chip filter ở trạng thái nghỉ.
  static const surface = Color(0xFF211C15);

  /// Bề mặt nổi hơn (viền, tách lớp).
  static const surfaceHigh = Color(0xFF2C261D);

  /// Điểm nhấn chính — vàng đồng đồng hồ đo sáng.
  static const brass = Color(0xFFE3B15A);

  /// Vàng đồng đậm — bóng kim loại của vòng nút chụp.
  static const brassDeep = Color(0xFF9C7636);

  /// Chữ chính — trắng ngả kem như giấy ảnh.
  static const ink = Color(0xFFF4EEE2);

  /// Chữ phụ — xám ấm.
  static const inkMuted = Color(0xFF9E9482);

  /// Chữ mờ / gợi ý.
  static const inkFaint = Color(0xFF6E665A);

  /// Đỏ nhả cò (điểm đỏ nhỏ trên nút chụp).
  static const shutter = Color(0xFFE7573F);

  /// Xanh báo "máy đã thẳng" của thước cân bằng.
  static const level = Color(0xFF7BE0A6);

  /// Dải cầu vồng mềm cho các khoảnh khắc AI (viền toast, hào quang).
  static const aurora = <Color>[
    Color(0xFFFF9E9E),
    Color(0xFFFFE29E),
    Color(0xFF9EDCFF),
    Color(0xFFD3B4FF),
  ];

  /// Nền kính mờ cho cụm nút nổi trên khung ngắm.
  static Color glass([double alpha = 0.42]) =>
      Colors.black.withValues(alpha: alpha);
}

/// Thang khoảng cách nhất quán.
abstract final class DokaSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class DokaRadius {
  static const chip = 22.0;
  static const card = 18.0;
  static const sheet = 24.0;
}

/// Kiểu chữ. Các số đo kỹ thuật (tỉ lệ khung, %, số ảnh) dùng monospace để
/// gợi cảm giác chỉ số trên đồng hồ đo sáng.
abstract final class DokaType {
  /// Nhãn chỉ số kỹ thuật — như vạch đo trên máy.
  static const TextStyle meter = TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    letterSpacing: 1.5,
    fontWeight: FontWeight.w600,
    color: DokaColors.ink,
  );

  /// Tiêu đề màn hình.
  static const TextStyle title = TextStyle(
    fontSize: 19,
    letterSpacing: 0.4,
    fontWeight: FontWeight.w600,
    color: DokaColors.ink,
  );

  static const TextStyle chip = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 13.5,
    height: 1.4,
    color: DokaColors.ink,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12.5,
    height: 1.35,
    color: DokaColors.inkMuted,
  );
}

/// Suy ra "màu của cuốn phim" từ khoa học màu của preset, để mỗi chip trong
/// dải filter mang đúng sắc của nó — dải chip đọc như một kệ phim.
///
/// Không nhằm chính xác vật lý, chỉ cần mỗi cuốn phim nhận ra được bằng màu.
Color presetSwatch(FilmPreset p) {
  // Preset trung tính (Gốc) → xám trung tính, báo "không nhuộm màu".
  if (p.isNeutral) return const Color(0xFFC4BEB2);

  // Nền giấy phim ấm.
  double r = 0.82, g = 0.78, b = 0.72;

  // Nhiệt màu: ấm đẩy về hổ phách, lạnh đẩy về lam-ngọc.
  r += p.temperature * 0.16;
  g += p.temperature * 0.04;
  b -= p.temperature * 0.20;

  // Tint: âm = xanh rêu, dương = hồng cánh sen.
  g += (-p.tint) * 0.18;
  r += p.tint * 0.10;
  b += p.tint * 0.06;

  // Nhuộm vùng sáng.
  r += (p.highlightTint[0] - 1) * p.highlightStrength * 2;
  g += (p.highlightTint[1] - 1) * p.highlightStrength * 2;
  b += (p.highlightTint[2] - 1) * p.highlightStrength * 2;

  // Nhuộm nhẹ vùng tối.
  r += p.shadowTint[0] * p.shadowStrength * 0.4;
  g += p.shadowTint[1] * p.shadowStrength * 0.4;
  b += p.shadowTint[2] * p.shadowStrength * 0.4;

  // Giảm bão hoà về đúng độ sáng riêng của nó.
  final luma = 0.299 * r + 0.587 * g + 0.114 * b;
  final s = p.saturation.clamp(0.0, 1.5);
  r = luma + (r - luma) * s;
  g = luma + (g - luma) * s;
  b = luma + (b - luma) * s;

  // Phim đen trắng: tương phản cao thì tối hơn (Noir đậm hơn Mono).
  if (p.saturation == 0) {
    final darken = (p.contrast - 1).clamp(0.0, 0.5) * 0.35;
    r -= darken;
    g -= darken;
    b -= darken;
  }

  // Fade nâng & làm dịu về màu kem.
  final f = p.fade;
  r += (0.86 - r) * f * 0.4;
  g += (0.84 - g) * f * 0.4;
  b += (0.80 - b) * f * 0.4;

  int c(double v) => (v * 255).clamp(0, 255).round();
  return Color.fromARGB(255, c(r), c(g), c(b));
}
