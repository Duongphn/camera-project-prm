import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/geometry.dart';

/// Vạch cân bằng đường chân trời: xoay theo độ nghiêng của máy,
/// chuyển xanh khi máy thẳng (±2°).
class LevelIndicator extends StatelessWidget {
  const LevelIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: StreamBuilder<AccelerometerEvent>(
        stream: accelerometerEventStream(
          samplingPeriod: SensorInterval.uiInterval,
        ),
        builder: (context, snapshot) {
          final event = snapshot.data;
          if (event == null) return const SizedBox.shrink();
          final roll = rollRadians(event.x, event.y);
          final level = isLevel(roll);
          return Center(
            child: Transform.rotate(
              angle: roll,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: level ? 140 : 110,
                height: 1.6,
                color: level ? Colors.greenAccent : Colors.white54,
              ),
            ),
          );
        },
      ),
    );
  }
}
