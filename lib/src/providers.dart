import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/analysis/scene_analyzer.dart';
import 'features/gallery/photo_repository.dart';

final photoRepositoryProvider =
    Provider<PhotoRepository>((ref) => PhotoRepository());

/// Phân tích ảnh bằng Gemini (đường chính).
final sceneAnalyzerProvider =
    Provider<SceneAnalyzer>((ref) => GeminiSceneAnalyzer());

/// Fallback on-device khi Gemini lỗi/offline/thiếu key.
final offlineAnalyzerProvider =
    Provider<SceneAnalyzer>((ref) => const OfflineSceneAnalyzer());
