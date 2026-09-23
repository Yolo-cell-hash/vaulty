import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Wraps the OS Keychain (iOS) / Keystore-backed storage (Android).
///
/// Holds the 256-bit SQLCipher key, the attachment encryption key and the
/// small set of app preferences. Entries are device-bound: they are never
/// synced to iCloud Keychain nor included in Android backups.
class SecureKeys {
  SecureKeys._();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    aOptions: AndroidOptions(),
  );

  static const _dbKey = 'db_secret';
  static const _mediaKey = 'media_secret';
  static const _installMarker = '.vaulty_installed';

  static Future<String?> read(String key) => _storage.read(key: key);

  static Future<void> write(String key, String? value) => _storage.write(key: key, value: value);

  static Future<Map<String, String>> readAll() => _storage.readAll();

  /// iOS keeps Keychain items after an uninstall. If the sandbox is fresh but
  /// the Keychain is not, wipe it so a reinstall starts from a clean slate.
  static Future<void> ensureFreshInstallConsistency() async {
    final dir = await getApplicationSupportDirectory();
    final marker = File(p.join(dir.path, _installMarker));
    if (!await marker.exists()) {
      await _storage.deleteAll();
      await marker.create(recursive: true);
    }
  }

  /// Hex-encoded 256-bit key for SQLCipher, created with the platform CSPRNG.
  static Future<String> databaseKey() async {
    final existing = await _storage.read(key: _dbKey);
    if (existing != null && existing.length == 64) return existing;
    final key = _hex(_randomBytes(32));
    await _storage.write(key: _dbKey, value: key);
    return key;
  }

  static Future<Uint8List> mediaKey() async {
    var existing = await _storage.read(key: _mediaKey);
    if (existing == null || existing.length != 64) {
      existing = _hex(_randomBytes(32));
      await _storage.write(key: _mediaKey, value: existing);
    }
    return _unhex(existing);
  }

  static Future<void> wipeEverything() => _storage.deleteAll();

  static Uint8List _randomBytes(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
  }

  static String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _unhex(String s) =>
      Uint8List.fromList(List.generate(s.length ~/ 2, (i) => int.parse(s.substring(i * 2, i * 2 + 2), radix: 16)));
}
