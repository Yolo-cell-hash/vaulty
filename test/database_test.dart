import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaulty/data/memory_repository.dart';
import 'package:vaulty/data/vault_database.dart';
import 'package:vaulty/models/memory.dart';

/// Runs the real schema, migrations and repository against plain SQLite
/// (SQLCipher only adds encryption on top of the same SQL).
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  const repo = MemoryRepository();
  late Directory dir;

  OpenDatabaseOptions current() => OpenDatabaseOptions(
    version: VaultDatabase.schemaVersion,
    onConfigure: VaultDatabase.onConfigure,
    onCreate: VaultDatabase.onCreate,
    onUpgrade: VaultDatabase.onUpgrade,
    onOpen: VaultDatabase.onOpen,
  );

  Memory memory(String id, {String title = 'Passport', DateTime? expiry}) => Memory(
    id: id,
    title: title,
    category: MemoryCategory.expiryDoc,
    expiryDate: expiry ?? DateTime(2031, 3, 15),
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    metadata: [MetaEntry(id: 'k-$id', key: 'Passport #', value: 'K1234567')],
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vaulty_db_test');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on Object {
      // Windows may still hold the file for a moment; temp dirs are cleaned by the OS.
    }
  });

  test('a v1 database upgrades to the current schema without losing data', () async {
    final path = '${dir.path}/vault.db';
    // An install from before people/tags/recurrence/reminders existed.
    final v1 = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: VaultDatabase.onConfigure,
        onCreate: (db, _) => VaultDatabase.createV1(db),
      ),
    );
    await v1.insert('memories', {
      'id': 'old',
      'title': 'Car insurance',
      'category': 'EXPIRY_DOC',
      'expiry_date': '2026-11-12T00:00:00Z',
    });
    await v1.insert('memory_metadata', {'id': 'm1', 'memory_id': 'old', 'meta_key': 'Policy #', 'meta_value': '9812'});
    await v1.close();

    final db = await factory.openDatabase(path, options: current());
    expect(await db.getVersion(), VaultDatabase.schemaVersion);
    final cols = (await db.rawQuery('PRAGMA table_info(memories)')).map((c) => c['name']).toSet();
    expect(cols, containsAll(['recurrence', 'reminder_offsets', 'reminder_minutes', 'remind', 'deleted_at']));
    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']);
    expect(tables, containsAll(['tags', 'memory_tags']));

    VaultDatabase.useForTesting(db);
    final loaded = (await repo.loadAll()).single;
    expect(loaded.title, 'Car insurance');
    expect(loaded.recurrence, Recurrence.none);
    expect(loaded.remind, isTrue);
    expect(loaded.reminderOffsets, isNull);
    expect(loaded.metadata.single.value, '9812');
    await db.close();
  });

  test('migrations can run twice safely', () async {
    final db = await factory.openDatabase('${dir.path}/twice.db', options: current());
    await VaultDatabase.onUpgrade(db, 1, VaultDatabase.schemaVersion);
    await db.close();
  });

  group('repository', () {
    late Database db;

    setUp(() async {
      db = await factory.openDatabase('${dir.path}/repo.db', options: current());
      VaultDatabase.useForTesting(db);
    });

    tearDown(() => db.close());

    test('round-trips reminders, recurrence and tags', () async {
      await repo.save(
        memory('a').copyWith(
          recurrence: Recurrence.yearly,
          reminderOffsets: const [14, 1],
          reminderMinutes: 19 * 60 + 30,
          remind: true,
          tags: const [Tag(id: 't1', name: 'Mom', kind: TagKind.person)],
        ),
      );
      await repo.save(memory('b', title: 'Muted').copyWith(remind: false, reminderOffsets: const []));
      final byId = {for (final m in await repo.loadAll()) m.id: m};
      expect(byId['a']!.reminderOffsets, [14, 1]);
      expect(byId['a']!.reminderMinutes, 19 * 60 + 30);
      expect(byId['a']!.recurrence, Recurrence.yearly);
      expect(byId['a']!.people.single.name, 'Mom');
      expect(byId['b']!.remind, isFalse);
      expect(byId['b']!.reminderOffsets, isEmpty);
    });

    test('soft delete hides, undo restores, finish removes', () async {
      await repo.save(memory('a'));
      await repo.softDelete('a');
      expect(await repo.loadAll(), isEmpty);
      expect(await repo.search('passport'), isEmpty);

      await repo.undoDelete('a');
      expect((await repo.loadAll()).single.id, 'a');
      expect(await repo.search('passport'), ['a']);

      await repo.softDelete('a');
      await repo.finishDelete('a');
      expect(await db.query('memories'), isEmpty);
      expect(await db.query('memory_metadata'), isEmpty, reason: 'children cascade');
    });

    test('deletes left pending past the undo window are purged on open', () async {
      await repo.save(memory('stale'));
      await repo.save(memory('fresh'));
      final old = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      await db.update(
        'memories',
        {'deleted_at': '${old.toIso8601String().split('.').first}Z'},
        where: 'id = ?',
        whereArgs: ['stale'],
      );
      await repo.softDelete('fresh');
      await VaultDatabase.onOpen(db);
      final ids = (await db.query('memories')).map((r) => r['id']).toSet();
      expect(ids, {'fresh'}, reason: 'a just-deleted item can still be undone');
    });
  });
}
