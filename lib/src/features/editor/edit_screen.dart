import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        final jpeg = await Isolate.run(
          () => encodeRgbaToJpeg(rgba, width, height),
        );
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Chỉnh ảnh'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(onPressed: _save, icon: const Icon(Icons.check)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _rendered == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white24),
                  )
                : RawImage(image: _rendered, fit: BoxFit.contain),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _adjustments.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final selected = index == _selected;
                final changed =
                    _values[index] != _adjustments[index].neutral;
                return GestureDetector(
                  onTap: () => setState(() => _selected = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.white10,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      changed
                          ? '${_adjustments[index].label} •'
                          : _adjustments[index].label,
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 16),
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
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
