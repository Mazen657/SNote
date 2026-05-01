import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _kHiveKey = 'snote_hive_aes_key';

/// Box name constants — referenced from repository classes.
const kNotesBox = 'snote_notes';
const kTagsBox = 'snote_tags';
const kSettingsBox = 'snote_settings';

/// Initialises Hive with a randomly-generated AES-256 key that is stored in
/// flutter_secure_storage (Android EncryptedSharedPreferences / iOS Keychain).
///
/// All Hive boxes are encrypted at rest.  The note content is also encrypted
/// at the application layer (see EncryptionService), providing defence-in-depth.
class HiveStorage {
  static late Box notesBox;
  static late Box tagsBox;
  static late Box settingsBox;

  static final FlutterSecureStorage _ss = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<void> init() async {
    await Hive.initFlutter();
    final cipher = HiveAesCipher(await _getOrCreateAesKey());
    notesBox = await Hive.openBox(kNotesBox, encryptionCipher: cipher);
    tagsBox = await Hive.openBox(kTagsBox, encryptionCipher: cipher);
    settingsBox = await Hive.openBox(kSettingsBox, encryptionCipher: cipher);
  }

  static Future<Uint8List> _getOrCreateAesKey() async {
    String? stored = await _ss.read(key: _kHiveKey);
    if (stored == null) {
      final key = Hive.generateSecureKey(); // 32 secure random bytes
      stored = base64UrlEncode(key);
      await _ss.write(key: _kHiveKey, value: stored);
    }
    return base64Url.decode(stored);
  }

  static Future<void> dispose() async {
    await notesBox.close();
    await tagsBox.close();
    await settingsBox.close();
  }

  static Future<void> writeSetting(String key, dynamic value) =>
      settingsBox.put(key, value);

  static T? readSetting<T>(String key, {T? defaultValue}) =>
      settingsBox.get(key, defaultValue: defaultValue) as T?;
}
