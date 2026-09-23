import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/memory.dart';
import 'secure_keys.dart';

/// Photos are stored AES-256-GCM encrypted inside the app sandbox and only
/// ever decrypted into memory for display.
class AttachmentStore {
  AttachmentStore._();

  static final _algo = AesGcm.with256bits();
  static SecretKey? _key;
  static final Map<String, Uint8List> _cache = {};

  static Future<SecretKey> _secret() async => _key ??= SecretKey(await SecureKeys.mediaKey());

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'vault_media'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Encrypts [source] into the vault and deletes the plaintext original.
  static Future<Attachment> importFile(File source, {String mimeType = 'image/jpeg'}) async {
    final bytes = await source.readAsBytes();
    final box = await _algo.encrypt(bytes, secretKey: await _secret());
    final id = const Uuid().v4();
    final out = File(p.join((await _dir()).path, '$id.vault'));
    await out.writeAsBytes(box.concatenation(), flush: true);
    _cache[out.path] = bytes;
    try {
      await source.delete();
    } catch (_) {
      // Picker temp files may already be gone; nothing sensitive is left behind.
    }
    return Attachment(id: id, filePath: out.path, mimeType: mimeType);
  }

  /// Encrypts in-memory bytes (e.g. a photo from a restored backup).
  static Future<Attachment> importBytes(Uint8List bytes, {String mimeType = 'image/jpeg'}) async {
    final box = await _algo.encrypt(bytes, secretKey: await _secret());
    final id = const Uuid().v4();
    final out = File(p.join((await _dir()).path, '$id.vault'));
    await out.writeAsBytes(box.concatenation(), flush: true);
    return Attachment(id: id, filePath: out.path, mimeType: mimeType);
  }

  static Future<Uint8List> read(Attachment a) async {
    final cached = _cache[a.filePath];
    if (cached != null) return cached;
    final data = await File(a.filePath).readAsBytes();
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: _algo.nonceLength,
      macLength: _algo.macAlgorithm.macLength,
    );
    final clear = Uint8List.fromList(await _algo.decrypt(box, secretKey: await _secret()));
    if (_cache.length > 24) _cache.remove(_cache.keys.first);
    _cache[a.filePath] = clear;
    return clear;
  }

  static Future<void> remove(Attachment a) async {
    _cache.remove(a.filePath);
    final f = File(a.filePath);
    if (await f.exists()) await f.delete();
  }

  static void clearCache() => _cache.clear();

  static Future<void> wipe() async {
    _cache.clear();
    _key = null;
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
