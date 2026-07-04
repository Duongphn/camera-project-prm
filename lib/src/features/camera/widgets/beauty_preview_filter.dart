import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../filters/beauty_shader.dart';

/// Áp hiệu ứng làm mịn da lên preview camera theo thời gian thực.
/// Cùng cơ chế với FilmPreviewFilter: không hỗ trợ thì hiển thị gốc.
class BeautyPreviewFilter extends StatefulWidget {
  const BeautyPreviewFilter({
    super.key,
    required this.intensity,
    required this.child,
  });

  /// 0..1, 0 = tắt.
  final double intensity;
  final Widget child;

  @override
  State<BeautyPreviewFilter> createState() => _BeautyPreviewFilterState();
}

class _BeautyPreviewFilterState extends State<BeautyPreviewFilter> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    BeautyShaderProgram.load().then((program) {
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
        widget.intensity <= 0 ||
        !ui.ImageFilter.isShaderFilterSupported) {
      return widget.child;
    }
    // u_size và sampler input do engine tự gán ở chế độ ImageFilter.
    applyBeautyUniforms(shader, intensity: widget.intensity);
    return ImageFiltered(
      imageFilter: ui.ImageFilter.shader(shader),
      child: widget.child,
    );
  }
}
