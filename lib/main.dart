import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/security/root_detection_service.dart';
import 'core/storage/hive_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/compromised_device_page.dart';
import 'features/auth/login_page.dart';
import 'features/notes/note_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Register Hive adapters before opening boxes.
  Hive.registerAdapter(NoteModelAdapter());
  Hive.registerAdapter(TagModelAdapter());

  // Initialise encrypted Hive storage.
  await HiveStorage.init();

  // Check for root / jailbreak.
  final compromised = await RootDetectionService.isDeviceCompromised();

  runApp(
    ProviderScope(
      child: SNoteApp(deviceCompromised: compromised),
    ),
  );
}

class SNoteApp extends StatelessWidget {
  final bool deviceCompromised;
  const SNoteApp({super.key, required this.deviceCompromised});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: deviceCompromised
          ? const CompromisedDevicePage()
          : const LoginPage(),
      builder: (context, child) {
        // Apply the dark system UI overlay on every screen.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: child!,
        );
      },
    );
  }
}