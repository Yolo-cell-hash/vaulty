import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/memory.dart';
import 'vault_database.dart';

class MemoryRepository {
  const MemoryRepository();

  Future<Database> get _db => VaultDatabase.instance;

  // ---------------------------------------------------------------- reads --

  Future<List<Memory>> loadAll({bool archived = false}) async {
    final db = await _db;
    final rows = await db.query(
      'memories',
      where: 'is_archived = ? AND deleted_at IS NULL',
      whereArgs: [archived ? 1 : 0],
      orderBy: 'updated_at DESC',
    );
    if (rows.isEmpty) return [];

    final metaRows = await db.query('memory_metadata', orderBy: 'position ASC');
    final attRows = await db.query('memory_attachments');
    final meta = <String, List<MetaEntry>>{};
    for (final r in metaRows) {
      (meta[r['memory_id'] as String] ??= []).add(
        MetaEntry(id: r['id'] as String, key: r['meta_key'] as String, value: r['meta_value'] as String),
      );
    }
    final tagRows = await db.rawQuery(
      'SELECT mt.memory_id, t.id, t.name, t.kind, t.emoji FROM memory_tags mt '
      'JOIN tags t ON t.id = mt.tag_id ORDER BY t.kind DESC, t.name COLLATE NOCASE',
    );
    final tags = <String, List<Tag>>{};
    for (final r in tagRows) {
      (tags[r['memory_id'] as String] ??= []).add(_tagFromRow(r));
    }
    final atts = <String, List<Attachment>>{};
    for (final r in attRows) {
      (atts[r['memory_id'] as String] ??= []).add(
        Attachment(id: r['id'] as String, filePath: r['file_path'] as String, mimeType: r['mime_type'] as String),
      );
    }
    return rows
        .map((r) => _fromRow(r, meta[r['id']] ?? const [], atts[r['id']] ?? const [], tags[r['id']] ?? const []))
        .toList();
  }

  Future<List<Reminder>> remindersFor(String memoryId) async {
    final db = await _db;
    final rows = await db.query(
      'memory_reminders',
      where: 'memory_id = ?',
      whereArgs: [memoryId],
      orderBy: 'scheduled_for ASC',
    );
    return rows
        .map(
          (r) => Reminder(
            id: r['id'] as String,
            memoryId: r['memory_id'] as String,
            notificationId: r['notification_id'] as String,
            scheduledFor: DateTime.parse(r['scheduled_for'] as String).toLocal(),
            offsetDays: r['offset_days'] as int,
          ),
        )
        .toList();
  }

  // --------------------------------------------------------------- writes --

  Future<void> save(Memory m) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.rawInsert(
        '''
        INSERT INTO memories (id, title, raw_content, category, is_sensitive, expiry_date, recurrence,
          reminder_offsets, reminder_minutes, remind, is_archived, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          raw_content = excluded.raw_content,
          category = excluded.category,
          is_sensitive = excluded.is_sensitive,
          expiry_date = excluded.expiry_date,
          recurrence = excluded.recurrence,
          reminder_offsets = excluded.reminder_offsets,
          reminder_minutes = excluded.reminder_minutes,
          remind = excluded.remind,
          is_archived = excluded.is_archived,
          deleted_at = NULL,
          updated_at = excluded.updated_at''',
        [
          m.id,
          m.title,
          m.rawContent,
          m.category.dbValue,
          m.isSensitive ? 1 : 0,
          _dateToDb(m.expiryDate),
          m.recurrence.dbValue,
          m.reminderOffsets?.join(','),
          m.reminderMinutes,
          m.remind ? 1 : 0,
          m.isArchived ? 1 : 0,
          _stamp(m.createdAt),
          _stamp(m.updatedAt),
        ],
      );

      await txn.delete('memory_metadata', where: 'memory_id = ?', whereArgs: [m.id]);
      for (var i = 0; i < m.metadata.length; i++) {
        final e = m.metadata[i];
        await txn.insert('memory_metadata', {
          'id': e.id,
          'memory_id': m.id,
          'meta_key': e.key,
          'meta_value': e.value,
          'position': i,
        });
      }

      await txn.delete('memory_attachments', where: 'memory_id = ?', whereArgs: [m.id]);
      for (final a in m.attachments) {
        await txn.insert('memory_attachments', {
          'id': a.id,
          'memory_id': m.id,
          'file_path': a.filePath,
          'mime_type': a.mimeType,
        });
      }

      await txn.delete('memory_tags', where: 'memory_id = ?', whereArgs: [m.id]);
      for (final t in m.tags) {
        final tagId = await _resolveTag(txn, t);
        await txn.insert('memory_tags', {
          'memory_id': m.id,
          'tag_id': tagId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      await _index(txn, m.id);
    });
  }

