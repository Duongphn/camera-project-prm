/// Một preset màu phim. Mọi giá trị mặc định là trung tính (ảnh gốc).
class FilmPreset {
  const FilmPreset({
    required this.id,
    required this.name,
    this.exposure = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.temperature = 0,
    this.tint = 0,
    this.fade = 0,
    this.vignette = 0,
    this.grain = 0,
    this.shadowTint = const [0, 0, 0],
    this.shadowStrength = 0,
    this.highlightTint = const [1, 1, 1],
    this.highlightStrength = 0,
  });

  final String id;
  final String name;
  final double exposure;
  final double contrast;
  final double saturation;
  final double temperature;
  final double tint;
  final double fade;
  final double vignette;
  final double grain;
  final List<double> shadowTint;
  final double shadowStrength;
  final List<double> highlightTint;
  final double highlightStrength;

  bool get isNeutral =>
      exposure == 0 &&
      contrast == 1 &&
      saturation == 1 &&
      temperature == 0 &&
      tint == 0 &&
      fade == 0 &&
      vignette == 0 &&
      grain == 0 &&
      shadowStrength == 0 &&
      highlightStrength == 0;
}

/// Bộ preset của Giai đoạn 1. Tên gốc, không dùng tên phim thương mại.
const List<FilmPreset> filmPresets = [
  FilmPreset(id: 'original', name: 'Gốc'),
  FilmPreset(
    id: 'saigon89',
    name: 'Sài Gòn 89',
    temperature: 0.45,
    saturation: 1.08,
    contrast: 1.06,
    fade: 0.15,
    grain: 0.25,
    vignette: 0.2,
    highlightTint: [1.0, 0.93, 0.75],
    highlightStrength: 0.06,
  ),
  FilmPreset(
    id: 'dalat',
    name: 'Đà Lạt',
    exposure: 0.12,
    contrast: 0.92,
    saturation: 0.85,
    temperature: -0.1,
    fade: 0.35,
    grain: 0.18,
    shadowTint: [0.55, 0.72, 0.72],
    shadowStrength: 0.05,
  ),
  FilmPreset(
    id: 'halong',
    name: 'Hạ Long',
    temperature: -0.4,
    saturation: 0.95,
    contrast: 1.05,
    grain: 0.15,
    shadowTint: [0.4, 0.5, 0.75],
    shadowStrength: 0.08,
  ),
  FilmPreset(
    id: 'chodem',
    name: 'Chợ Đêm',
    contrast: 1.12,
    saturation: 1.05,
    vignette: 0.3,
    grain: 0.2,
    shadowTint: [0.25, 0.5, 0.55],
    shadowStrength: 0.1,
    highlightTint: [1.0, 0.85, 0.65],
    highlightStrength: 0.08,
  ),
  FilmPreset(
    id: 'mono400',
    name: 'Mono 400',
    saturation: 0,
    contrast: 1.08,
    fade: 0.1,
    grain: 0.35,
    vignette: 0.25,
  ),
  FilmPreset(
    id: 'noir',
    name: 'Noir',
    saturation: 0,
    contrast: 1.3,
    exposure: -0.05,
    grain: 0.3,
    vignette: 0.4,
  ),
  FilmPreset(
    id: 'retro76',
    name: 'Retro 76',
    saturation: 0.7,
    temperature: 0.3,
    fade: 0.4,
    grain: 0.3,
    vignette: 0.2,
    highlightTint: [0.98, 0.92, 0.78],
    highlightStrength: 0.1,
  ),
  FilmPreset(
    id: 'xanhreu',
    name: 'Xanh Rêu',
    tint: -0.25,
    saturation: 0.9,
    contrast: 0.98,
    fade: 0.2,
    grain: 0.2,
    shadowTint: [0.45, 0.6, 0.45],
    shadowStrength: 0.06,
  ),
  FilmPreset(
    id: 'kem',
    name: 'Kem',
    exposure: 0.08,
    contrast: 0.95,
    saturation: 0.92,
    temperature: 0.18,
    fade: 0.28,
    grain: 0.12,
    highlightTint: [1.0, 0.96, 0.88],
    highlightStrength: 0.08,
  ),
];
