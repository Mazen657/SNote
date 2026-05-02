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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Step 1: Root check — BEFORE any sensitive initialisation ───────────────
  //
  // This is the Dart-layer check.  The primary root gate is the native
  // Kotlin check in MainActivity.onCreate() which runs before Flutter boots.
  // This check covers the rare case where the native gate is unavailable
  // (e.g. unit-test environment, unsupported platform) and adds a second
  // independent verification layer.
  //
  // If root is detected here, we skip Hive initialisation entirely so no
  // encrypted box is ever opened and no keys are loaded into memory.
  final bool deviceCompromised =
      await RootDetectionService.isDeviceCompromised();

  if (!deviceCompromised) {
    // ── Step 2: Sensitive initialisation (only on clean devices) ─────────────

    // Lock to portrait.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Register Hive type adapters.
    Hive.registerAdapter(NoteModelAdapter());
    Hive.registerAdapter(TagModelAdapter());

    // Open encrypted Hive boxes.
    await HiveStorage.init();
  }

  // ── Step 3: Launch the app ────────────────────────────────────────────────
  //
  // If the device is compromised the app renders only CompromisedDevicePage
  // — a non-dismissible dead-end that auto-exits after 10 seconds.
  // ProviderScope is intentionally omitted on the compromised path so no
  // providers, repositories, or encryption services are ever instantiated.
  runApp(
    deviceCompromised
        ? const _BlockedApp()
        : const ProviderScope(child: SNoteApp()),
  );
}

// ── Normal app ────────────────────────────────────────────────────────────────

class SNoteApp extends StatelessWidget {
  const SNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'SNote',
      debugShowCheckedModeBanner: false,
      theme:                    AppTheme.darkTheme,
      darkTheme:                AppTheme.darkTheme,
      themeMode:                ThemeMode.dark,
      home:                     const LoginPage(),
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: child!,
        );
      },
    );
  }
}

// ── Blocked app (compromised device) ─────────────────────────────────────────
//
// A minimal MaterialApp with a single non-dismissible route.
// No ProviderScope, no Hive, no encryption services — nothing sensitive
// is ever instantiated on this path.

class _BlockedApp extends StatelessWidget {
  const _BlockedApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'SNote',
      debugShowCheckedModeBanner: false,
      theme:                    AppTheme.darkTheme,
      darkTheme:                AppTheme.darkTheme,
      themeMode:                ThemeMode.dark,
      // onGenerateRoute returns null for everything except '/' so no
      // navigation to other pages is possible.
      home:                     const CompromisedDevicePage(),
      onGenerateRoute:          (_) => null,
    );
  }
}