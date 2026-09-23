import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../models/memory.dart';
import 'attachment_store.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What a decrypted backup contains, ready to merge into the vault.
class BackupContents {
  const BackupContents({required this.memories, required this.photos, required this.exportedAt});

  final List<Memory> memories;

  /// Plain photo bytes keyed by the attachment id in the backup.
  final Map<String, Uint8List> photos;
  final DateTime exportedAt;

  int get photoCount => photos.length;
}

/// Portable, passphrase-encrypted `.vault` backups.
///
/// File layout (all integers big-endian):
///
/// ```
/// "VLTY"  magic                 4 bytes
/// version                       1 byte
/// PBKDF2-HMAC-SHA256 iterations 4 bytes
/// salt                         16 bytes
/// AES-GCM nonce                12 bytes
/// ciphertext                    n bytes   gzip(JSON payload)
/// AES-GCM tag                  16 bytes
/// ```
///
/// The header is authenticated as associated data, so tampering with the
/// iteration count or salt is detected just like tampering with the payload.
class VaultBackup {
  VaultBackup._();

  static const _magic = [0x56, 0x4C, 0x54, 0x59]; // VLTY
  static const formatVersion = 1;

  /// OWASP 2023 guidance for PBKDF2-HMAC-SHA256.
  static const defaultIterations = 600000;
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;
  static const _headerLength = 4 + 1 + 4 + _saltLength;

  static const minPassphraseLength = 8;

