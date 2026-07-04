import 'dart:typed_data';

/// Ngưỡng tin cậy tối thiểu để một nhãn được tính.
const double kLabelConfidenceThreshold = 0.6;

/// Ảnh tối hơn mức này được coi là cảnh đêm.
const double kNightLumaThreshold = 0.22;

/// Chọn preset theo nhãn cảnh (đã lowercase) và độ sáng trung bình (0..1).
/// Logic thuần để test được, không phụ thuộc ML Kit.
String suggestPresetId({
  required Map<String, double> labels,
  required double avgLuma,
}) {
  bool has(List<String> keys) =>
      keys.any((k) => (labels[k] ?? 0) >= kLabelConfidenceThreshold);

  if (avgLuma < kNightLumaThreshold) return 'chodem';
  if (has(['selfie', 'person', 'skin', 'smile', 'fashion', 'hair'])) {
    return 'kem';
  }
  if (has(['food', 'dessert', 'cuisine', 'cooking', 'drink', 'coffee'])) {
    return 'saigon89';
  }
  if (has(['sunset', 'dawn', 'dusk'])) return 'saigon89';
  if (has(['sky', 'beach', 'sea', 'ocean', 'lake', 'water', 'snow'])) {
    return 'halong';
  }
  if (has(['plant', 'tree', 'flower', 'grass', 'jungle', 'garden', 'leaf'])) {
    return 'xanhreu';
  }
  if (has(['building', 'street', 'architecture', 'vehicle', 'motorcycle'])) {
    return 'retro76';
  }
  return 'dalat';
}

/// Độ sáng trung bình (0..1) của buffer RGBA thô.
double averageLuma(Uint8List rgba) {
  if (rgba.isEmpty) return 0;
  final pixels = rgba.length ~/ 4;
  var total = 0.0;
  for (var i = 0; i < pixels; i++) {
    total += 0.2126 * rgba[i * 4] +
        0.7152 * rgba[i * 4 + 1] +
        0.0722 * rgba[i * 4 + 2];
  }
  return total / pixels / 255;
}
