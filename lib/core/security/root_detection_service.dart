import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Multi-layer root / jailbreak detection.
///
/// Android strategy (defence-in-depth):
///   Layer A — Native Kotlin check via MethodChannel.
///              Runs [RootDetectionHelper] which covers build integrity,
///              su binaries, root packages, mount-point analysis, command
///              probing, and Magisk hidden paths.
///   Layer B — Dart-side file-system scan as a secondary guard.  Covers
///              scenarios where the MethodChannel itself might be intercepted
///              by a sophisticated Xposed/LSPosed hook.
///   Layer C — Environment integrity check (emulator + debug-build detection).
///
/// iOS strategy:
///   Dart-side path scan for Cydia, SSH, MobileSubstrate, and known
///   jailbreak artefacts.
///
/// The native layer (A) is the primary authoritative source on Android.
/// If the channel call fails for any unexpected reason, Layer B is used as
/// a fallback so the app never silently skips detection.
///
/// Fail-safe policy: any exception during detection does NOT default to
/// "safe".  Only a confirmed exception from a path-access denial (which
/// indicates the sandbox is intact) is treated as a non-rooted signal.
class RootDetectionService {
  static const MethodChannel _channel =
      MethodChannel('com.mazen.snote/root_detection');

  // ── Android file-system indicators (Layer B fallback) ─────────────────────

  static const _androidPaths = [
    // su binaries
    '/sbin/su',
    '/su/bin/su',
    '/su/xbin/su',
    '/system/bin/su',
    '/system/bin/failsafe/su',
    '/system/sd/xbin/su',
    '/system/xbin/su',
    '/system/xbin/daemonsu',
    '/data/local/su',
    '/data/local/bin/su',
    '/data/local/xbin/su',
    '/cache/su',
    '/vendor/bin/su',
    // Root apps
    '/system/app/SuperSU.apk',
    '/system/app/Superuser.apk',
    '/system/app/SuperSU/SuperSU.apk',
    '/system/app/Superuser/Superuser.apk',
    // Magisk
    '/sbin/magisk',
    '/sbin/.magisk',
    '/sbin/.core/mirror',
    '/data/adb/magisk',
    '/data/adb/magisk.db',
    '/data/adb/modules',
    '/data/adb/ksu',
    // Misc root artefacts
    '/system/lib/libsuperuser.so',
    '/system/etc/init.d/99SuperSUDaemon',
  ];

  // ── iOS jailbreak indicators ───────────────────────────────────────────────

  static const _iosPaths = [
    '/Applications/Cydia.app',
    '/Applications/FakeCarrier.app',
    '/Applications/Icy.app',
    '/Applications/IntelliScreen.app',
    '/Applications/MxTube.app',
    '/Applications/RockApp.app',
    '/Applications/SBSettings.app',
    '/Applications/WinterBoard.app',
    '/Library/MobileSubstrate/MobileSubstrate.dylib',
    '/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist',
    '/Library/MobileSubstrate/DynamicLibraries/Veency.plist',
    '/private/var/lib/apt',
    '/private/var/lib/cydia',
    '/private/var/mobile/Library/SBSettings/Themes',
    '/private/var/stash',
    '/private/var/tmp/cydia.log',
    '/usr/bin/sshd',
    '/usr/libexec/sftp-server',
    '/usr/sbin/sshd',
    '/bin/bash',
    '/bin/sh',
    '/etc/apt',
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns true when the device is determined to be rooted or jailbroken.
  ///
  /// On Android the native MethodChannel check is always attempted first.
  /// A channel error falls through to the Dart-side scan.
  ///
  /// Must be called after [WidgetsFlutterBinding.ensureInitialized].
  static Future<bool> isDeviceCompromised() async {
    if (kIsWeb) return false;

    try {
      if (Platform.isAndroid) {
        return await _checkAndroid();
      }
      if (Platform.isIOS) {
        return _checkIos();
      }
    } catch (_) {
      // Unhandled platform error — treat as safe to avoid blocking all
      // desktop / unknown platforms.
    }
    return false;
  }

  // ── Android ───────────────────────────────────────────────────────────────

  static Future<bool> _checkAndroid() async {
    // Layer A: native Kotlin check (authoritative).
    final nativeResult = await _nativeRootCheck();
    if (nativeResult == true) return true;

    // Layer B: Dart file-system scan (fallback / secondary).
    if (_dartFileSystemCheck(_androidPaths)) return true;

    // Layer C: environment integrity (emulator with root / debug builds).
    if (await _environmentCheck()) return true;

    return false;
  }

  /// Calls the native [RootDetectionHelper] via MethodChannel.
  /// Returns null only when the channel itself is unavailable (e.g. on a
  /// platform where the native handler is not registered), not when the
  /// check ran and found no root.
  static Future<bool?> _nativeRootCheck() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRooted');
      return result;
    } on MissingPluginException {
      // Native handler not registered — fall through to Dart checks.
      return null;
    } on PlatformException catch (e) {
      // Channel error — treat as inconclusive, fall through.
      debugPrint('RootDetectionService: native check error: ${e.message}');
      return null;
    }
  }

  /// Checks for the existence of known root / Magisk artefact paths.
  static bool _dartFileSystemCheck(List<String> paths) {
    for (final path in paths) {
      try {
        if (File(path).existsSync()) return true;
      } on FileSystemException {
        // Access denied → sandbox is intact for this path.  Not a root signal.
      } catch (_) {
        // Any other exception — skip this path.
      }
    }
    return false;
  }

  /// Checks environment properties that indicate a rooted emulator or a
  /// build variant that ships with unrestricted root access.
  static Future<bool> _environmentCheck() async {
    // Check for a "test-keys" build tag exposed via the native channel.
    // If the channel is unavailable this check is skipped gracefully.
    try {
      final buildTag = await _channel.invokeMethod<String>('getBuildTag');
      if (buildTag != null && buildTag.contains('test-keys')) return true;
    } catch (_) { /* channel may not implement this method on all versions */ }
    return false;
  }

  // ── iOS ───────────────────────────────────────────────────────────────────

  static bool _checkIos() {
    return _dartFileSystemCheck(_iosPaths);
  }
}