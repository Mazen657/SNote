import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' hide Hmac;
import 'package:cryptography/cryptography.dart';

/// Handles all cryptographic key derivation for SNote.
///
/// - PBKDF2-HMAC-SHA256 derives the 256-bit master key from the user password.
/// - HKDF-SHA256 derives a unique 256-bit key for each note field (title/content)
///   from the master key and a per-note random salt.
/// - SHA-256 + pepper creates a one-way password hash stored for verification only.
class KeyDerivationService {
  // 100 000 iterations balances security (>= NIST minimum) with login latency.
  static const int _pbkdf2Iterations = 100000;
  static const int _keyBits = 256;
  static const int _saltBytes = 32;

  // Pepper is mixed into the verification hash so a raw SHA-256 rainbow table
  // cannot be used even if the hash leaks.
  static const String _pepper = 'SNote_v1_Offline_Secure_2024';

  // ─── Master Key ───────────────────────────────────────────────────────────

  /// Derives a 256-bit master key from [password] and [salt] using
  /// PBKDF2-HMAC-SHA256.  This is intentionally slow to resist brute force.
  static Future<Uint8List> deriveMasterKey(
    String password,
    Uint8List salt,
  ) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: _keyBits,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  // ─── Per-Note Key ─────────────────────────────────────────────────────────

  /// Derives a 256-bit per-note key using HKDF-SHA256.
  ///
  /// [masterKey]  — held in memory, never stored.
  /// [noteSalt]   — random 32-byte value stored alongside the encrypted note.
  /// [context]    — differentiates the title key from the content key for the
  ///                same note so they use distinct keys even with the same salt.
  static Future<Uint8List> deriveNoteKey(
    Uint8List masterKey,
    Uint8List noteSalt, {
    String context = 'snote-default-v1',
  }) async {
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(masterKey),
      nonce: noteSalt,
      info: utf8.encode(context),
    );
    final bytes = await derived.extractBytes();
    return Uint8List.fromList(bytes);
  }

  // ─── Salt Generation ──────────────────────────────────────────────────────

  /// Returns a cryptographically secure 32-byte random salt.
  static Uint8List generateSalt() {
    final rng = Random.secure();
    final bytes = Uint8List(_saltBytes);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }

  // ─── Password Verification Hash ───────────────────────────────────────────

  /// Returns a one-way SHA-256 hash of [password] + pepper.
  /// Used only to verify login attempts — never for key derivation.
  static String hashPasswordForStorage(String password) {
    final data = utf8.encode('$password$_pepper');
    return sha256.convert(data).toString();
  }

  /// Returns true when [password] matches [storedHash].
  static bool verifyPasswordHash(String password, String storedHash) {
    return hashPasswordForStorage(password) == storedHash;
  }
}