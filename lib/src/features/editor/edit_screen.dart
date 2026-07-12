import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../filters/film_preset.dart';
import '../filters/image_renderer.dart';
import '../filters/photo_encoder.dart';
import '../filters/photo_processor.dart';

/// Một thông số chỉnh được trong editor.
class _Adjustment {
  const _Adjustment(this.label, this.min, this.max, this.neutral);

  final String label;
  final double min;
  final double max;
  final double neutral;
}

/// Mã hoá RGBA → JPEG trong isolate riêng.
///
/// Phải là hàm CẤP CAO NHẤT (không phải method của State): closure gửi sang
/// isolate chỉ được bắt các tham số thuần (rgba/width/height đều gửi được).
/// Nếu đặt trong method, closure sẽ bắt luôn `this` → kéo theo `ui.Image` của
/// State (không gửi được) → lỗi "object is unsendable".
Future<Uint8List> _encodeJpegInIsolate(
  Uint8List rgba,
  int width,
  int height,
) {
  return Isolate.run(() => encodeRgbaToJpeg(rgba, width, height));
}

/// Chấm đồng nhỏ báo thông số đã bị chỉnh khỏi mặc định.
class _ChangedDot extends StatelessWidget {
  const _ChangedDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: DokaColors.brass,
      ),
    );
  }
}

const _adjustments = <_Adjustment>[
  _Adjustment('Phơi sáng', -1, 1, 0),
  _Adjustment('Tương phản', 0.5, 1.5, 1),
  _Adjustment('Nhiệt màu', -1, 1, 0),
  _Adjustment('Bão hoà', 0, 2, 1),
  _Adjustment('Fade', 0, 1, 0),
  _Adjustment('Vignette', 0, 1, 0),
  _Adjustment('Hạt', 0, 1, 0),
];

/// Chỉnh màu một ảnh đã chụp và lưu thành ảnh mới.
class EditScreen extends ConsumerStatefulWidget {
  const EditScreen({super.key, required this.file});

  final File file;

  @override
  ConsumerState<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends ConsumerState<EditScreen> {
  ui.Image? _source; // full-res, dùng khi lưu
  ui.Image? _previewBase; // downscale, dùng khi preview
  ui.Image? _rendered;

  final _values = [for (final a in _adjustments) a.neutral];
  int _selected = 0;
  bool _rendering = false;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _source?.dispose();
    _previewBase?.dispose();
    _rendered?.dispose();
    super.dispose();
  }

  FilmPreset _currentPreset() => FilmPreset(
        id: 'custom',
        name: 'Tuỳ chỉnh',
        exposure: _values[0],
        contrast: _values[1],
        temperature: _values[2],
        saturation: _values[3],
        fade: _values[4],
        vignette: _values[5],
        grain: _values[6],
      );

  Future<void> _load() async {
    final bytes = await widget.file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    _source = frame.image;
    _previewBase = await ImageRenderer.downscale(_source!, 1080);
    if (!mounted) return;
    await _rerender();
  }

  Future<void> _rerender() async {
    final base = _previewBase;
    if (base == null) return;
    if (_rendering) {
      _dirty = true;
      return;
    }
    _rendering = true;
    do {
      _dirty = false;
      final image = await ImageRenderer.filmPass(base, _currentPreset());
      if (!mounted) {
        image.dispose();
        _rendering = false;
        return;
      }
      final old = _rendered;
      setState(() => _rendered = image);
      if (old != null) {
        // Đợi frame hiện tại vẽ xong rồi mới giải phóng ảnh cũ.
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } while (_dirty);
    _rendering = false;
  }

  Future<void> _save() async {
    final source = _source;
    if (source == null || _saving) return;
    setState(() => _saving = true);
    try {
      final rendered = await ImageRenderer.filmPass(
        source,
        _currentPreset(),
        seed: math.Random().nextDouble() * 1000,
      );
      try {
        final raw =
            await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (raw == null) {
          throw StateError('Không đọc được dữ liệu ảnh sau khi render.');
        }
        final rgba = raw.buffer.asUint8List();
        final width = rendered.width;
        final height = rendered.height;
        final jpeg = await _encodeJpegInIsolate(rgba, width, height);
        final file = await ref.read(photoRepositoryProvider).savePhoto(jpeg);
        await PhotoProcessor.saveToSystemGallery(file);
      } finally {
        rendered.dispose();
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lưu thất bại: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adjustment = _adjustments[_selected];
    return Scaffold(
      backgroundColor: DokaColors.body,
      appBar: AppBar(
        backgroundColor: DokaColors.body,
        foregroundColor: DokaColors.ink,
        elevation: 0,
        title: const Text('Chỉnh ảnh', style: DokaType.title),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DokaColors.brass,
                ),
              ),
            )
          else
            IconButton(
              onPressed: _save,
              tooltip: 'Lưu ảnh mới',
              icon: const Icon(Icons.check, color: DokaColors.brass),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _rendered == null
                ? const Center(
                    child:
                        CircularProgressIndicator(color: DokaColors.brassDeep),
                  )
                : Padding(
                    padding: const EdgeInsets.all(DokaSpacing.md),
                    child: RawImage(image: _rendered, fit: BoxFit.contain),
                  ),
          ),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DokaSpacing.lg),
              itemCount: _adjustments.length,
              separatorBuilder: (_, _) => const SizedBox(width: DokaSpacing.sm),
              itemBuilder: (context, index) {
                final selected = index == _selected;
                final changed =
                    _values[index] != _adjustments[index].neutral;
                return GestureDetector(
                  onTap: () => setState(() => _selected = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? DokaColors.brass.withValues(alpha: 0.16)
                          : DokaColors.surface,
                      borderRadius: BorderRadius.circular(DokaRadius.chip),
                      border: Border.all(
                        color: selected
                            ? DokaColors.brass.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.06),
                        width: selected ? 1.2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _adjustments[index].label,
                          style: DokaType.chip.copyWith(
                            color: selected
                                ? DokaColors.ink
                                : DokaColors.inkMuted,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        if (changed) ...[
                          const SizedBox(width: 6),
                          const _ChangedDot(),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                DokaSpacing.lg, DokaSpacing.xs, DokaSpacing.sm, DokaSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _values[_selected],
                    min: adjustment.min,
                    max: adjustment.max,
                    onChanged: (v) {
                      setState(() => _values[_selected] = v);
                      _rerender();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Đặt lại tất cả',
                  onPressed: () {
                    setState(() {
                      for (var i = 0; i < _values.length; i++) {
                        _values[i] = _adjustments[i].neutral;
                      }
                    });
                    _rerender();
                  },
                  icon: const Icon(Icons.refresh, color: DokaColors.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
