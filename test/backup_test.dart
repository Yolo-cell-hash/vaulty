import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaulty/models/memory.dart';
import 'package:vaulty/services/backup_service.dart';

void main() {
  // Low iteration count keeps the suite fast; the format stores the count.
  const fast = 20000;

  Memory memory() => Memory(
    id: 'abc',
    title: 'Passport',
    rawContent: 'Renew at the consulate',
    category: MemoryCategory.expiryDoc,
    isSensitive: true,
    expiryDate: DateTime(2031, 3, 15),
    createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    updatedAt: DateTime.utc(2026, 5, 6, 7, 8, 9),
    metadata: const [MetaEntry(id: 'm1', key: 'Passport #', value: 'K1234567')],
    remind: false,
    reminderOffsets: const [14, 1],
    reminderMinutes: 1170,
    tags: const [
      Tag(id: 't1', name: 'Mom', kind: TagKind.person, emoji: '👩'),
      Tag(id: 't2', name: 'travel', kind: TagKind.tag),
    ],
  );

  Future<Uint8List> sealed(String pass) => VaultBackup.seal(
    utf8.encode(
      jsonEncode({
        'app': 'vaulty',
        'format': 1,
        'exportedAt': '2026-09-23T10:00:00Z',
        'memories': [],
        'photos': {
          'p1': base64Encode([1, 2, 3]),
        },
      }),
    ),
    pass,
    iterations: fast,
  );

  test('round-trips memories through export and open', () async {
    final file = await VaultBackup.export(
      memories: [memory()],
      passphrase: 'correct horse',
      includePhotos: false,
      iterations: fast,
    );
    expect(String.fromCharCodes(file.sublist(0, 4)), 'VLTY');
    expect(utf8.decode(file, allowMalformed: true), isNot(contains('K1234567')));

    final back = await VaultBackup.open(file, 'correct horse');
    final m = back.memories.single;
    expect(m.title, 'Passport');
    expect(m.expiryDate, DateTime(2031, 3, 15));
    expect(m.isSensitive, isTrue);
    expect(m.category, MemoryCategory.expiryDoc);
    expect(m.metadata.single.value, 'K1234567');
    expect(m.updatedAt.toUtc(), DateTime.utc(2026, 5, 6, 7, 8, 9));
    expect(m.people.single.name, 'Mom');
    expect(m.people.single.emoji, '👩');
    expect(m.plainTags.single.name, 'travel');
    expect(m.remind, isFalse);
    expect(m.reminderOffsets, [14, 1]);
    expect(m.reminderMinutes, 1170);
  });

  test('keeps photo bytes', () async {
    final back = await VaultBackup.open(await sealed('pw-123456'), 'pw-123456');
    expect(back.photos['p1'], [1, 2, 3]);
  });

  test('wrong passphrase is rejected', () async {
    final file = await sealed('right-pass');
    expect(
      () => VaultBackup.open(file, 'wrong-pass'),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('Wrong passphrase'))),
    );
  });

  test('tampering with header or body is detected', () async {
    final body = Uint8List.fromList(await sealed('pw-123456'));
    body[body.length - 20] ^= 1;
    expect(() => VaultBackup.open(body, 'pw-123456'), throwsA(isA<BackupException>()));

    final salt = Uint8List.fromList(await sealed('pw-123456'));
    salt[12] ^= 1; // inside the authenticated salt
    expect(() => VaultBackup.open(salt, 'pw-123456'), throwsA(isA<BackupException>()));
  });

  test('random files are refused politely', () async {
    expect(
      () => VaultBackup.open(Uint8List.fromList(utf8.encode('hello, not a backup at all!!')), 'x'),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('doesn\'t look like'))),
    );
  });

  test('default key derivation cost', () async {
    final sw = Stopwatch()..start();
    await VaultBackup.seal(utf8.encode('{}'), 'benchmark-pass');
    // ignore: avoid_print
    print('PBKDF2 x${VaultBackup.defaultIterations} (JIT): ${sw.elapsedMilliseconds} ms');
  });
}
