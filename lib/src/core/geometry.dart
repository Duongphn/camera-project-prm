import 'dart:math' as math;
import 'dart:ui';

/// Khung crop ở giữa ảnh [width]x[height] theo tỉ lệ [aspect] (rộng/cao).
Rect centeredCropRect(int width, int height, double aspect) {
  assert(aspect > 0);
  var cropWidth = width.toDouble();
  var cropHeight = cropWidth / aspect;
  if (cropHeight > height) {
    cropHeight = height.toDouble();
    cropWidth = cropHeight * aspect;
  }
  return Rect.fromLTWH(
    (width - cropWidth) / 2,
    (height - cropHeight) / 2,
    cropWidth,
    cropHeight,
  );
}

/// Góc nghiêng (radian) của máy quanh trục nhìn khi cầm dọc,
/// tính từ gia tốc trọng trường. 0 = cân bằng.
double rollRadians(double ax, double ay) => math.atan2(-ax, ay);

/// Máy được coi là cân bằng khi nghiêng dưới [toleranceDegrees].
bool isLevel(double rollRad, {double toleranceDegrees = 2.0}) =>
    (rollRad * 180 / math.pi).abs() < toleranceDegrees;
