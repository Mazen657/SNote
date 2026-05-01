import 'dart:io';

import 'package:flutter/foundation.dart';

/// Detects whether the device has been rooted (Android) or jailbroken (iOS).
/// Desktop platforms are not checked and are considered safe.
///
/// Detection is heuristic — a determined attacker can bypass it.  Its purpose
/// is to deter casual misuse on compromised devices, not to stop sophisticated
/// adversaries.  Combine with full-disk encryption and hardware-backed key
/// storage for defence-in-depth.
class RootDetectionService {
  static const List<String> _androidRootPaths = [
    '/system/app/Superuser.apk',
    '/sbin/su',
    '/system/bin/su',
    '/system/xbin/su',
    '/data/local/xbin/su',
    '/data/local/bin/su',
    '/system/sd/xbin/su',
    '/system/bin/failsafe/su',
    '/data/local/su',
    '/su/bin/su',
    '/system/app/SuperSU.apk',
  ];

  static const List<String> _iosPaths = [
    '/Applications/Cydia.app',
    '/Library/MobileSubstrate/MobileSubstrate.dylib',
    '/usr/sbin/sshd',
    '/etc/apt',
    '/private/var/lib/apt/',
    '/usr/bin/ssh',
    '/bin/bash',
  ];

  /// Returns true when the device appears to be rooted or jailbroken.
  static Future<bool> isDeviceCompromised() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) return await _checkAndroid();
      if (Platform.isIOS) return await _checkIos();
    } catch (_) {
      // Unexpected error during detection — assume safe so the app is usable.
    }
    return false;
  }

  static Future<bool> _checkAndroid() async {
    for (final path in _androidRootPaths) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {
        // Access denied means the path is protected — not rooted for this check.
      }
    }
    return false;
  }

  static Future<bool> _checkIos() async {
    for (final path in _iosPaths) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {
        // Sandbox enforced — path not accessible — not jailbroken for this check.
      }
    }
    return false;
  }
}
