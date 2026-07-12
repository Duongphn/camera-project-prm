import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/core/theme.dart';
import 'src/features/camera/camera_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: DokaApp()));
}

class DokaApp extends StatelessWidget {
  const DokaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doka App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: DokaColors.brass,
          brightness: Brightness.dark,
          primary: DokaColors.brass,
          surface: DokaColors.surface,
        ),
        scaffoldBackgroundColor: DokaColors.body,
        sliderTheme: const SliderThemeData(
          activeTrackColor: DokaColors.brass,
          inactiveTrackColor: DokaColors.surfaceHigh,
          thumbColor: DokaColors.brass,
          overlayColor: Color(0x33E3B15A),
          trackHeight: 2.5,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: DokaColors.surfaceHigh,
          contentTextStyle: DokaType.body,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DokaRadius.card),
          ),
        ),
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}
