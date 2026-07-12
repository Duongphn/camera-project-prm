import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/theme.dart';
import '../../providers.dart';
import '../analysis/scene_analysis.dart';
import '../composition/composition_advisor.dart';
import '../composition/composition_overlay.dart';
import '../composition/frame_guide_overlay.dart';
import '../composition/subject_detector.dart';
import '../composition/zoom_advisor.dart';
import '../filters/film_preset.dart';
import '../filters/photo_processor.dart';
import '../gallery/gallery_screen.dart';
import 'capture_aspect.dart';
import 'widgets/ai_toast_card.dart';
import 'widgets/analyzing_sparkle_overlay.dart';
import 'widgets/beauty_preview_filter.dart';
import 'widgets/film_preview_filter.dart';
import 'widgets/filter_carousel.dart';
import 'widgets/grid_overlay.dart';
import 'widgets/level_indicator.dart';

/// Trạng thái AI bố cục: tắt → phân tích (giữ yên máy) → dẫn ngắm
/// (dấu + vào vòng cầu vồng) → khung crop + tự động zoom.
enum _CompositionPhase { off, analyzing, aiming, framing }

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  FlashMode _flash = FlashMode.off;
  CaptureAspect _aspect = CaptureAspect.r34;
  bool _showGrid = true;
  int _presetIndex = 0;
  bool _processing = false;
  double _beauty = 0;
  bool _showBeautySlider = false;
  bool _suggesting = false;
  _CompositionPhase _compositionPhase = _CompositionPhase.off;
  CompositionAdvice? _advice;
  SubjectDetector? _subjectDetector;
  bool _wasAligned = false;
  Offset? _fixedTarget;
  int? _candidateId;
  int _candidateFrames = 0;
  bool _manualLock = false;
  bool _lostNotified = false;
  Offset? _cloudTarget;
  Offset? _scenicTarget; // 0..1 viewfinder — điểm cảnh đẹp khi chưa có chủ thể
  bool _cloudResolved = true;
  List<String> _cloudTips = const [];
  int _compositionAnalyzeToken = 0;
  Rect? _cloudCrop; // 0..1 viewfinder, đã map + clamp
  String? _cloudAdvice;
  String? _aiToast;
  bool _needMoreZoom = false;
  double _maxZoom = 1;
  AnimationController? _zoomAnimation;
  String? _error;

  FilmPreset get _preset => filmPresets[_presetIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _subjectDetector?.close();
    _stopZoomAnimation();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      controller.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _startController(_cameraIndex);
    }
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'Không tìm thấy camera trên thiết bị.');
        return;
      }
      await _startController(0);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không mở được camera: $e');
    }
  }

  Future<void> _startController(int index) async {
    final old = _controller;
    if (old != null) {
      _controller = null;
      if (mounted) setState(() {});
      await old.dispose();
    }
    try {
      final controller = CameraController(
        _cameras[index],
        ResolutionPreset.ultraHigh,
        enableAudio: false,
        // Format stream cho ML Kit; ảnh chụp (takePicture) vẫn là JPEG.
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      double maxZoom = 1;
      try {
        maxZoom = await controller.getMaxZoomLevel();
      } on CameraException {
        // giữ 1 — coi như không zoom được
      }
      await controller.setFlashMode(_flash);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraIndex = index;
        _error = null;
        _maxZoom = maxZoom;
      });
      if (_compositionPhase != _CompositionPhase.off) {
        // Camera mới (flip/resume) → phân tích lại từ đầu.
        _subjectDetector?.unlock();
        _resetAnalysisState();
        _compositionPhase = _CompositionPhase.analyzing;
        await _startCompositionStream();
      }
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = 'Không mở được camera: ${e.description}');
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _processing) return;
    await _startController((_cameraIndex + 1) % _cameras.length);
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
      setState(() => _flash = next);
    } on CameraException {
      // Một số camera trước không có flash — giữ nguyên.
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _processing) {
      return;
    }
    setState(() => _processing = true);
    // Chụp giữa chừng zoom: dừng hẳn animation (dispose) để giữ mức zoom
    // hiện tại của camera, tránh controller còn sống chạy ngầm không cần thiết.
    _stopZoomAnimation();
    try {
      await _pauseCompositionStream();
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      final result = await PhotoProcessor.processAndSave(
        bytes: bytes,
        preset: _preset,
        aspect: _aspect.ratio,
        repository: ref.read(photoRepositoryProvider),
        beauty: _beauty,
      );
      if (mounted && !result.savedToGallery) {
        _showMessage(
          'Đã lưu trong app. Cấp quyền thư viện để lưu vào máy.',
        );
      }
    } catch (e) {
      if (mounted) _showMessage('Chụp ảnh thất bại: $e');
    } finally {
      await _resumeCompositionStream();
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Chụp một ảnh tĩnh, phân tích bằng Gemini (fallback ML Kit khi offline) và tự chọn filter.
  Future<void> _suggestFilter() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _processing ||
        _suggesting) {
      return;
    }
    setState(() => _suggesting = true);
    try {
      await _pauseCompositionStream();
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      SceneAnalysis analysis;
      try {
        analysis = await ref
            .read(sceneAnalyzerProvider)
            .analyze(jpegBytes: bytes, filePath: shot.path);
      } catch (_) {
        analysis = await ref
            .read(offlineAnalyzerProvider)
            .analyze(jpegBytes: bytes, filePath: shot.path);
      }
      final index = filmPresets.indexWhere((p) => p.id == analysis.presetId);
      if (mounted && index >= 0) {
        setState(() => _presetIndex = index);
        final preset = filmPresets[index];
        final reason = analysis.reason;
        final suffix = (analysis.fromCloud && reason != null) ? ' — $reason' : '';
        _showMessage('Gợi ý filter: ${preset.name} ✨$suffix');
      }
    } catch (e) {
      if (mounted) _showMessage('Không gợi ý được filter: $e');
    } finally {
      await _resumeCompositionStream();
      if (mounted) setState(() => _suggesting = false);
    }
  }

  // ---- AI bố cục: bấm ⊹ → phân tích 1 lần → dẫn hướng tới nốt tròn ----

  void _resetAnalysisState() {
    _fixedTarget = null;
    _candidateId = null;
    _candidateFrames = 0;
    _manualLock = false;
    _lostNotified = false;
    _wasAligned = false;
    _advice = null;
    _cloudTarget = null;
    _scenicTarget = null;
    _cloudResolved = true;
    _cloudTips = const [];
    _cloudCrop = null;
    _cloudAdvice = null;
    _aiToast = null;
    _needMoreZoom = false;
    _stopZoomAnimation();
  }

  void _stopZoomAnimation() {
    _zoomAnimation?.dispose();
    _zoomAnimation = null;
  }

  /// Dừng animation và trả zoom về 1 (khi thoát chế độ/flip camera).
  Future<void> _resetZoom() async {
    _stopZoomAnimation();
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.setZoomLevel(1);
      } on CameraException {
        // camera đang đóng — bỏ qua
      }
    }
  }

  /// Chụp 1 ảnh tĩnh, hỏi Gemini điểm bố cục đẹp nhất. Tạm dừng stream khi
  /// chụp rồi bật lại. Lỗi/offline → giữ _cloudTarget null (fallback hình học).
  Future<void> _runCloudCompositionAnalysis() async {
    final controller = _controller;
    final token = ++_compositionAnalyzeToken;
    _cloudResolved = false;
    _cloudTarget = null;
    _scenicTarget = null;
    _cloudTips = const [];
    if (controller == null || !controller.value.isInitialized) {
      if (token == _compositionAnalyzeToken) _cloudResolved = true;
      return;
    }
    try {
      await _pauseCompositionStream();
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      final analysis = await ref
          .read(sceneAnalyzerProvider)
          .analyze(jpegBytes: bytes, filePath: shot.path);
      if (token != _compositionAnalyzeToken) return; // đã bị lần mới thay

      final camera = _cameras[_cameraIndex];
      final mirror = camera.lensDirection == CameraLensDirection.front;
      if (analysis.targetPoint != null ||
          analysis.cropRect != null ||
          analysis.scenicPoint != null) {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final upright = img.bakeOrientation(decoded);
          final imageSize =
              Size(upright.width.toDouble(), upright.height.toDouble());
          final rawScenic = analysis.scenicPoint;
          if (rawScenic != null) {
            final mapped = mapImagePointToView(
              point: rawScenic,
              imageSize: imageSize,
              viewAspect: _aspect.ratio,
              mirrorX: mirror,
            );
            _scenicTarget = Offset(
              mapped.dx.clamp(0.0, 1.0),
              mapped.dy.clamp(0.0, 1.0),
            );
          }
          final rawTarget = analysis.targetPoint;
          if (rawTarget != null) {
            final mapped = mapImagePointToView(
              point: rawTarget,
              imageSize: imageSize,
              viewAspect: _aspect.ratio,
              mirrorX: mirror,
            );
            _cloudTarget = Offset(
              mapped.dx.clamp(0.0, 1.0),
              mapped.dy.clamp(0.0, 1.0),
            );
          }
          final crop = analysis.cropRect;
          if (crop != null) {
            final mapped = mapImageRectToView(
              rect: Rect.fromLTWH(
                crop.left * imageSize.width,
                crop.top * imageSize.height,
                crop.width * imageSize.width,
                crop.height * imageSize.height,
              ),
              imageSize: imageSize,
              viewAspect: _aspect.ratio,
              mirrorX: mirror,
            );
            final clamped = Rect.fromLTRB(
              mapped.left.clamp(0.0, 1.0),
              mapped.top.clamp(0.0, 1.0),
              mapped.right.clamp(0.0, 1.0),
              mapped.bottom.clamp(0.0, 1.0),
            );
            // Crop quá bé sau clamp = vùng đề xuất nằm ngoài phần nhìn thấy.
            if (clamped.width > 0.05 && clamped.height > 0.05) {
              _cloudCrop = clamped;
            }
          }
          // Không có điểm ngắm riêng → ngắm vào tâm vùng crop.
          _cloudTarget ??= _cloudCrop?.center;
        }
      }
      _cloudTips = analysis.tips;
      _cloudAdvice = analysis.advice;

      // Tự áp filter đề xuất + toast giải thích (kiểu Doka).
      final presetIdx =
          filmPresets.indexWhere((p) => p.id == analysis.presetId);
      if (mounted) {
        setState(() {
          if (presetIdx >= 0) _presetIndex = presetIdx;
          _aiToast = _buildFilterToast(analysis, presetIdx);
        });
      }
    } catch (_) {
      // giữ null → fallback hình học
    } finally {
      if (token == _compositionAnalyzeToken) {
        _cloudResolved = true;
        await _resumeCompositionStream();
      }
    }
  }

  /// Ghép câu giải thích: "«mood» — gợi ý «filter», «reason»".
  String? _buildFilterToast(SceneAnalysis analysis, int presetIdx) {
    if (presetIdx < 0) return null;
    final name = filmPresets[presetIdx].name;
    final parts = <String>[
      if (analysis.mood != null && analysis.mood!.isNotEmpty) analysis.mood!,
      'gợi ý filter $name',
      if (analysis.reason != null && analysis.reason!.isNotEmpty)
        analysis.reason!,
    ];
    return parts.join(' — ');
  }

  Future<void> _toggleComposition() async {
    if (_compositionPhase != _CompositionPhase.off) {
      _compositionPhase = _CompositionPhase.off;
      await _pauseCompositionStream();
      await _resetZoom();
      _subjectDetector?.unlock();
      _resetAnalysisState();
      if (mounted) setState(() {});
      return;
    }
    _resetAnalysisState();
    _compositionPhase = _CompositionPhase.analyzing;
    if (mounted) setState(() {});
    await _runCloudCompositionAnalysis();
    if (mounted) setState(() {});
  }

  Future<void> _startCompositionStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) return;
    _subjectDetector ??= SubjectDetector();
    try {
      await controller.startImageStream(_onFrame);
    } catch (e) {
      _compositionPhase = _CompositionPhase.off;
      if (mounted) {
        setState(() => _advice = null);
        _showMessage('Không bật được AI bố cục: $e');
      }
    }
  }

  Future<void> _pauseCompositionStream() async {
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> _resumeCompositionStream() async {
    if (_compositionPhase != _CompositionPhase.off) {
      await _startCompositionStream();
    }
  }

  void _onFrame(CameraImage image) {
    final detector = _subjectDetector;
    final controller = _controller;
    if (detector == null ||
        controller == null ||
        _compositionPhase == _CompositionPhase.off) {
      return;
    }
    final camera = _cameras[_cameraIndex];
    detector
        .process(
      image: image,
      camera: camera,
      deviceOrientation: controller.value.deviceOrientation,
    )
        .then((result) {
      if (!mounted ||
          _compositionPhase == _CompositionPhase.off ||
          result.skipped) {
        return;
      }
      if (_compositionPhase == _CompositionPhase.analyzing) {
        _handleAnalyzingFrame(result.subject, camera);
      } else {
        _handleGuidingFrame(result.subject, camera);
      }
    });
  }

  /// Pha phân tích: chờ chủ thể ổn định 3 frame liên tiếp rồi chốt
  /// chủ thể + điểm đích MỘT LẦN, chuyển sang pha dẫn hướng.
  void _handleAnalyzingFrame(
      SubjectDetection? subject, CameraDescription camera) {
    final id = subject?.trackingId;
    if (subject == null || id == null) {
      _candidateId = null;
      _candidateFrames = 0;
      return;
    }
    if (id == _candidateId) {
      _candidateFrames++;
    } else {
      _candidateId = id;
      _candidateFrames = 1;
    }
    if (_candidateFrames < 3) return;
    if (!_cloudResolved) return; // chờ Gemini trả điểm bố cục

    _subjectDetector!.lockTo(id);
    final viewRect = _subjectViewRect(subject, camera);
    _fixedTarget = _cloudTarget ?? adviseComposition(viewRect).target;
    final advice = adviseComposition(viewRect, fixedTarget: _fixedTarget);
    _compositionPhase = _CompositionPhase.aiming;
    _wasAligned = advice.isAligned;
    setState(() => _advice = advice);
    HapticFeedback.selectionClick();
    // Nếu chưa có toast từ Gemini (offline) thì dùng tip rule-based.
    if (_aiToast == null) {
      final tip = _cloudTips.isNotEmpty
          ? _cloudTips.first
          : 'Di máy cho dấu + vào vòng tròn màu.';
      setState(() => _aiToast = tip);
    }
  }

  /// Pha dẫn hướng: chỉ bám theo chủ thể đã chốt, đích giữ nguyên.
  void _handleGuidingFrame(
      SubjectDetection? subject, CameraDescription camera) {
    if (subject == null || !subject.isLocked) {
      // Mất dấu chủ thể đã chốt.
      if (_advice != null) setState(() => _advice = null);
      _wasAligned = false;
      _stopZoomAnimation();
      if (!_lostNotified) {
        _lostNotified = true;
        _showMessage('Mất dấu chủ thể — bấm ⊹ để phân tích lại.');
      }
      return;
    }
    _lostNotified = false;
    final viewRect = _subjectViewRect(subject, camera);
    // Sau long-press đổi chủ thể, đích được chốt lại một lần cho chủ thể mới.
    _fixedTarget ??= adviseComposition(viewRect).target;
    final advice = adviseComposition(
      viewRect,
      isLocked: _manualLock,
      fixedTarget: _fixedTarget,
    );
    if (advice.isAligned && !_wasAligned) {
      HapticFeedback.lightImpact();
      if (_compositionPhase == _CompositionPhase.aiming && _cloudCrop != null) {
        _enterFraming();
      }
    }
    _wasAligned = advice.isAligned;
    setState(() => _advice = advice);
  }

  /// Vào pha khung crop: hiện khung cầu vồng, toast lời khuyên, zoom mượt.
  void _enterFraming() {
    _compositionPhase = _CompositionPhase.framing;
    if (_cloudAdvice != null) _aiToast = _cloudAdvice;
    _startAutoZoom();
  }

  /// Auto-zoom neo giữa khung và fill theo cạnh LỚN của crop; ảnh chụp ra là
  /// center-zoom, không phải đúng nguyên vùng crop đề xuất — khung chỉ mang
  /// tính dẫn hướng.
  void _startAutoZoom() {
    final crop = _cloudCrop;
    if (_controller == null || crop == null) return;
    final side = math.max(crop.width, crop.height);
    final target = zoomForCrop(crop, maxZoom: _maxZoom);
    // Vùng crop cần zoom sâu hơn máy hỗ trợ → nhắc người dùng lại gần.
    _needMoreZoom = side > 0 && 1 / side > _maxZoom + 0.01;
    if (target <= 1.01) {
      if (mounted) setState(() {});
      return;
    }
    _stopZoomAnimation();
    final anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _zoomAnimation = anim;
    final zoom = Tween<double>(begin: 1, end: target).animate(
      CurvedAnimation(parent: anim, curve: Curves.easeInOut),
    );
    anim.addListener(() {
      final controller = _controller;
      if (controller == null) return;
      controller.setZoomLevel(zoom.value).catchError((_) {});
      if (mounted) setState(() {});
    });
    anim.forward();
  }

  Rect _subjectViewRect(SubjectDetection subject, CameraDescription camera) {
    return mapImageRectToView(
      rect: subject.rect,
      imageSize: subject.imageSize,
      viewAspect: _aspect.ratio,
      mirrorX: camera.lensDirection == CameraLensDirection.front,
    );
  }

  /// Long-press trên viewfinder: tự chọn chủ thể tại điểm bấm;
  /// bấm vùng trống → phân tích lại từ đầu.
  void _onViewfinderLongPress(Offset localPosition, Size viewSize) {
    final detector = _subjectDetector;
    if (_compositionPhase == _CompositionPhase.off || detector == null) return;
    if (detector.lastImageSize == Size.zero) return;
    final camera = _cameras[_cameraIndex];
    final imagePoint = mapViewPointToImage(
      point: Offset(
        localPosition.dx / viewSize.width,
        localPosition.dy / viewSize.height,
      ),
      imageSize: detector.lastImageSize,
      viewAspect: _aspect.ratio,
      mirrorX: camera.lensDirection == CameraLensDirection.front,
    );
    final locked = detector.lockAt(imagePoint);
    HapticFeedback.selectionClick();
    if (locked) {
      _manualLock = true;
      _fixedTarget = null; // chốt lại đích cho chủ thể mới ở frame kế tiếp
      _lostNotified = false;
      _compositionPhase = _CompositionPhase.aiming;
      _cloudCrop = null; // crop cũ thuộc bố cục của chủ thể trước
      _cloudAdvice = null;
      _aiToast = null; // toast lời khuyên cũ không còn hợp với chủ thể mới
      _stopZoomAnimation();
      _showMessage('Đã khoá chủ thể bạn chọn — di máy cho dấu + trùng nốt tròn.');
    } else {
      _resetAnalysisState();
      _compositionPhase = _CompositionPhase.analyzing;
      setState(() {});
      _showMessage('Đang phân tích lại — giữ nguyên máy.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  IconData get _flashIcon => switch (_flash) {
        FlashMode.off => Icons.flash_off,
        FlashMode.auto => Icons.flash_auto,
        _ => Icons.flash_on,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DokaColors.body,
      body: SafeArea(
        child: _error != null
            ? _buildError()
            : Column(
                children: [
                  _buildTopBar(),
                  Expanded(child: Center(child: _buildViewfinder())),
                  const SizedBox(height: DokaSpacing.lg),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: _showBeautySlider
                        ? _buildBeautySlider()
                        : const SizedBox(width: double.infinity),
                  ),
                  FilterCarousel(
                    selectedIndex: _presetIndex,
                    onSelected: (i) => setState(() => _presetIndex = i),
                  ),
                  _buildBottomBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DokaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography,
                color: DokaColors.inkFaint, size: 48),
            const SizedBox(height: DokaSpacing.lg),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: DokaType.body.copyWith(color: DokaColors.inkMuted),
            ),
            const SizedBox(height: DokaSpacing.xl),
            OutlinedButton(
              onPressed: () {
                setState(() => _error = null);
                _initCameras();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: DokaColors.brass,
                side: const BorderSide(color: DokaColors.brass),
              ),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          DokaSpacing.md, DokaSpacing.sm, DokaSpacing.md, 0),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: DokaColors.glass(0.35),
        borderRadius: BorderRadius.circular(DokaRadius.card),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _toolButton(
            icon: _flashIcon,
            active: _flash != FlashMode.off,
            onTap: _cycleFlash,
            tooltip: 'Đèn flash',
          ),
          // Tỉ lệ khung như chỉ số trên đồng hồ đo sáng.
          GestureDetector(
            onTap: () => setState(() => _aspect = _aspect.next),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: DokaColors.brass.withValues(alpha: 0.55)),
              ),
              child: Text(
                _aspect.label,
                style: DokaType.meter.copyWith(
                    fontSize: 13, color: DokaColors.brass),
              ),
            ),
          ),
          _toolButton(
            icon: Icons.grid_3x3,
            active: _showGrid,
            onTap: () => setState(() => _showGrid = !_showGrid),
            tooltip: 'Lưới 1/3',
          ),
          _toolButton(
            icon: Icons.face_retouching_natural,
            active: _beauty > 0,
            onTap: () =>
                setState(() => _showBeautySlider = !_showBeautySlider),
            tooltip: 'Làm mịn da',
          ),
          _toolButton(
            icon: Icons.center_focus_strong,
            active: _compositionPhase != _CompositionPhase.off,
            onTap: _toggleComposition,
            tooltip: 'AI bố cục',
          ),
          _toolButton(
            icon: Icons.auto_awesome,
            active: _suggesting,
            loading: _suggesting,
            onTap: _suggestFilter,
            tooltip: 'AI gợi ý filter',
          ),
          _toolButton(
            icon: Icons.cameraswitch_outlined,
            active: false,
            onTap: _flipCamera,
            tooltip: 'Đổi camera',
          ),
        ],
      ),
    );
  }

  /// Nút công cụ trên thanh trên: sáng đồng khi bật, tô nền đồng nhạt.
  Widget _toolButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    String? tooltip,
    bool loading = false,
  }) {
    final button = InkResponse(
      onTap: onTap,
      radius: 26,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? DokaColors.brass.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DokaColors.brass,
                ),
              )
            : Icon(
                icon,
                size: 22,
                color: active ? DokaColors.brass : DokaColors.ink,
              ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  Widget _buildViewfinder() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DokaSpacing.md),
      child: AspectRatio(
        aspectRatio: _aspect.ratio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DokaRadius.card),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DokaRadius.card),
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onLongPressStart: (details) => _onViewfinderLongPress(
                  details.localPosition,
                  constraints.biggest,
                ),
                child: _buildViewfinderStack(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewfinderStack() {
    return Stack(
          fit: StackFit.expand,
          children: [
            FilmPreviewFilter(
              preset: _preset,
              child: BeautyPreviewFilter(
                intensity: _beauty,
                child: _buildCameraCover(),
              ),
            ),
            if (_showGrid) const GridOverlay(),
            const LevelIndicator(),
            if (_compositionPhase != _CompositionPhase.off)
              CompositionOverlay(advice: _advice),
            // Đang chờ Gemini → hiệu ứng sparkle. Xong mà chưa có chủ thể nào
            // tự khoá → nốt tròn điểm cảnh đẹp (hoặc lưới 1/3 khi offline).
            if (_compositionPhase == _CompositionPhase.analyzing &&
                !_cloudResolved)
              const AnalyzingSparkleOverlay(),
            if (_compositionPhase == _CompositionPhase.analyzing &&
                _cloudResolved)
              CompositionOverlay(
                scenicPoint: _scenicTarget,
                showThirdsHint: _scenicTarget == null,
              ),
            if (_compositionPhase == _CompositionPhase.framing &&
                _cloudCrop != null)
              FrameGuideOverlay(
                rect: _cloudCrop!,
                opacity: (1 - (_zoomAnimation?.value ?? 0))
                    .clamp(0.0, 1.0)
                    .toDouble(),
              ),
            if (_compositionPhase == _CompositionPhase.analyzing &&
                !_cloudResolved)
              Positioned(
                top: 14,
                left: 12,
                right: 12,
                child: Center(
                  child: _infoPill(
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: DokaColors.brass,
                          ),
                        ),
                        SizedBox(width: 9),
                        Text(
                          'AI đang phân tích — giữ yên máy…',
                          style: TextStyle(
                              color: DokaColors.ink, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Đã phân tích xong nhưng chưa có chủ thể: mời hướng máy vào chủ thể.
            if (_compositionPhase == _CompositionPhase.analyzing &&
                _cloudResolved)
              Positioned(
                top: 14,
                left: 12,
                right: 12,
                child: Center(
                  child: _infoPill(
                    child: Text(
                      _scenicTarget != null
                          ? 'Điểm cảnh đẹp nhất đây — hướng máy vào chủ thể để được dẫn ngắm.'
                          : 'Ngoại tuyến — dùng lưới 1/3. Hướng máy vào chủ thể để dẫn ngắm.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: DokaColors.ink, fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ),
              ),
            if (_aiToast != null &&
                _compositionPhase != _CompositionPhase.off &&
                _compositionPhase != _CompositionPhase.analyzing)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: AiToastCard(message: _aiToast!),
              ),
            if (_compositionPhase == _CompositionPhase.framing &&
                _needMoreZoom)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: _infoPill(
                    child: const Text(
                      '✨ Tiến lại gần hoặc zoom thêm',
                      style:
                          TextStyle(color: DokaColors.ink, fontSize: 12.5),
                    ),
                  ),
                ),
              ),
            if (_processing)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: DokaColors.brass),
                    SizedBox(height: DokaSpacing.md),
                    Text(
                      'Đang tráng phim…',
                      style:
                          TextStyle(color: DokaColors.ink, fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        );
  }

  /// Thẻ thông tin nhỏ nổi trên khung ngắm — nền kính mờ, viền mảnh.
  Widget _infoPill({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: DokaColors.glass(0.55),
        borderRadius: BorderRadius.circular(DokaRadius.chip),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }

  Widget _buildCameraCover() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: DokaColors.body,
        child: Center(
          child: CircularProgressIndicator(color: DokaColors.brassDeep),
        ),
      );
    }
    final previewSize = controller.value.previewSize!;
    // previewSize của plugin là landscape → đảo chiều cho máy cầm dọc.
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildBeautySlider() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          DokaSpacing.xl, 0, DokaSpacing.lg, DokaSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.face_retouching_natural,
              color: DokaColors.brass, size: 18),
          const SizedBox(width: DokaSpacing.sm),
          Expanded(
            child: Slider(
              value: _beauty,
              onChanged: (v) => setState(() => _beauty = v),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${(_beauty * 100).round()}',
              style: DokaType.meter.copyWith(
                  fontSize: 12, color: DokaColors.inkMuted),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildGalleryButton(),
          _buildShutterButton(),
          // Cân đối với nút thư viện bên trái.
          const SizedBox(width: 52),
        ],
      ),
    );
  }

  Widget _buildGalleryButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const GalleryScreen()),
      ),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: DokaColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: const Icon(Icons.photo_library_outlined,
            color: DokaColors.ink, size: 24),
      ),
    );
  }

  /// Nút chụp kiểu cò máy phim: vòng đồng ánh kim, đĩa nhả màu kem.
  Widget _buildShutterButton() {
    return GestureDetector(
      onTap: _capture,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _processing ? 0.94 : 1,
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [DokaColors.brass, DokaColors.brassDeep],
            ),
            boxShadow: [
              BoxShadow(
                color: DokaColors.brass.withValues(alpha: 0.30),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          padding: const EdgeInsets.all(4),
          // Khe tối giữa vòng đồng và đĩa nhả.
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: DokaColors.body,
            ),
            child: Padding(
              padding: const EdgeInsets.all(3.5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _processing ? DokaColors.inkMuted : DokaColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
