import 'package:doka_app/src/features/composition/subject_detector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('streamRotationDegrees', () {
    test('iOS: buffer đã được plugin xoay thẳng → luôn 0, bất kể cảm biến',
        () {
      for (final sensor in [0, 90, 180, 270]) {
        for (final front in [true, false]) {
          expect(
            streamRotationDegrees(
              isIOS: true,
              sensorOrientation: sensor,
              isFrontCamera: front,
              deviceOrientation: DeviceOrientation.portraitUp,
            ),
            0,
            reason: 'sensor=$sensor front=$front',
          );
        }
      }
    });

    test('Android camera sau, cầm dọc, cảm biến 90 → 90', () {
      expect(
        streamRotationDegrees(
          isIOS: false,
          sensorOrientation: 90,
          isFrontCamera: false,
          deviceOrientation: DeviceOrientation.portraitUp,
        ),
        90,
      );
    });

    test('Android camera sau, landscapeLeft, cảm biến 90 → 0', () {
      expect(
        streamRotationDegrees(
          isIOS: false,
          sensorOrientation: 90,
          isFrontCamera: false,
          deviceOrientation: DeviceOrientation.landscapeLeft,
        ),
        0,
      );
    });

    test('Android camera trước, cầm dọc, cảm biến 270 → 270', () {
      expect(
        streamRotationDegrees(
          isIOS: false,
          sensorOrientation: 270,
          isFrontCamera: true,
          deviceOrientation: DeviceOrientation.portraitUp,
        ),
        270,
      );
    });
  });

  group('streamMirrorX', () {
    test('iOS camera trước: buffer đã mirror sẵn trong plugin → false', () {
      expect(streamMirrorX(isIOS: true, isFrontCamera: true), isFalse);
    });

    test('Android camera trước: buffer chưa mirror, preview mirror → true',
        () {
      expect(streamMirrorX(isIOS: false, isFrontCamera: true), isTrue);
    });

    test('camera sau: không mirror trên cả hai nền tảng', () {
      expect(streamMirrorX(isIOS: true, isFrontCamera: false), isFalse);
      expect(streamMirrorX(isIOS: false, isFrontCamera: false), isFalse);
    });
  });
}
