/// Tỉ lệ khung ảnh (rộng/cao, máy cầm dọc).
enum CaptureAspect {
  r34('3:4', 3 / 4),
  r11('1:1', 1),
  r916('9:16', 9 / 16);

  const CaptureAspect(this.label, this.ratio);

  final String label;
  final double ratio;

  CaptureAspect get next =>
      CaptureAspect.values[(index + 1) % CaptureAspect.values.length];
}
