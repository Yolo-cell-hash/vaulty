import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../services/secure_keys.dart';

/// SQLCipher (AES-256) database holding every memory, plus an FTS5 index.
class VaultDatabase {
  VaultDatabase._();

  static Database? _db;
  static Future<Database>? _opening;

  /// Whether the SQLCipher build on this device ships FTS5. Search falls back
  /// to LIKE matching when it does not.
  static bool ftsAvailable = false;

  /// Bump when adding a `_migrateToVn` step; each step must be idempotent.
  ///
  /// History: v1 core tables · v2 people & tags · v3 repeating dates ·
  /// v4 per-item reminders + soft delete (undo).
  static const schemaVersion = 4;

  /// Tests inject an in-memory database opened with [onConfigure] /
  /// [onCreate] / [onUpgrade] / [onOpen] so the real schema is exercised.
  @visibleForTesting
  static void useForTesting(Database db) => _db = db;

  static Future<Database> get instance {
    final db = _db;
    if (db != null && db.isOpen) return Future.value(db);
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  static Future<String> _path() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'vaulty.db');
  }

  static Future<Database> _open() async {
    final hexKey = await SecureKeys.databaseKey();
    final db = await openDatabase(
      await _path(),
      // x'…' makes SQLCipher use the 256-bit key directly (no passphrase KDF).
      password: "x'$hexKey'",
      version: schemaVersion,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onOpen: onOpen,
    );
    _db = db;
    return db;
  }

  static Future<void> onConfigure(Database db) => db.execute('PRAGMA foreign_keys = ON');

  static Future<void> onCreate(Database db, int version) async {
    await createV1(db);
    await onUpgrade(db, 1, version);
  }

  static Future<void> onUpgrade(Database db, int from, int to) async {
    if (from < 2) await _migrateToV2(db);
    if (from < 3) await _migrateToV3(db);
    if (from < 4) await _migrateToV4(db);
  }

  static Future<void> onOpen(Database db) async {
    await _ensureFts(db);
    await _purgeDeleted(db);
  }

  /// The original v1 schema. Kept verbatim so upgrades can be tested.
  @visibleForTesting
  static Future<void> createV1(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        raw_content TEXT,
        category TEXT CHECK(category IN ('STATIC_FACT', 'EXPIRY_DOC', 'SUBSCRIPTION', 'MEASUREMENT', 'OTHER')) NOT NULL DEFAULT 'STATIC_FACT',
        is_sensitive INTEGER NOT NULL DEFAULT 0,
        expiry_date TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
        updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS memory_metadata (
        id TEXT PRIMARY KEY NOT NULL,
        memory_id TEXT NOT NULL,
        meta_key TEXT NOT NULL,
        meta_value TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(memory_id) REFERENCES memories(id) ON DELETE CASCADE
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS memory_attachments (
        id TEXT PRIMARY KEY NOT NULL,
        memory_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        FOREIGN KEY(memory_id) REFERENCES memories(id) ON DELETE CASCADE
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS memory_reminders (
        id TEXT PRIMARY KEY NOT NULL,
        memory_id TEXT NOT NULL,
        notification_id TEXT NOT NULL,
        scheduled_for TEXT NOT NULL,
        offset_days INTEGER NOT NULL,
        FOREIGN KEY(memory_id) REFERENCES memories(id) ON DELETE CASCADE
      )''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_meta_memory ON memory_metadata(memory_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_att_memory ON memory_attachments(memory_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_rem_memory ON memory_reminders(memory_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_mem_expiry ON memories(expiry_date)');
    await batch.commit(noResult: true);
  }

  /// Adds a column unless it already exists (keeps migrations re-runnable).
  static Future<void> _addColumn(Database db, String table, String column, String ddl) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => c['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $ddl');
  }

  /// v3: repeating dates (birthdays, monthly subscriptions).
  static Future<void> _migrateToV3(Database db) =>
      _addColumn(db, 'memories', 'recurrence', "TEXT NOT NULL DEFAULT 'NONE'");

  /// v4: per-item reminders and soft delete.
  ///
  /// * reminder_offsets: comma-separated days before (NULL = app default)
  /// * reminder_minutes: minutes after midnight (NULL = app default)
  /// * remind: 0 mutes reminders for this item
  /// * deleted_at: set while a delete can still be undone
  static Future<void> _migrateToV4(Database db) async {
    await _addColumn(db, 'memories', 'reminder_offsets', 'TEXT');
    await _addColumn(db, 'memories', 'reminder_minutes', 'INTEGER');
    await _addColumn(db, 'memories', 'remind', 'INTEGER NOT NULL DEFAULT 1');
    await _addColumn(db, 'memories', 'deleted_at', 'TEXT');
  }

  /// How long a delete can be undone. Rows past it are purged on open.
  static const undoWindow = Duration(seconds: 8);

  /// Finishes deletes whose undo window ran out (e.g. the app was closed
  /// right after deleting). Photos are cleaned up by the caller.
  static Future<void> _purgeDeleted(Database db) async {
    final cutoff = '${DateTime.now().toUtc().subtract(undoWindow).toIso8601String().split('.').first}Z';
    const expired = 'deleted_at IS NOT NULL AND deleted_at < ?';
    final files = await db.rawQuery(
      'SELECT a.file_path FROM memory_attachments a JOIN memories m ON m.id = a.memory_id WHERE m.$expired',
      [cutoff],
    );
    await db.delete('memories', where: expired, whereArgs: [cutoff]);
    for (final f in files) {
      try {
        await File(f['file_path'] as String).delete();
      } on Object {
        // Already gone; nothing to clean.
      }
    }
  }

  /// v2: people & tags.
  static Future<void> _migrateToV2(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE IF NOT EXISTS tags (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        kind TEXT CHECK(kind IN ('PERSON', 'TAG')) NOT NULL,
        emoji TEXT,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
      )''');
    batch.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name ON tags(kind, name COLLATE NOCASE)');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS memory_tags (
        memory_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (memory_id, tag_id),
        FOREIGN KEY(memory_id) REFERENCES memories(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_memory_tags_tag ON memory_tags(tag_id)');
    await batch.commit(noResult: true);
  }

  static Future<void> _ensureFts(Database db) async {
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
          memory_id UNINDEXED,
          title,
          raw_content,
          metadata_searchable,
          tokenize = 'porter unicode61'
        )''');
      // Metadata is written after the parent row, so inserts are indexed by
      // the repository once the whole memory is saved; deletes stay automatic.
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS memories_after_delete AFTER DELETE ON memories BEGIN
          DELETE FROM memories_fts WHERE memory_id = OLD.id;
        END''');
      ftsAvailable = true;
    } on DatabaseException catch (e) {
      debugPrint('FTS5 unavailable, falling back to LIKE search: $e');
      ftsAvailable = false;
    }
  }

  static Future<void> destroy() async {
    await _db?.close();
    _db = null;
    await deleteDatabase(await _path());
  }
}
