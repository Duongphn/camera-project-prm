import 'package:doka_app/src/features/camera/camera_lifecycle.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resumed sau khi controller đã bị nhả → restart (lỗi màn hình đen cũ)',
      () {
    expect(
      cameraLifecycleAction(
        state: AppLifecycleState.resumed,
        hasLiveController: false,
        camerasLoaded: true,
      ),
      CameraLifecycleAction.restart,
    );
  });

  test('resumed khi controller còn sống → không làm gì', () {
    expect(
      cameraLifecycleAction(
        state: AppLifecycleState.resumed,
        hasLiveController: true,
        camerasLoaded: true,
      ),
      CameraLifecycleAction.none,
    );
  });

  test('resumed khi chưa nạp xong danh sách camera → không restart '
      '(tránh RangeError lúc khởi động dở)', () {
    expect(
      cameraLifecycleAction(
        state: AppLifecycleState.resumed,
        hasLiveController: false,
        camerasLoaded: false,
      ),
      CameraLifecycleAction.none,
    );
  });

  test('inactive/paused/hidden khi controller sống → nhả camera', () {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
    ]) {
      expect(
        cameraLifecycleAction(
          state: state,
          hasLiveController: true,
          camerasLoaded: true,
        ),
        CameraLifecycleAction.release,
        reason: '$state',
      );
    }
  });

  test('inactive khi không có controller → không làm gì', () {
    expect(
      cameraLifecycleAction(
        state: AppLifecycleState.inactive,
        hasLiveController: false,
        camerasLoaded: true,
      ),
      CameraLifecycleAction.none,
    );
  });

  test('detached → không làm gì', () {
    expect(
      cameraLifecycleAction(
        state: AppLifecycleState.detached,
        hasLiveController: true,
        camerasLoaded: true,
      ),
      CameraLifecycleAction.none,
    );
  });
}
