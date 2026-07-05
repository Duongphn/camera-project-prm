import 'dart:ui';

import '../../core/geometry.dart';

/// 4 giao điểm rule-of-thirds (toạ độ 0..1 của viewfinder).
const List<Offset> thirdsPoints = [
  Offset(1 / 3, 1 / 3),
  Offset(2 / 3, 1 / 3),
  Offset(1 / 3, 2 / 3),
  Offset(2 / 3, 2 / 3),
];

/// Chủ thể chiếm diện tích lớn hơn mức này thì hướng về tâm khung
/// thay vì điểm thirds.
const double kLargeSubjectArea = 0.35;

/// Khoảng cách (theo tỉ lệ khung) coi là "đã vào bố cục".
const double kAlignThreshold = 0.05;

/// Lời khuyên bố cục cho một frame. Mọi toạ độ ở không gian 0..1
/// của viewfinder.
class CompositionAdvice {
  const CompositionAdvice({
    required this.subjectRect,
    required this.subjectCenter,
    required this.target,
    required this.aimPoint,
    required this.isAligned,
    required this.isLocked,
  });

  final Rect subjectRect;
  final Offset subjectCenter;
  final Offset target;

  /// Điểm ngắm: vị trí phải đưa dấu + giữa màn hình tới. Khi aimPoint trùng
  /// tâm màn hình thì chủ thể nằm đúng [target] (điểm bố cục đẹp).
  final Offset aimPoint;

  final bool isAligned;

  /// Người dùng đã long-press khoá chủ thể này.
  final bool isLocked;
}

/// Tính lời khuyên bố cục cho chủ thể [subjectRect] (0..1 viewfinder).
///
/// [fixedTarget]: điểm đích đã chốt từ lần phân tích đầu — truyền vào để
/// đích không bị tính lại mỗi frame (chế độ "phân tích 1 lần").
CompositionAdvice adviseComposition(
  Rect subjectRect, {
  bool isLocked = false,
  Offset? fixedTarget,
  double alignThreshold = kAlignThreshold,
  double largeSubjectArea = kLargeSubjectArea,
}) {
  final center = subjectRect.center;
  final area = subjectRect.width * subjectRect.height;

  Offset target;
  if (fixedTarget != null) {
    target = fixedTarget;
  } else if (area >= largeSubjectArea) {
    target = const Offset(0.5, 0.5);
  } else {
    target = thirdsPoints.first;
    var best = (center - target).distance;
    for (final p in thirdsPoints.skip(1)) {
      final d = (center - p).distance;
      if (d < best) {
        best = d;
        target = p;
      }
    }
  }

  // Cần dời khung ngắm một đoạn (target - center) để chủ thể vào target;
  // điểm cảnh đang ở tâm sẽ trôi ngược lại đúng đoạn đó → điểm ngắm là:
  final aimPoint = Offset(
    0.5 + center.dx - target.dx,
    0.5 + center.dy - target.dy,
  );

  return CompositionAdvice(
    subjectRect: subjectRect,
    subjectCenter: center,
    target: target,
    aimPoint: aimPoint,
    isAligned: (center - target).distance <= alignThreshold,
    isLocked: isLocked,
  );
}

/// Map rect (px, không gian ảnh upright) sang toạ độ 0..1 của viewfinder.
///
/// Giả định: viewfinder hiển thị phần center-crop (BoxFit.cover) của frame
/// theo tỉ lệ [viewAspect]. [mirrorX] = true với camera trước (preview soi
/// gương). Kết quả có thể vượt ra ngoài [0,1] nếu chủ thể nằm ngoài vùng
/// nhìn thấy — người gọi tự quyết định vẽ hay bỏ.
Rect mapImageRectToView({
  required Rect rect,
  required Size imageSize,
  required double viewAspect,
  bool mirrorX = false,
}) {
  final visible = centeredCropRect(
    imageSize.width.round(),
    imageSize.height.round(),
    viewAspect,
  );
  var left = (rect.left - visible.left) / visible.width;
  var right = (rect.right - visible.left) / visible.width;
  final top = (rect.top - visible.top) / visible.height;
  final bottom = (rect.bottom - visible.top) / visible.height;
  if (mirrorX) {
    final l = 1 - right;
    right = 1 - left;
    left = l;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Map một điểm chuẩn hoá (0..1 trên ảnh tĩnh upright) sang toạ độ 0..1 của
/// viewfinder (đã center-crop theo [viewAspect]; [mirrorX]=true cho camera
/// trước). Kết quả có thể ra ngoài [0,1] nếu điểm nằm trong vùng bị crop —
/// người gọi tự kẹp.
Offset mapImagePointToView({
  required Offset point,
  required Size imageSize,
  required double viewAspect,
  bool mirrorX = false,
}) {
  final visible = centeredCropRect(
    imageSize.width.round(),
    imageSize.height.round(),
    viewAspect,
  );
  final px = point.dx * imageSize.width;
  final py = point.dy * imageSize.height;
  var vx = (px - visible.left) / visible.width;
  final vy = (py - visible.top) / visible.height;
  if (mirrorX) vx = 1 - vx;
  return Offset(vx, vy);
}

/// Ngược của [mapImageRectToView] cho một điểm: từ toạ độ 0..1 viewfinder
/// về toạ độ px trong ảnh upright. Dùng cho long-press chọn chủ thể.
Offset mapViewPointToImage({
  required Offset point,
  required Size imageSize,
  required double viewAspect,
  bool mirrorX = false,
}) {
  final visible = centeredCropRect(
    imageSize.width.round(),
    imageSize.height.round(),
    viewAspect,
  );
  final x = mirrorX ? 1 - point.dx : point.dx;
  return Offset(
    visible.left + x * visible.width,
    visible.top + point.dy * visible.height,
  );
}

/// Chọn chủ thể trong danh sách box (px, ảnh upright).
///
/// Ưu tiên box có [lockedId]; nếu không có thì chấm điểm
/// diện tích × độ gần tâm khung. Trả về index, -1 nếu danh sách rỗng.
int pickSubjectIndex(
  List<Rect> boxes,
  List<int?> ids, {
  int? lockedId,
  required Size imageSize,
}) {
  if (boxes.isEmpty) return -1;
  if (lockedId != null) {
    final locked = ids.indexOf(lockedId);
    if (locked >= 0) return locked;
  }
  final imageArea = imageSize.width * imageSize.height;
  final center = Offset(imageSize.width / 2, imageSize.height / 2);
  final diagonal = center.distance;
  var bestIndex = 0;
  var bestScore = double.negativeInfinity;
  for (var i = 0; i < boxes.length; i++) {
    final area = boxes[i].width * boxes[i].height / imageArea;
    final centrality = 1 - (boxes[i].center - center).distance / diagonal;
    final score = area * (0.4 + 0.6 * centrality);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = i;
    }
  }
  return bestIndex;
}
