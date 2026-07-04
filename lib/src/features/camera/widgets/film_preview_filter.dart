import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../filters/film_preset.dart';
import '../../filters/film_shader.dart';

/// Áp filter phim lên preview camera theo thời gian thực bằng
/// ImageFilter.shader (chỉ hỗ trợ Impeller). Nếu backend không hỗ trợ,
/// hiển thị preview gốc — ảnh chụp vẫn được bake filter như thường.
class FilmPreviewFilter extends StatefulWidget {
  const FilmPreviewFilter({
    super.key,
    required this.preset,
    required this.child,
  });

  final FilmPreset preset;
  final Widget child;

  @override
  State<FilmPreviewFilter> createState() => _FilmPreviewFilterState();
}

class _FilmPreviewFilterState extends State<FilmPreviewFilter> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    FilmShaderProgram.load().then((program) {
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null ||
        widget.preset.isNeutral ||
        !ui.ImageFilter.isShaderFilterSupported) {
      return widget.child;
    }
    // u_size và sampler input do engine tự gán ở chế độ ImageFilter.
    applyFilmUniforms(shader, widget.preset);
    return ImageFiltered(
      imageFilter: ui.ImageFilter.shader(shader),
      child: widget.child,
    );
  }
}
