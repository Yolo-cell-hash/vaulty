import '../models/memory.dart';

/// How often to nudge about a backup, in days, and how it reads. 0 is off.
const backupEveryChoices = [
  (0, 'Off'),
  (7, 'Every week'),
  (14, 'Every 2 weeks'),
  (30, 'Every month'),
  (90, 'Every 3 months'),
];

String backupEveryLabel(int days) =>
    backupEveryChoices.where((c) => c.$1 == days).map((c) => c.$2).firstOrNull ?? 'Every $days days';

/// A vault that has never been backed up gets its first nudge this long after
/// its first memory, so a brand-new user isn't nagged on day one.
const firstBackupGrace = Duration(days: 3);

/// The day a backup became due, or null when there's nothing to protect:
/// nudges are off, the vault is empty, or nothing changed since the last one.
DateTime? backupDueSince({required List<Memory> items, required DateTime? lastBackup, required int everyDays}) {
  if (everyDays <= 0 || items.isEmpty) return null;
  if (lastBackup == null) {
    final first = items.map((m) => m.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
    return first.add(firstBackupGrace);
  }
  final lastEdit = items.map((m) => m.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);
  if (!lastEdit.isAfter(lastBackup)) return null;
  return DateTime(lastBackup.year, lastBackup.month, lastBackup.day + everyDays);
}

/// Whether the home screen should show its backup card right now.
bool backupIsDue({
  required List<Memory> items,
  required DateTime? lastBackup,
  required int everyDays,
  required DateTime now,
  DateTime? snoozedUntil,
}) {
  final due = backupDueSince(items: items, lastBackup: lastBackup, everyDays: everyDays);
  if (due == null || now.isBefore(due)) return false;
  return snoozedUntil == null || !now.isBefore(snoozedUntil);
}

/// When the next backup notification fires: on the due day at the reminder
/// time, then every [everyDays] after that until a backup happens. One at a
/// time, so an ignored nudge never turns into a daily one.
DateTime? nextBackupNudge({
  required List<Memory> items,
  required DateTime? lastBackup,
  required int everyDays,
  required int minutes,
  required DateTime now,
}) {
  final due = backupDueSince(items: items, lastBackup: lastBackup, everyDays: everyDays);
  if (due == null) return null;
  DateTime at(DateTime d) => DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);
  var day = DateTime(due.year, due.month, due.day);
  while (!at(day).isAfter(now)) {
    day = DateTime(day.year, day.month, day.day + everyDays);
  }
  return at(day);
}
