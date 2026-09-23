import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/memory_repository.dart';
import '../data/vault_database.dart';
import '../models/memory.dart';
import '../services/attachment_store.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/settings.dart';

const repository = MemoryRepository();

final vaultProvider = AsyncNotifierProvider<VaultNotifier, List<Memory>>(VaultNotifier.new);

class VaultNotifier extends AsyncNotifier<List<Memory>> {
  @override
  Future<List<Memory>> build() async {
    final items = await repository.loadAll();
    // Repeating dates roll forward, so refresh the OS queue on every launch,
    // and again whenever the reminder defaults change.
    ref.listen(settingsProvider.select((s) => s.reminders), (_, _) => reschedule());
    ref.onDispose(() {
      for (final t in _pendingDeletes.values) {
        t.cancel();
      }
    });
    _schedule(items);
    return items;
  }

  List<Memory> get _items => state.value ?? const [];

  /// Completes once the OS reminder queue matches the latest vault state.
  Future<void> pendingReschedule = Future.value();

  void _schedule(List<Memory> items) {
    // Reminders are derived data; a failure here must never block saving.
    pendingReschedule = NotificationService.rescheduleAll(
      items,
      repository,
      ref.read(settingsProvider).reminders,
    ).catchError((Object e) => debugPrint('reschedule failed: $e'));
  }

  /// Re-plans every reminder (e.g. after the default time changes).
  void reschedule() => _schedule(_items);

  Future<void> _reload() async {
    final items = await repository.loadAll();
    _schedule(items);
    state = AsyncData(items);
    ref.invalidate(archivedProvider);
  }

  Future<void> save(Memory memory) async {
    final previous = _items.where((m) => m.id == memory.id).firstOrNull;
    await repository.save(memory.copyWith(updatedAt: DateTime.now()));
    if (previous != null) {
      final kept = memory.attachments.map((a) => a.id).toSet();
      for (final a in previous.attachments.where((a) => !kept.contains(a.id))) {
        await AttachmentStore.remove(a);
      }
    }
    await _reload();
  }

  Future<void> setArchived(String id, bool archived) async {
    await repository.setArchived(id, archived);
    await _reload();
  }

  /// Sets a new date on a one-off item ("Renewed it!").
  Future<void> renew(Memory memory, DateTime newDate) =>
      save(memory.copyWith(expiryDate: DateTime(newDate.year, newDate.month, newDate.day)));

  final _pendingDeletes = <String, Timer>{};

  /// Deletes with an undo window: the memory disappears now, but is only
  /// removed for good (with its photos) once [VaultDatabase.undoWindow] passes.
  /// If the app is closed first, the purge on next open finishes the job.
  Future<void> delete(Memory memory) async {
    await repository.softDelete(memory.id);
    _pendingDeletes.remove(memory.id)?.cancel();
    _pendingDeletes[memory.id] = Timer(VaultDatabase.undoWindow, () => _finishDelete(memory));
    await _reload();
  }

  Future<void> undoDelete(String id) async {
    _pendingDeletes.remove(id)?.cancel();
    await repository.undoDelete(id);
    await _reload();
  }

  Future<void> _finishDelete(Memory memory) async {
    _pendingDeletes.remove(memory.id);
    try {
      await repository.finishDelete(memory.id);
      for (final a in memory.attachments) {
        await AttachmentStore.remove(a);
      }
    } catch (e) {
      debugPrint('finishing delete failed (will retry on next open): $e');
    }
  }

  /// Renames or re-emojis a person/tag; renaming onto an existing name merges.
  Future<String> updateTag(Tag tag) async {
    final survivor = await repository.updateTag(tag);
    await _reload();
    return survivor;
  }

  Future<void> deleteTag(String tagId) async {
    await repository.deleteTag(tagId);
    await _reload();
  }

  /// Everything in the vault, archived items included, for backups.
  Future<List<Memory>> snapshot() async => [...await repository.loadAll(), ...await repository.loadAll(archived: true)];

  /// Merges a decrypted backup. For ids that already exist, the copy that
  /// was edited most recently wins, so an old backup never clobbers new edits.
  Future<RestoreSummary> restore(BackupContents backup) async {
    final existing = {for (final m in await snapshot()) m.id: m};
    var added = 0, updated = 0, skipped = 0;
    for (final incoming in backup.memories) {
      final current = existing[incoming.id];
      if (current != null && !incoming.updatedAt.isAfter(current.updatedAt)) {
        skipped++;
        continue;
      }
      final attachments = <Attachment>[];
      for (final a in incoming.attachments) {
        final bytes = backup.photos[a.id];
        if (bytes != null) attachments.add(await AttachmentStore.importBytes(bytes, mimeType: a.mimeType));
      }
      await repository.save(incoming.copyWith(attachments: attachments));
      if (current != null) {
        for (final a in current.attachments) {
          await AttachmentStore.remove(a);
        }
        updated++;
      } else {
        added++;
      }
    }
    await _reload();
    ref.invalidate(archivedProvider);
    return RestoreSummary(added: added, updated: updated, skipped: skipped);
  }

  Future<void> nuke() async {
    for (final t in _pendingDeletes.values) {
      t.cancel();
    }
    _pendingDeletes.clear();
    await NotificationService.cancelAll();
    await AttachmentStore.wipe();
    await VaultDatabase.destroy();
    state = const AsyncData([]);
  }
}

class RestoreSummary {
  const RestoreSummary({required this.added, required this.updated, required this.skipped});

  final int added;
  final int updated;
  final int skipped;
}

final remindersProvider = FutureProvider.family<List<Reminder>, String>((ref, memoryId) async {
  ref.watch(vaultProvider);
  await ref.read(vaultProvider.notifier).pendingReschedule;
  return repository.remindersFor(memoryId);
});

/// Every person and tag, most used first.
final tagsProvider = FutureProvider<List<Tag>>((ref) async {
  ref.watch(vaultProvider);
  return repository.loadTags();
});

final peopleProvider = Provider<List<Tag>>(
  (ref) => (ref.watch(tagsProvider).value ?? const <Tag>[]).where((t) => t.isPerson).toList(),
);

final archivedProvider = FutureProvider<List<Memory>>((ref) async {
  ref.watch(vaultProvider);
  return repository.loadAll(archived: true);
});

/// Items with an expiry date, most urgent first.
final radarProvider = Provider<List<Memory>>((ref) {
  final items = ref.watch(vaultProvider).value ?? const <Memory>[];
  return items.where((m) => m.hasExpiry).toList()..sort((a, b) => a.nextDate!.compareTo(b.nextDate!));
});

final memoryByIdProvider = Provider.family<Memory?, String>((ref, id) {
  final items = ref.watch(vaultProvider).value ?? const <Memory>[];
  return items.where((m) => m.id == id).firstOrNull;
});

/// Whether the vault UI is currently unlocked.
final unlockedProvider = NotifierProvider<UnlockNotifier, bool>(UnlockNotifier.new);

class UnlockNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}
