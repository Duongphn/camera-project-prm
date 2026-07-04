import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        colorSchemeSeed: Colors.amber,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}
