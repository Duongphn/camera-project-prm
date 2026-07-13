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
import 'ai/quick_edits.dart';

/// Chế độ chỉnh: thông số shader on-device, hoặc chỉnh tạo sinh bằng Gemini.
enum _EditMode { manual, ai }

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

  // Trạng thái tab AI.
  _EditMode _mode = _EditMode.manual;
  final _promptController = TextEditingController();
  bool _aiBusy = false;
  int _aiRequestId = 0; // token vô hiệu request khi người dùng huỷ
  ui.Image? _aiPreview; // ảnh AI đang xem trước (chưa "Dùng")

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
    _aiPreview?.dispose();
    _promptController.dispose();
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
    final image = await _decodeImage(bytes);
    if (!mounted) {
      image.dispose();
      return;
    }
    _source = image;
    _previewBase = await ImageRenderer.downscale(_source!, 1080);
    if (!mounted) return;
    await _rerender();
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
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

  /// Mã hoá ảnh nguồn hiện tại thành JPEG để gửi Gemini.
  Future<Uint8List> _sourceToJpeg(ui.Image image) async {
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) {
      throw StateError('Không đọc được dữ liệu ảnh nguồn.');
    }
    return _encodeJpegInIsolate(
      raw.buffer.asUint8List(),
      image.width,
      image.height,
    );
  }

  Future<void> _runAiEdit(String prompt) async {
    final source = _source;
    if (source == null || _aiBusy || prompt.trim().isEmpty) return;
    setState(() => _aiBusy = true);
    final requestId = ++_aiRequestId;
    try {
      final jpeg = await _sourceToJpeg(source);
      final bytes = await ref
          .read(geminiImageEditorProvider)
          .editImage(jpegBytes: jpeg, prompt: prompt);
      if (!mounted || requestId != _aiRequestId) return; // đã huỷ
      final preview = await _decodeImage(bytes);
      if (!mounted || requestId != _aiRequestId) {
        preview.dispose();
        return;
      }
      setState(() {
        _aiPreview?.dispose();
        _aiPreview = preview;
      });
    } catch (e) {
      if (mounted && requestId == _aiRequestId) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Chỉnh AI thất bại: $e')));
      }
    } finally {
      if (mounted && requestId == _aiRequestId) {
        setState(() => _aiBusy = false);
      }
    }
  }

  void _cancelAi() {
    _aiRequestId++; // vô hiệu request đang chờ
    setState(() => _aiBusy = false);
  }

  void _discardAi() {
    setState(() {
      _aiPreview?.dispose();
      _aiPreview = null;
    });
  }

  Future<void> _applyAiResult() async {
    final preview = _aiPreview;
    if (preview == null) return;
    // Tạo bản downscale TRƯỚC khi đổi state: nếu lỗi/huỷ giữa chừng thì chưa
    // đụng tới _source/_previewBase hiện tại.
    final ui.Image newPreviewBase;
    try {
      newPreviewBase = await ImageRenderer.downscale(preview, 1080);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không dùng được ảnh AI: $e')));
      }
      return;
    }
    if (!mounted) {
      // Widget đã huỷ trong lúc downscale: dispose() đã lo _aiPreview (=preview);
      // chỉ cần bỏ ảnh vừa tạo, chưa gắn vào field nào.
      newPreviewBase.dispose();
      return;
    }
    // Từ đây tới lúc swap KHÔNG còn await → dispose() không thể chen vào giữa.
    final oldSource = _source;
    final oldPreviewBase = _previewBase;
    _source = preview; // ảnh AI thành nền mới
    _previewBase = newPreviewBase;
    _aiPreview = null; // quyền sở hữu preview đã chuyển sang _source
    for (var i = 0; i < _values.length; i++) {
      _values[i] = _adjustments[i].neutral;
    }
    oldSource?.dispose();
    oldPreviewBase?.dispose();
    setState(() => _mode = _EditMode.manual);
    await _rerender();
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
          Expanded(child: _imageArea()),
          if (_aiPreview != null)
            _aiPreviewActions()
          else ...[
            _modeToggle(),
            if (_mode == _EditMode.manual)
              ..._manualControls(adjustment)
            else
              _aiPanel(),
          ],
        ],
      ),
    );
  }

  Widget _imageArea() {
    final preview = _aiPreview;
    final Widget content;
    if (preview != null) {
      content = Padding(
        padding: const EdgeInsets.all(DokaSpacing.md),
        child: RawImage(image: preview, fit: BoxFit.contain),
      );
    } else if (_rendered == null) {
      content = const Center(
        child: CircularProgressIndicator(color: DokaColors.brassDeep),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(DokaSpacing.md),
        child: RawImage(image: _rendered, fit: BoxFit.contain),
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: content),
        if (_aiBusy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: DokaColors.brass),
                    const SizedBox(height: DokaSpacing.md),
                    Text('Đang xử lý AI…',
                        style: DokaType.chip.copyWith(color: DokaColors.ink)),
                    const SizedBox(height: DokaSpacing.md),
                    TextButton(onPressed: _cancelAi, child: const Text('Huỷ')),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _aiPreviewActions() {
    return Padding(
      padding: const EdgeInsets.all(DokaSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Ảnh AI có độ phân giải thấp hơn ảnh gốc.',
            style: DokaType.chip.copyWith(color: DokaColors.inkMuted),
          ),
          const SizedBox(height: DokaSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _discardAi,
                  child: const Text('Huỷ'),
                ),
              ),
              const SizedBox(width: DokaSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: _applyAiResult,
                  child: const Text('Dùng'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DokaSpacing.lg,
        vertical: DokaSpacing.xs,
      ),
      child: Row(
        children: [
          _modeTab('Chỉnh tay', _EditMode.manual),
          const SizedBox(width: DokaSpacing.sm),
          _modeTab('AI', _EditMode.ai),
        ],
      ),
    );
  }

  Widget _modeTab(String label, _EditMode mode) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        child: Text(
          label,
          style: DokaType.chip.copyWith(
            color: selected ? DokaColors.ink : DokaColors.inkMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  List<Widget> _manualControls(_Adjustment adjustment) {
    return [
      SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: DokaSpacing.lg),
          itemCount: _adjustments.length,
          separatorBuilder: (_, _) => const SizedBox(width: DokaSpacing.sm),
          itemBuilder: (context, index) {
            final selected = index == _selected;
            final changed = _values[index] != _adjustments[index].neutral;
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
                        color: selected ? DokaColors.ink : DokaColors.inkMuted,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
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
    ];
  }

  Widget _aiPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          DokaSpacing.lg, DokaSpacing.xs, DokaSpacing.lg, DokaSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: DokaSpacing.sm,
            runSpacing: DokaSpacing.sm,
            children: [
              for (final q in quickEdits)
                GestureDetector(
                  onTap: _aiBusy ? null : () => _runAiEdit(q.prompt),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: DokaColors.surface,
                      borderRadius: BorderRadius.circular(DokaRadius.chip),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Text(
                      q.label,
                      style: DokaType.chip.copyWith(color: DokaColors.ink),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: DokaSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  enabled: !_aiBusy,
                  style: DokaType.chip.copyWith(color: DokaColors.ink),
                  decoration: InputDecoration(
                    hintText: 'Nhập lệnh chỉnh sửa…',
                    hintStyle:
                        DokaType.chip.copyWith(color: DokaColors.inkMuted),
                    filled: true,
                    fillColor: DokaColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DokaRadius.chip),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: _aiBusy ? null : _runAiEdit,
                ),
              ),
              const SizedBox(width: DokaSpacing.sm),
              IconButton(
                tooltip: 'Chỉnh bằng AI',
                onPressed:
                    _aiBusy ? null : () => _runAiEdit(_promptController.text),
                icon: const Icon(Icons.auto_awesome, color: DokaColors.brass),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
