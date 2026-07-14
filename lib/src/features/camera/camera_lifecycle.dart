import 'package:flutter/widgets.dart';

/// Hành động với camera khi vòng đời app đổi trạng thái.
enum CameraLifecycleAction { release, restart, none }

/// Quyết định thuần cho didChangeAppLifecycleState của màn hình camera.
///
/// [hasLiveController]: đang giữ controller đã khởi tạo.
/// [camerasLoaded]: availableCameras đã trả về danh sách khác rỗng.
///
/// resumed phải mở lại camera cả khi controller đã bị nhả lúc inactive
/// (hasLiveController = false) — guard "không có controller thì thôi" đặt
/// chung cho mọi trạng thái chính là nguồn lỗi màn hình đen khi quay lại app.
CameraLifecycleAction cameraLifecycleAction({
  required AppLifecycleState state,
  required bool hasLiveController,
  required bool camerasLoaded,
}) {
  switch (state) {
    case AppLifecycleState.inactive:
    case AppLifecycleState.paused:
    case AppLifecycleState.hidden:
      return hasLiveController
          ? CameraLifecycleAction.release
          : CameraLifecycleAction.none;
    case AppLifecycleState.resumed:
      return (!hasLiveController && camerasLoaded)
          ? CameraLifecycleAction.restart
          : CameraLifecycleAction.none;
    case AppLifecycleState.detached:
      return CameraLifecycleAction.none;
  }
}