  static String suggestedFileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'vaulty-backup-${now.year}-${two(now.month)}-${two(now.day)}.vault';
  }

  /// Serialises [memories] (with decrypted photos when [includePhotos]) and
  /// seals them with [passphrase]. Heavy crypto runs off the UI isolate.
  static Future<Uint8List> export({
    required List<Memory> memories,
    required String passphrase,
    bool includePhotos = true,
    int iterations = defaultIterations,
  }) async {
    final photos = <String, String>{};
    if (includePhotos) {
      for (final m in memories) {
        for (final a in m.attachments) {
          try {
            photos[a.id] = base64Encode(await AttachmentStore.read(a));
          } on Object {
            // A missing or unreadable photo shouldn't sink the whole backup.
          }
        }
      }
    }
    final payload = utf8.encode(
      jsonEncode({
        'app': 'vaulty',
        'format': formatVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'memories': [for (final m in memories) _memoryToJson(m, includePhotos ? photos.keys.toSet() : const {})],
        'photos': photos,
      }),
    );
    return Isolate.run(() => seal(payload, passphrase, iterations: iterations));
  }

  /// Decrypts a `.vault` file. Throws [BackupException] with a friendly
  /// message for wrong passphrases, damaged files or unknown formats.
  static Future<BackupContents> open(Uint8List file, String passphrase) async {
    final json = await Isolate.run(() => unseal(file, passphrase));
    return _parse(json);
  }

  // ------------------------------------------------------------- sealing --

  static Future<Uint8List> seal(List<int> plaintext, String passphrase, {int iterations = defaultIterations}) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(_saltLength, (_) => rnd.nextInt(256));
    final nonce = List<int>.generate(_nonceLength, (_) => rnd.nextInt(256));
    final header = BytesBuilder()
      ..add(_magic)
      ..addByte(formatVersion)
      ..add(_uint32(iterations))
      ..add(salt);
    final headerBytes = header.toBytes();

    final key = await _deriveKey(passphrase, salt, iterations);
    final box = await AesGcm.with256bits().encrypt(
      gzip.encode(plaintext),
      secretKey: key,
      nonce: nonce,
      aad: headerBytes,
    );
    return (BytesBuilder(copy: false)
          ..add(headerBytes)
          ..add(box.nonce)
          ..add(box.cipherText)
          ..add(box.mac.bytes))
        .toBytes();
  }

  static Future<String> unseal(Uint8List file, String passphrase) async {
    if (file.length < _headerLength + _nonceLength + _macLength || !_listEquals(file.sublist(0, 4), _magic)) {
      throw const BackupException('That doesn\'t look like a Vaulty backup file.');
    }
    final version = file[4];
    if (version > formatVersion) {
      throw const BackupException('This backup was made by a newer Vaulty. Update the app and try again.');
    }
    final iterations = ByteData.sublistView(file, 5, 9).getUint32(0);
    if (iterations < 10000 || iterations > 10000000) {
      throw const BackupException('This backup file is damaged.');
    }
    final headerBytes = file.sublist(0, _headerLength);
    final salt = file.sublist(9, _headerLength);
    final nonce = file.sublist(_headerLength, _headerLength + _nonceLength);
    final cipherText = file.sublist(_headerLength + _nonceLength, file.length - _macLength);
    final mac = Mac(file.sublist(file.length - _macLength));

    final key = await _deriveKey(passphrase, salt, iterations);
    final List<int> compressed;
    try {
      compressed = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: key,
        aad: headerBytes,
      );
    } on SecretBoxAuthenticationError {
      throw const BackupException('Wrong passphrase, or the file was changed.');
    }
    return utf8.decode(gzip.decode(compressed));
  }

  static Future<SecretKey> _deriveKey(String passphrase, List<int> salt, int iterations) {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    return kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  // ------------------------------------------------------------ JSON I/O --

  static Map<String, Object?> _memoryToJson(Memory m, Set<String> photoIds) => {
    'id': m.id,
    'title': m.title,
    'rawContent': m.rawContent,
    'category': m.category.dbValue,
    'isSensitive': m.isSensitive,
    'expiryDate': m.expiryDate == null ? null : _day(m.expiryDate!),
    'recurrence': m.recurrence.dbValue,
    'remind': m.remind,
    'reminderOffsets': m.reminderOffsets,
    'reminderMinutes': m.reminderMinutes,
    'isArchived': m.isArchived,
    'createdAt': m.createdAt.toUtc().toIso8601String(),
    'updatedAt': m.updatedAt.toUtc().toIso8601String(),
    'metadata': [
      for (final e in m.metadata) {'id': e.id, 'key': e.key, 'value': e.value},
    ],
    'attachments': [
      for (final a in m.attachments)
        if (photoIds.contains(a.id)) {'id': a.id, 'mimeType': a.mimeType},
    ],
    'tags': [
      for (final t in m.tags) {'name': t.name, 'kind': t.kind.dbValue, 'emoji': t.emoji},
    ],
  };

  static BackupContents _parse(String json) {
    try {
      final root = jsonDecode(json) as Map<String, dynamic>;
      if (root['app'] != 'vaulty') throw const FormatException();
      final photos = <String, Uint8List>{
        for (final e in (root['photos'] as Map<String, dynamic>? ?? {}).entries) e.key: base64Decode(e.value as String),
      };
      final memories = [
        for (final raw in root['memories'] as List<dynamic>) _memoryFromJson(raw as Map<String, dynamic>),
      ];
      return BackupContents(
        memories: memories,
        photos: photos,
        exportedAt: DateTime.parse(root['exportedAt'] as String).toLocal(),
      );
    } on BackupException {
      rethrow;
    } on Object {
      throw const BackupException('This backup file is damaged.');
    }
  }

  static Memory _memoryFromJson(Map<String, dynamic> j) {
    final expiry = j['expiryDate'] as String?;
    DateTime? day;
    if (expiry != null) {
      final parts = expiry.split('-').map(int.parse).toList();
      day = DateTime(parts[0], parts[1], parts[2]);
    }
    return Memory(
      id: j['id'] as String,
      title: j['title'] as String,
      rawContent: (j['rawContent'] as String?) ?? '',
      category: MemoryCategory.fromDb(j['category'] as String?),
      isSensitive: j['isSensitive'] as bool? ?? false,
      expiryDate: day,
      recurrence: Recurrence.fromDb(j['recurrence'] as String?),
      remind: j['remind'] as bool? ?? true,
      reminderOffsets: (j['reminderOffsets'] as List<dynamic>?)?.map((e) => e as int).toList(),
      reminderMinutes: j['reminderMinutes'] as int?,
      isArchived: j['isArchived'] as bool? ?? false,
      createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(j['updatedAt'] as String).toLocal(),
      metadata: [
        for (final e in (j['metadata'] as List<dynamic>? ?? const []))
          MetaEntry(id: e['id'] as String, key: e['key'] as String, value: e['value'] as String),
      ],
      // Tags are matched by name on save, so fresh ids are fine here.
      tags: [
        for (final t in (j['tags'] as List<dynamic>? ?? const []))
          Tag(
            id: const Uuid().v4(),
            name: t['name'] as String,
            kind: TagKind.fromDb(t['kind'] as String?),
            emoji: t['emoji'] as String?,
          ),
      ],
      // Placeholder paths: restore swaps these for freshly encrypted files.
      attachments: [
        for (final a in (j['attachments'] as List<dynamic>? ?? const []))
          Attachment(id: a['id'] as String, filePath: '', mimeType: a['mimeType'] as String),
      ],
    );
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static List<int> _uint32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
