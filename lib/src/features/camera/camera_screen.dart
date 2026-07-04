import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../composition/composition_advisor.dart';
import '../composition/composition_overlay.dart';
import '../composition/subject_detector.dart';
import '../filters/film_preset.dart';
import '../filters/photo_processor.dart';
import '../gallery/gallery_screen.dart';
import '../suggestion/filter_suggester.dart';
import 'capture_aspect.dart';
import 'widgets/beauty_preview_filter.dart';
import 'widgets/film_preview_filter.dart';
import 'widgets/filter_carousel.dart';
import 'widgets/grid_overlay.dart';
import 'widgets/level_indicator.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
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
  bool _compositionOn = false;
  CompositionAdvice? _advice;
  SubjectDetector? _subjectDetector;
  bool _wasAligned = false;
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
      await controller.setFlashMode(_flash);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraIndex = index;
        _error = null;
      });
      if (_compositionOn) {
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

  /// Chụp một frame, phân tích cảnh (ML Kit + độ sáng) và tự chọn filter.
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
      final preset =
          await FilterSuggester.suggest(filePath: shot.path, bytes: bytes);
      final index = filmPresets.indexWhere((p) => p.id == preset.id);
      if (mounted && index >= 0) {
        setState(() => _presetIndex = index);
        _showMessage('Gợi ý filter: ${preset.name} ✨');
      }
    } catch (e) {
      if (mounted) _showMessage('Không gợi ý được filter: $e');
    } finally {
      await _resumeCompositionStream();
      if (mounted) setState(() => _suggesting = false);
    }
  }

  // ---- AI bố cục ----

  Future<void> _toggleComposition() async {
    if (_compositionOn) {
      _compositionOn = false;
      await _pauseCompositionStream();
      _subjectDetector?.unlock();
      if (mounted) {
        setState(() => _advice = null);
      }
      return;
    }
    _compositionOn = true;
    await _startCompositionStream();
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
      _compositionOn = false;
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
    if (_compositionOn) {
      await _startCompositionStream();
    }
  }

  void _onFrame(CameraImage image) {
    final detector = _subjectDetector;
    final controller = _controller;
    if (detector == null || controller == null || !_compositionOn) return;
    final camera = _cameras[_cameraIndex];
    detector
        .process(
      image: image,
      camera: camera,
      deviceOrientation: controller.value.deviceOrientation,
    )
        .then((result) {
      if (!mounted || !_compositionOn || result.skipped) return;
      final subject = result.subject;
      if (subject == null) {
        if (_advice != null) setState(() => _advice = null);
        _wasAligned = false;
        return;
      }
      final viewRect = mapImageRectToView(
        rect: subject.rect,
        imageSize: subject.imageSize,
        viewAspect: _aspect.ratio,
        mirrorX: camera.lensDirection == CameraLensDirection.front,
      );
      final advice =
          adviseComposition(viewRect, isLocked: subject.isLocked);
      if (advice.isAligned && !_wasAligned) {
        HapticFeedback.lightImpact();
      }
      _wasAligned = advice.isAligned;
      setState(() => _advice = advice);
    });
  }

  /// Long-press trên viewfinder: khoá/bỏ khoá chủ thể tại điểm bấm.
  void _onViewfinderLongPress(Offset localPosition, Size viewSize) {
    final detector = _subjectDetector;
    if (!_compositionOn || detector == null) return;
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
    _showMessage(locked
        ? 'Đã khoá chủ thể — AI sẽ bám theo nó.'
        : 'Đã bỏ khoá chủ thể.');
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error != null
            ? _buildError()
            : Column(
                children: [
                  _buildTopBar(),
                  Expanded(child: Center(child: _buildViewfinder())),
                  const SizedBox(height: 12),
                  if (_showBeautySlider) _buildBeautySlider(),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                setState(() => _error = null);
                _initCameras();
              },
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _cycleFlash,
            icon: Icon(_flashIcon, color: Colors.white),
          ),
          TextButton(
            onPressed: () => setState(() => _aspect = _aspect.next),
            child: Text(
              _aspect.label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _showGrid = !_showGrid),
            icon: Icon(
              Icons.grid_3x3,
              color: _showGrid ? Colors.amber : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Làm mịn da',
            onPressed: () =>
                setState(() => _showBeautySlider = !_showBeautySlider),
            icon: Icon(
              Icons.face_retouching_natural,
              color: _beauty > 0 ? Colors.amber : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'AI bố cục',
            onPressed: _toggleComposition,
            icon: Icon(
              Icons.center_focus_strong,
              color: _compositionOn ? Colors.amber : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'AI gợi ý filter',
            onPressed: _suggestFilter,
            icon: _suggesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.amber,
                    ),
                  )
                : const Icon(Icons.auto_awesome, color: Colors.white),
          ),
          IconButton(
            onPressed: _flipCamera,
            icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinder() {
    return AspectRatio(
      aspectRatio: _aspect.ratio,
      child: ClipRect(
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
            if (_compositionOn) CompositionOverlay(advice: _advice),
            if (_processing)
              Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      'Đang tráng phim…',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        );
  }

  Widget _buildCameraCover() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white24),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Icon(Icons.face_retouching_natural,
              color: Colors.white54, size: 18),
          Expanded(
            child: Slider(
              value: _beauty,
              onChanged: (v) => setState(() => _beauty = v),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${(_beauty * 100).round()}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            iconSize: 30,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GalleryScreen()),
            ),
            icon: const Icon(Icons.photo_library_outlined,
                color: Colors.white),
          ),
          GestureDetector(
            onTap: _capture,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              padding: const EdgeInsets.all(5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _processing ? Colors.white38 : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 46),
        ],
      ),
    );
  }
}
