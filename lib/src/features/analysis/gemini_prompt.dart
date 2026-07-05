import 'dart:ui';

import '../filters/film_preset.dart';
import 'scene_analysis.dart';

/// Schema JSON buộc Gemini trả đúng cấu trúc.
const Map<String, dynamic> sceneResponseSchema = {
  'type': 'OBJECT',
  'properties': {
    'presetId': {'type': 'STRING'},
    'reason': {'type': 'STRING'},
    'mood': {'type': 'STRING'},
    'targetX': {'type': 'NUMBER'},
    'targetY': {'type': 'NUMBER'},
    'tips': {
      'type': 'ARRAY',
      'items': {'type': 'STRING'},
    },
  },
  'required': ['presetId'],
};

/// Prompt yêu cầu Gemini phân tích ảnh và chọn preset + điểm bố cục.
String buildScenePrompt(List<FilmPreset> presets) {
  final catalog = presets.map((p) => '- ${p.id}: ${p.name}').join('\n');
  return '''
Bạn là chuyên gia nhiếp ảnh phim. Phân tích bức ảnh và trả về JSON.

Chọn ĐÚNG MỘT presetId phù hợp nhất trong danh mục dưới đây (chỉ dùng id có trong danh sách):
$catalog

Trả về các trường:
- presetId: id filter hợp nhất với ánh sáng và tông màu của ảnh.
- reason: vì sao chọn (tiếng Việt, tối đa 15 từ).
- mood: mô tả ngắn ánh sáng/tông màu/bối cảnh (tiếng Việt).
- targetX, targetY: vị trí ĐẶT CHỦ THỂ đẹp nhất theo bố cục, số thực 0..1 (gốc 0,0 ở góc trên-trái).
- tips: tối đa 3 mẹo bố cục ngắn gọn bằng tiếng Việt.
''';
}

/// Parse JSON trả về (đã decode) thành SceneAnalysis. Thuần, không mạng.
SceneAnalysis parseGeminiJson(
  Map<String, dynamic> json, {
  required List<String> validIds,
  bool fromCloud = true,
}) {
  final rawId = (json['presetId'] as String?)?.trim() ?? '';
  final presetId = validIds.contains(rawId) ? rawId : 'original';

  Offset? target;
  final tx = (json['targetX'] as num?)?.toDouble();
  final ty = (json['targetY'] as num?)?.toDouble();
  if (tx != null && ty != null && tx >= 0 && tx <= 1 && ty >= 0 && ty <= 1) {
    target = Offset(tx, ty);
  }

  final tips = <String>[];
  final rawTips = json['tips'];
  if (rawTips is List) {
    for (final t in rawTips) {
      if (t is String && t.trim().isNotEmpty) tips.add(t.trim());
      if (tips.length == 3) break;
    }
  }

  return SceneAnalysis(
    presetId: presetId,
    reason: (json['reason'] as String?)?.trim(),
    mood: (json['mood'] as String?)?.trim(),
    targetPoint: target,
    tips: tips,
    fromCloud: fromCloud,
  );
}