  Future<void> setArchived(String id, bool archived) async {
    final db = await _db;
    await db.update(
      'memories',
      {'is_archived': archived ? 1 : 0, 'updated_at': _stamp(DateTime.now())},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hides a memory immediately; it can be restored until [finishDelete].
  Future<void> softDelete(String id) async {
    final db = await _db;
    await db.update('memories', {'deleted_at': _stamp(DateTime.now())}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> undoDelete(String id) async {
    final db = await _db;
    await db.update('memories', {'deleted_at': null}, where: 'id = ?', whereArgs: [id]);
  }

  /// Permanently removes a soft-deleted memory (cascades to its rows).
  Future<void> finishDelete(String id) async {
    final db = await _db;
    await db.delete('memories', where: 'id = ? AND deleted_at IS NOT NULL', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replaceAllReminders(List<Reminder> reminders) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('memory_reminders');
      for (final r in reminders) {
        await txn.insert('memory_reminders', {
          'id': r.id,
          'memory_id': r.memoryId,
          'notification_id': r.notificationId,
          'scheduled_for': _stamp(r.scheduledFor),
          'offset_days': r.offsetDays,
        });
      }
    });
  }

  // ----------------------------------------------------------------- tags --

  /// All people and tags with how many live memories use each.
  Future<List<Tag>> loadTags() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT t.id, t.name, t.kind, t.emoji,
        (SELECT COUNT(*) FROM memory_tags mt JOIN memories m ON m.id = mt.memory_id
          WHERE mt.tag_id = t.id AND m.is_archived = 0 AND m.deleted_at IS NULL) AS uses
      FROM tags t ORDER BY uses DESC, t.name COLLATE NOCASE''');
    return rows.map(_tagFromRow).toList();
  }

  /// Renames / re-emojis a tag. Renaming onto an existing name merges the two.
  /// Returns the id of the surviving tag.
  Future<String> updateTag(Tag tag) async {
    final db = await _db;
    return db.transaction((txn) async {
      final clash = await txn.query(
        'tags',
        where: 'kind = ? AND name = ? COLLATE NOCASE AND id != ?',
        whereArgs: [tag.kind.dbValue, tag.name.trim(), tag.id],
      );
      final affected = await _memoriesWithTag(txn, tag.id);
      var survivor = tag.id;
      if (clash.isNotEmpty) {
        survivor = clash.first['id'] as String;
        await txn.rawInsert(
          'INSERT OR IGNORE INTO memory_tags (memory_id, tag_id) SELECT memory_id, ? FROM memory_tags WHERE tag_id = ?',
          [survivor, tag.id],
        );
        await txn.delete('tags', where: 'id = ?', whereArgs: [tag.id]);
      } else {
        await txn.update('tags', {'name': tag.name.trim(), 'emoji': tag.emoji}, where: 'id = ?', whereArgs: [tag.id]);
      }
      for (final id in affected) {
        await _index(txn, id);
      }
      return survivor;
    });
  }

  Future<void> deleteTag(String tagId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final affected = await _memoriesWithTag(txn, tagId);
      await txn.delete('tags', where: 'id = ?', whereArgs: [tagId]);
      for (final id in affected) {
        await _index(txn, id);
      }
    });
  }

  Future<List<String>> _memoriesWithTag(DatabaseExecutor txn, String tagId) async {
    final rows = await txn.query('memory_tags', columns: ['memory_id'], where: 'tag_id = ?', whereArgs: [tagId]);
    return rows.map((r) => r['memory_id'] as String).toList();
  }

  /// Finds a tag with the same kind + name (case-insensitive) or creates it.
  Future<String> _resolveTag(DatabaseExecutor txn, Tag t) async {
    final name = t.name.trim();
    final existing = await txn.query(
      'tags',
      columns: ['id'],
      where: 'kind = ? AND name = ? COLLATE NOCASE',
      whereArgs: [t.kind.dbValue, name],
    );
    if (existing.isNotEmpty) return existing.first['id'] as String;
    await txn.insert('tags', {'id': t.id, 'name': name, 'kind': t.kind.dbValue, 'emoji': t.emoji});
    return t.id;
  }

  /// Rebuilds the FTS row for one memory from what's in the database.
  Future<void> _index(DatabaseExecutor txn, String memoryId) async {
    if (!VaultDatabase.ftsAvailable) return;
    final row = await txn.query('memories', where: 'id = ?', whereArgs: [memoryId]);
    await txn.delete('memories_fts', where: 'memory_id = ?', whereArgs: [memoryId]);
    if (row.isEmpty) return;
    final meta = await txn.query('memory_metadata', where: 'memory_id = ?', whereArgs: [memoryId]);
    final tags = await txn.rawQuery(
      'SELECT t.name FROM memory_tags mt JOIN tags t ON t.id = mt.tag_id WHERE mt.memory_id = ?',
      [memoryId],
    );
    await txn.insert('memories_fts', {
      'memory_id': memoryId,
      'title': row.first['title'],
      'raw_content': row.first['raw_content'],
      'metadata_searchable': [
        ...meta.map((e) => '${e['meta_key']} ${e['meta_value']}'),
        ...tags.map((t) => t['name']),
      ].join(' '),
    });
  }

  // --------------------------------------------------------------- search --

  /// Returns ids of matching, non-archived memories, best match first.
  Future<List<String>> search(String query) async {
    final terms = searchTerms(query);
    if (terms.isEmpty) return [];
    final db = await _db;

    if (VaultDatabase.ftsAvailable) {
      Future<List<String>> run(String joiner) async {
        final match = terms.map((t) => '"$t"*').join(joiner);
        final rows = await db.rawQuery(
          '''
          SELECT f.memory_id AS id FROM memories_fts f
          JOIN memories m ON m.id = f.memory_id
          WHERE memories_fts MATCH ? AND m.is_archived = 0 AND m.deleted_at IS NULL
          ORDER BY bm25(memories_fts, 0.0, 10.0, 1.0, 4.0)
          LIMIT 50''',
          [match],
        );
        return rows.map((r) => r['id'] as String).toList();
      }

      try {
        final strict = await run(' AND ');
        if (strict.isNotEmpty || terms.length == 1) return strict;
        return await run(' OR ');
      } on DatabaseException {
        // Fall through to LIKE matching on malformed MATCH expressions.
      }
    }

    final like = terms
        .map(
          (_) => '''
      (m.title LIKE ? OR m.raw_content LIKE ? OR EXISTS (
        SELECT 1 FROM memory_metadata d WHERE d.memory_id = m.id
        AND (d.meta_key LIKE ? OR d.meta_value LIKE ?)))''',
        )
        .join(' AND ');
    final args = [for (final t in terms) ...List.filled(4, '%$t%')];
    final rows = await db.rawQuery(
      'SELECT m.id FROM memories m WHERE m.is_archived = 0 AND m.deleted_at IS NULL AND $like '
      'ORDER BY m.updated_at DESC LIMIT 50',
      args,
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  static const _stopWords = {
    'what',
    'whats',
    'what\'s',
    'is',
    'are',
    'was',
    'the',
    'a',
    'an',
    'my',
    'our',
    'of',
    'for',
    'when',
    'does',
    'do',
    'did',
    'where',
    'which',
    'how',
    'to',
    'me',
    'i',
    'show',
    'find',
    'tell',
    'about',
    'please',
    'again',
    'it',
    'that',
    'this',
    'on',
    'in',
    'and',
    'or',
    'with',
    'from',
    'by',
    'at',
    'be',
    'can',
    'you',
    'your',
    'need',
    'know',
  };

  /// Turns a casual question ("What's Mom's shoe size?") into search terms.
  static List<String> searchTerms(String query) {
    final cleaned = query
        .toLowerCase()
        .replaceAll(RegExp(r"[’']s\b"), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s#.-]', unicode: true), ' ');
    final terms = cleaned
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'^[.#-]+|[.#-]+$'), ''))
        .where((t) => t.isNotEmpty && !_stopWords.contains(t))
        .map(
          (t) => switch (t) {
            'expire' || 'expires' || 'expiring' || 'expiration' || 'expiry' => 'exp',
            _ => t,
          },
        )
        .toSet()
        .toList();
    // FTS5 phrase tokens cannot contain double quotes.
    return terms.map((t) => t.replaceAll('"', '')).where((t) => t.isNotEmpty).toList();
  }

  // -------------------------------------------------------------- helpers --

  Memory _fromRow(Map<String, Object?> r, List<MetaEntry> meta, List<Attachment> atts, List<Tag> tags) => Memory(
    id: r['id'] as String,
    title: r['title'] as String,
    rawContent: (r['raw_content'] as String?) ?? '',
    category: MemoryCategory.fromDb(r['category'] as String?),
    isSensitive: (r['is_sensitive'] as int) == 1,
    expiryDate: _dateFromDb(r['expiry_date'] as String?),
    recurrence: Recurrence.fromDb(r['recurrence'] as String?),
    reminderOffsets: _offsetsFromDb(r['reminder_offsets'] as String?),
    reminderMinutes: r['reminder_minutes'] as int?,
    remind: (r['remind'] as int? ?? 1) == 1,
    isArchived: (r['is_archived'] as int) == 1,
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(r['updated_at'] as String).toLocal(),
    metadata: meta,
    attachments: atts,
    tags: tags,
  );

  static Tag _tagFromRow(Map<String, Object?> r) => Tag(
    id: r['id'] as String,
    name: r['name'] as String,
    kind: TagKind.fromDb(r['kind'] as String?),
    emoji: r['emoji'] as String?,
    uses: (r['uses'] as int?) ?? 0,
  );

  static List<int>? _offsetsFromDb(String? s) {
    if (s == null) return null;
    if (s.isEmpty) return const [];
    return s.split(',').map(int.tryParse).whereType<int>().toList();
  }

  static String _stamp(DateTime d) {
    final u = d.toUtc();
    return '${u.toIso8601String().split('.').first}Z';
  }

  /// Expiry is a calendar day; persist it as UTC midnight of that day.
  static String? _dateToDb(DateTime? d) {
    if (d == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}T00:00:00Z';
  }

  static DateTime? _dateFromDb(String? s) {
    if (s == null || s.isEmpty) return null;
    final u = DateTime.tryParse(s)?.toUtc();
    return u == null ? null : DateTime(u.year, u.month, u.day);
  }
}
