import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../encryption/encryption_service.dart';
import '../encryption/key_derivation_service.dart';

const _kPasswordHash   = 'snote_password_hash';
const _kMasterSalt     = 'snote_master_salt';
const _kBiometricKey   = 'snote_bio_master_key';
const _kBiometricEn    = 'snote_biometric_enabled';
const _kAutoLock       = 'snote_auto_lock_minutes';
const _kFailedAttempts = 'snote_failed_attempts';
const _kMaxAttempts    = 'snote_max_attempts';

/// Manages authentication and session security.
/// The master key lives only in memory; it is wiped on [lock].
class SecurityService {
  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;
  final EncryptionService encryptionService;

  Timer? _autoLockTimer;
  int _autoLockMinutes = 5;

  SecurityService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
    EncryptionService? encryptionService,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            ),
        _localAuth = localAuth ?? LocalAuthentication(),
        encryptionService = encryptionService ?? EncryptionService();

  // ─── Password ─────────────────────────────────────────────────────────────

  Future<bool> get hasPassword async {
    final h = await _storage.read(key: _kPasswordHash);
    return h != null && h.isNotEmpty;
  }

  Future<void> setPassword(String password) async {
    final salt   = KeyDerivationService.generateSalt();
    final saltB64 = base64.encode(salt);
    final hash   = KeyDerivationService.hashPasswordForStorage(password);

    await _storage.write(key: _kPasswordHash, value: hash);
    await _storage.write(key: _kMasterSalt,   value: saltB64);
    await _resetFailedAttempts();
    await _deriveMasterKey(password);
  }

  Future<AuthResult> verifyPassword(String password) async {
    final failed = await _getFailedAttempts();
    final max    = await _getMaxAttempts();
    if (failed >= max) return AuthResult.lockedOut;

    final storedHash = await _storage.read(key: _kPasswordHash);
    if (storedHash == null) return AuthResult.noPasswordSet;

    if (KeyDerivationService.verifyPasswordHash(password, storedHash)) {
      await _resetFailedAttempts();
      await _deriveMasterKey(password);
      return AuthResult.success;
    }

    await _incrementFailedAttempts();
    final remaining = max - (failed + 1);
    return remaining <= 0 ? AuthResult.lockedOut : AuthResult.wrongPassword;
  }

  Future<void> _deriveMasterKey(String password) async {
    final saltB64 = await _storage.read(key: _kMasterSalt);
    if (saltB64 == null) return;
    final salt      = base64.decode(saltB64);
    final masterKey = await KeyDerivationService.deriveMasterKey(password, salt);
    encryptionService.setMasterKey(masterKey);
  }

  // ─── Biometrics ───────────────────────────────────────────────────────────

  Future<bool> get isBiometricAvailable async {
    try {
      return await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  Future<bool> get isBiometricEnabled async {
    final val = await _storage.read(key: _kBiometricEn);
    return val == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) =>
      _storage.write(key: _kBiometricEn, value: enabled.toString());

  /// Stores the current in-memory master key under a biometric-protected entry
  /// so a future biometric login can restore it without requiring the password.
  Future<void> cacheMasterKeyForBiometrics() async {
    if (!encryptionService.isInitialized) return;
    final keyB64 = base64.encode(encryptionService.masterKey);
    await _storage.write(key: _kBiometricKey, value: keyB64);
  }

  Future<AuthResult> authenticateWithBiometrics() async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access SNote',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!ok) return AuthResult.biometricFailed;

      final cachedKey = await _storage.read(key: _kBiometricKey);
      if (cachedKey == null) return AuthResult.noPasswordSet;

      encryptionService.setMasterKey(
          Uint8List.fromList(base64.decode(cachedKey)));
      await _resetFailedAttempts();
      return AuthResult.success;
    } on PlatformException {
      return AuthResult.biometricFailed;
    }
  }

  // ─── Auto-lock ────────────────────────────────────────────────────────────

  Future<int> getAutoLockMinutes() async {
    final val = await _storage.read(key: _kAutoLock);
    _autoLockMinutes = int.tryParse(val ?? '5') ?? 5;
    return _autoLockMinutes;
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    _autoLockMinutes = minutes;
    await _storage.write(key: _kAutoLock, value: minutes.toString());
  }

  void resetAutoLockTimer(void Function() onLock) {
    _autoLockTimer?.cancel();
    if (_autoLockMinutes == 0) return;
    _autoLockTimer = Timer(Duration(minutes: _autoLockMinutes), onLock);
  }

  void cancelAutoLockTimer() => _autoLockTimer?.cancel();

  // ─── Lock ─────────────────────────────────────────────────────────────────

  void lock() {
    _autoLockTimer?.cancel();
    encryptionService.clearMasterKey();
  }

  // ─── Failed attempts ──────────────────────────────────────────────────────

  Future<int> _getFailedAttempts() async =>
      int.tryParse(await _storage.read(key: _kFailedAttempts) ?? '0') ?? 0;

  Future<int> _getMaxAttempts() async =>
      int.tryParse(await _storage.read(key: _kMaxAttempts) ?? '5') ?? 5;

  Future<void> _incrementFailedAttempts() async {
    final c = await _getFailedAttempts();
    await _storage.write(key: _kFailedAttempts, value: '${c + 1}');
  }

  Future<void> _resetFailedAttempts() =>
      _storage.write(key: _kFailedAttempts, value: '0');

  Future<int> getRemainingAttempts() async {
    final failed = await _getFailedAttempts();
    final max    = await _getMaxAttempts();
    return (max - failed).clamp(0, max);
  }
}

enum AuthResult {
  success,
  wrongPassword,
  lockedOut,
  noPasswordSet,
  biometricFailed,
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final securityServiceProvider = Provider<SecurityService>((ref) {
  return SecurityService();
});
