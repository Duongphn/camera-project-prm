import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import 'camera_image_converter.dart';
import 'composition_advisor.dart';

/// Chủ thể tìm được trong một frame (toạ độ px, không gian ảnh upright).
class SubjectDetection {
  const SubjectDetection({
    required this.rect,
    required this.imageSize,
    required this.trackingId,
    required this.isLocked,
  });

  final Rect rect;
  final Size imageSize;
  final int? trackingId;
  final bool isLocked;
}

/// Kết quả xử lý một frame. [skipped] = frame bị bỏ qua do detector đang bận
/// (khác với "không thấy chủ thể" khi [subject] == null).
class SubjectFrameResult {
  const SubjectFrameResult({required this.subject, this.skipped = false});

  static const skippedFrame = SubjectFrameResult(subject: null, skipped: true);

  final SubjectDetection? subject;
  final bool skipped;
}

const _deviceOrientationDegrees = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Nhận diện chủ thể nổi bật trên stream camera bằng ML Kit object detection
/// (stream mode, model bundled on-device, có tracking ID).
class SubjectDetector {
  final ObjectDetector _detector = ObjectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: false,
      multipleObjects: true,
    ),
  );

  bool _busy = false;
  int? _lockedId;
  List<DetectedObject> _lastObjects = const [];
  Size _lastImageSize = Size.zero;

  Future<SubjectFrameResult> process({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) async {
    if (_busy) return SubjectFrameResult.skippedFrame;
    _busy = true;
    try {
      final input = _toInputImage(image, camera, deviceOrientation);
      if (input == null) return SubjectFrameResult.skippedFrame;

      final objects = await _detector.processImage(input);

      // Bounding box ML Kit nằm trong không gian ảnh đã xoay thẳng đứng:
      // xoay 90/270 thì đảo chiều rộng/cao của buffer.
      final rotation = input.metadata!.rotation;
      final rotated = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      final imageSize = rotated
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());

      _lastObjects = objects;
      _lastImageSize = imageSize;

      if (objects.isEmpty) {
        // Chủ thể đã khoá ra khỏi khung → bỏ khoá để không kẹt.
        _lockedId = null;
        return const SubjectFrameResult(subject: null);
      }

      final index = pickSubjectIndex(
        [for (final o in objects) o.boundingBox],
        [for (final o in objects) o.trackingId],
        lockedId: _lockedId,
        imageSize: imageSize,
      );
      final picked = objects[index];
      if (_lockedId != null && picked.trackingId != _lockedId) {
        // Không còn thấy chủ thể đã khoá.
        _lockedId = null;
      }
      return SubjectFrameResult(
        subject: SubjectDetection(
          rect: picked.boundingBox,
          imageSize: imageSize,
          trackingId: picked.trackingId,
          isLocked: _lockedId != null && picked.trackingId == _lockedId,
        ),
      );
    } catch (_) {
      return SubjectFrameResult.skippedFrame;
    } finally {
      _busy = false;
    }
  }

  /// Khoá chủ thể chứa [imagePoint] (px, ảnh upright của frame gần nhất).
  /// Trả về true nếu khoá được; chạm vào vùng trống thì bỏ khoá.
  bool lockAt(Offset imagePoint) {
    for (final object in _lastObjects) {
      if (object.boundingBox.contains(imagePoint) &&
          object.trackingId != null) {
        _lockedId = object.trackingId;
        return true;
      }
    }
    _lockedId = null;
    return false;
  }

  void unlock() => _lockedId = null;

  Size get lastImageSize => _lastImageSize;

  Future<void> close() => _detector.close();

  InputImage? _toInputImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final rotation = _rotationFor(camera, deviceOrientation);
    if (rotation == null) return null;

    if (Platform.isAndroid) {
      final Uint8List nv21;
      if (image.planes.length == 1) {
        // camerax trả thẳng NV21 khi yêu cầu ImageFormatGroup.nv21.
        nv21 = image.planes[0].bytes;
      } else if (image.planes.length == 3) {
        nv21 = nv21FromYuvPlanes(
          width: image.width,
          height: image.height,
          yBytes: image.planes[0].bytes,
          yRowStride: image.planes[0].bytesPerRow,
          uBytes: image.planes[1].bytes,
          uRowStride: image.planes[1].bytesPerRow,
          uPixelStride: image.planes[1].bytesPerPixel ?? 1,
          vBytes: image.planes[2].bytes,
          vRowStride: image.planes[2].bytesPerRow,
          vPixelStride: image.planes[2].bytesPerPixel ?? 1,
        );
      } else {
        return null;
      }
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    // iOS: BGRA 1 plane.
    if (image.planes.length != 1) return null;
    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotationFor(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    final compensation = _deviceOrientationDegrees[deviceOrientation];
    if (compensation == null) return null;
    final degrees = camera.lensDirection == CameraLensDirection.front
        ? (sensorOrientation + compensation) % 360
        : (sensorOrientation - compensation + 360) % 360;
    return InputImageRotationValue.fromRawValue(degrees);
  }
}
