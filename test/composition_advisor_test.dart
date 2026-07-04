import 'dart:ui';

import 'package:doka_app/src/features/composition/composition_advisor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('adviseComposition', () {
    test('chủ thể nhỏ lệch trái trên → đích là điểm thirds trái trên', () {
      final advice = adviseComposition(
        Rect.fromCenter(
          center: const Offset(0.25, 0.25),
          width: 0.2,
          height: 0.2,
        ),
      );
      expect(advice.target, const Offset(1 / 3, 1 / 3));
      expect(advice.isAligned, isFalse);
    });

    test('chủ thể lớn (>35% khung) → đích là tâm', () {
      final advice = adviseComposition(
        Rect.fromCenter(
          center: const Offset(0.4, 0.4),
          width: 0.7,
          height: 0.7,
        ),
      );
      expect(advice.target, const Offset(0.5, 0.5));
    });

    test('chủ thể ngay điểm thirds → aligned', () {
      final advice = adviseComposition(
        Rect.fromCenter(
          center: const Offset(2 / 3 + 0.01, 1 / 3),
          width: 0.15,
          height: 0.15,
        ),
      );
      expect(advice.target, const Offset(2 / 3, 1 / 3));
      expect(advice.isAligned, isTrue);
    });

    test('aimPoint: đưa + về nốt tròn thì chủ thể vào đúng target', () {
      // Chủ thể ở (0.25, 0.25), đích (1/3, 1/3): cảnh phải trôi (−1/12, −1/12)
      // → điểm ngắm nằm tại tâm trừ đúng đoạn đó.
      final advice = adviseComposition(
        Rect.fromCenter(
          center: const Offset(0.25, 0.25),
          width: 0.2,
          height: 0.2,
        ),
      );
      expect(advice.aimPoint.dx, closeTo(0.5 + 0.25 - 1 / 3, 1e-9));
      expect(advice.aimPoint.dy, closeTo(0.5 + 0.25 - 1 / 3, 1e-9));
    });

    test('aimPoint trùng tâm khi chủ thể đã ở đúng đích', () {
      final advice = adviseComposition(
        Rect.fromCenter(
          center: const Offset(1 / 3, 1 / 3),
          width: 0.1,
          height: 0.1,
        ),
      );
      expect(advice.aimPoint.dx, closeTo(0.5, 1e-9));
      expect(advice.aimPoint.dy, closeTo(0.5, 1e-9));
      expect(advice.isAligned, isTrue);
    });

    test('cờ isLocked được giữ nguyên', () {
      final advice = adviseComposition(
        Rect.fromCenter(
          center: const Offset(0.5, 0.5),
          width: 0.1,
          height: 0.1,
        ),
        isLocked: true,
      );
      expect(advice.isLocked, isTrue);
    });
  });

  group('mapImageRectToView', () {
    // Frame upright 480x640 (dọc 3:4), viewfinder 3:4 → nhìn thấy toàn khung.
    test('viewfinder cùng tỉ lệ frame → map tuyến tính', () {
      final view = mapImageRectToView(
        rect: const Rect.fromLTWH(120, 160, 240, 320),
        imageSize: const Size(480, 640),
        viewAspect: 3 / 4,
      );
      expect(view.left, closeTo(0.25, 1e-9));
      expect(view.top, closeTo(0.25, 1e-9));
      expect(view.width, closeTo(0.5, 1e-9));
      expect(view.height, closeTo(0.5, 1e-9));
    });

    test('viewfinder 1:1 crop giữa từ frame 3:4 → trừ phần bị cắt', () {
      // Frame 480x640, view 1:1 → vùng nhìn thấy = 480x480, top = 80.
      final view = mapImageRectToView(
        rect: const Rect.fromLTWH(0, 80, 480, 480),
        imageSize: const Size(480, 640),
        viewAspect: 1,
      );
      expect(view.left, closeTo(0, 1e-9));
      expect(view.top, closeTo(0, 1e-9));
      expect(view.right, closeTo(1, 1e-9));
      expect(view.bottom, closeTo(1, 1e-9));
    });

    test('mirrorX lật trục ngang (camera trước)', () {
      final view = mapImageRectToView(
        rect: const Rect.fromLTWH(0, 0, 120, 640),
        imageSize: const Size(480, 640),
        viewAspect: 3 / 4,
        mirrorX: true,
      );
      // Box sát mép trái → sau mirror sát mép phải.
      expect(view.left, closeTo(0.75, 1e-9));
      expect(view.right, closeTo(1.0, 1e-9));
    });
  });

  group('mapViewPointToImage', () {
    test('là nghịch đảo của mapImageRectToView (không mirror)', () {
      const imageSize = Size(480, 640);
      const viewAspect = 1.0;
      final imagePoint = mapViewPointToImage(
        point: const Offset(0.5, 0.5),
        imageSize: imageSize,
        viewAspect: viewAspect,
      );
      // Tâm view = tâm vùng nhìn thấy = tâm frame.
      expect(imagePoint.dx, closeTo(240, 1e-9));
      expect(imagePoint.dy, closeTo(320, 1e-9));
    });

    test('mirror: điểm bên trái view là bên phải ảnh', () {
      final imagePoint = mapViewPointToImage(
        point: const Offset(0.1, 0.5),
        imageSize: const Size(480, 640),
        viewAspect: 3 / 4,
        mirrorX: true,
      );
      expect(imagePoint.dx, closeTo(0.9 * 480, 1e-9));
    });
  });

  group('pickSubjectIndex', () {
    const imageSize = Size(480, 640);

    test('danh sách rỗng → -1', () {
      expect(pickSubjectIndex([], [], imageSize: imageSize), -1);
    });

    test('ưu tiên chủ thể đã khoá dù nhỏ hơn', () {
      final boxes = [
        const Rect.fromLTWH(0, 0, 400, 400), // to
        const Rect.fromLTWH(200, 300, 50, 50), // nhỏ, id=7
      ];
      expect(
        pickSubjectIndex(boxes, [3, 7], lockedId: 7, imageSize: imageSize),
        1,
      );
    });

    test('không khoá → chọn box to và gần tâm', () {
      final boxes = [
        const Rect.fromLTWH(0, 0, 60, 60), // nhỏ, góc
        const Rect.fromLTWH(140, 220, 200, 200), // to, giữa khung
      ];
      expect(
        pickSubjectIndex(boxes, [1, 2], imageSize: imageSize),
        1,
      );
    });

    test('lockedId không còn trong khung → quay về chấm điểm', () {
      final boxes = [const Rect.fromLTWH(140, 220, 200, 200)];
      expect(
        pickSubjectIndex(boxes, [5], lockedId: 99, imageSize: imageSize),
        0,
      );
    });
  });
}
