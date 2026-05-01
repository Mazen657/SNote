import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

import 'key_derivation_service.dart';

const _kTitleContext   = 'snote-title-v1';
const _kContentContext = 'snote-content-v1';

/// AES-256-CBC encryption with per-note HKDF-derived keys.
/// The master key lives in memory only; it is wiped on lock.
/// Each note carries a random salt; re-saving regenerates the salt,
/// rotating every key derived from it.
class EncryptionService {
  static const int _ivBytes = 16;

  Uint8List? _masterKey;

  bool get isInitialized => _masterKey != null;

  /// Read-only access to the raw master key bytes (used for biometric cache).
  Uint8List get masterKey {
    if (_masterKey == null) {
      throw StateError('EncryptionService: no master key loaded.');
    }
    return _masterKey!;
  }

  void setMasterKey(Uint8List key) {
    _masterKey = Uint8List.fromList(key);
  }

  void clearMasterKey() {
    if (_masterKey != null) {
      for (int i = 0; i < _masterKey!.length; i++) {
        _masterKey![i] = 0;
      }
      _masterKey = null;
    }
  }

  // ─── Salt ─────────────────────────────────────────────────────────────────

  String generateNoteSalt() =>
      base64.encode(KeyDerivationService.generateSalt());

  // ─── Public encrypt / decrypt ─────────────────────────────────────────────

  Future<String> encryptTitle(String plaintext, String noteSaltB64) =>
      _encrypt(plaintext, noteSaltB64, _kTitleContext);

  Future<String> decryptTitle(String ciphertext, String noteSaltB64) =>
      _decrypt(ciphertext, noteSaltB64, _kTitleContext);

  Future<String> encryptContent(String plaintext, String noteSaltB64) =>
      _encrypt(plaintext, noteSaltB64, _kContentContext);

  Future<String> decryptContent(String ciphertext, String noteSaltB64) =>
      _decrypt(ciphertext, noteSaltB64, _kContentContext);

  // ─── Private ──────────────────────────────────────────────────────────────

  Future<String> _encrypt(
      String plaintext, String noteSaltB64, String context) async {
    _assertReady();
    final noteKey  = await _deriveKey(noteSaltB64, context);
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(noteKey), mode: enc.AESMode.cbc));
    final iv     = _randomIv();
    final result = encrypter.encrypt(plaintext, iv: iv);
    return '${iv.base64}:${result.base64}';
  }

  Future<String> _decrypt(
      String ciphertext, String noteSaltB64, String context) async {
    _assertReady();
    final parts = ciphertext.split(':');
    if (parts.length != 2) {
      throw const EncryptionException('Malformed ciphertext — expected IV:data.');
    }
    final noteKey  = await _deriveKey(noteSaltB64, context);
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(noteKey), mode: enc.AESMode.cbc));
    final iv        = enc.IV.fromBase64(parts[0]);
    final encrypted = enc.Encrypted.fromBase64(parts[1]);
    return encrypter.decrypt(encrypted, iv: iv);
  }

  Future<Uint8List> _deriveKey(String noteSaltB64, String context) async {
    final noteSalt = base64.decode(noteSaltB64);
    return KeyDerivationService.deriveNoteKey(
      _masterKey!,
      noteSalt,
      context: context,
    );
  }

  enc.IV _randomIv() {
    final rng   = Random.secure();
    final bytes = Uint8List(_ivBytes);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return enc.IV(bytes);
  }

  void _assertReady() {
    if (_masterKey == null) {
      throw const EncryptionException(
          'EncryptionService: no master key. Authenticate first.');
    }
  }
}

class EncryptionException implements Exception {
  final String message;
  const EncryptionException(this.message);
  @override
  String toString() => 'EncryptionException: $message';
}