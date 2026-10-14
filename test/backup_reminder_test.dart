import 'package:flutter_test/flutter_test.dart';
import 'package:vaulty/models/memory.dart';
import 'package:vaulty/services/backup_reminder.dart';

void main() {
  final now = DateTime(2026, 10, 14, 15, 30);
  const nine = 9 * 60;

  Memory item(String id, {required DateTime created, DateTime? updated}) =>
      Memory(id: id, title: id, createdAt: created, updatedAt: updated ?? created);

  group('backupDueSince', () {
    test('nothing is due with nudges off or an empty vault', () {
      final items = [item('a', created: DateTime(2026, 1, 1))];
      expect(backupDueSince(items: items, lastBackup: null, everyDays: 0), isNull);
      expect(backupDueSince(items: const [], lastBackup: null, everyDays: 30), isNull);
    });

    test('a vault never backed up is due a few days after its first memory', () {
      final items = [item('b', created: DateTime(2026, 10, 10)), item('a', created: DateTime(2026, 10, 1))];
      expect(backupDueSince(items: items, lastBackup: null, everyDays: 30), DateTime(2026, 10, 4));
    });

    test('nothing is due when nothing changed since the last backup', () {
      final items = [item('a', created: DateTime(2026, 9, 1))];
      expect(backupDueSince(items: items, lastBackup: DateTime(2026, 9, 2), everyDays: 7), isNull);
    });

    test('changes after a backup are due one interval after it', () {
      final items = [item('a', created: DateTime(2026, 9, 1), updated: DateTime(2026, 10, 12))];
      expect(
        backupDueSince(items: items, lastBackup: DateTime(2026, 9, 20, 18), everyDays: 30),
        DateTime(2026, 10, 20),
      );
    });
  });

  group('backupIsDue', () {
    final items = [item('a', created: DateTime(2026, 9, 1))];

    test('shows once the due day arrives', () {
      expect(backupIsDue(items: items, lastBackup: null, everyDays: 30, now: DateTime(2026, 9, 3, 23)), isFalse);
      expect(backupIsDue(items: items, lastBackup: null, everyDays: 30, now: DateTime(2026, 9, 4)), isTrue);
    });

    test('"Later" hides it until the snooze runs out', () {
      expect(
        backupIsDue(
          items: items,
          lastBackup: null,
          everyDays: 30,
          now: now,
          snoozedUntil: now.add(const Duration(days: 1)),
        ),
        isFalse,
      );
      expect(
        backupIsDue(
          items: items,
          lastBackup: null,
          everyDays: 30,
          now: now,
          snoozedUntil: now.subtract(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    });
  });

  group('nextBackupNudge', () {
    test('fires on the due day at the reminder time', () {
      final items = [item('a', created: DateTime(2026, 10, 13))];
      expect(
        nextBackupNudge(items: items, lastBackup: null, everyDays: 30, minutes: nine, now: now),
        DateTime(2026, 10, 16, 9),
      );
    });

    test('an overdue backup nudges at the next step of its interval, not every day', () {
      // Due 4 Sep; weekly steps fall on 9 Oct, then 16 Oct.
      final items = [item('a', created: DateTime(2026, 9, 1))];
      expect(
        nextBackupNudge(items: items, lastBackup: null, everyDays: 7, minutes: nine, now: now),
        DateTime(2026, 10, 16, 9),
      );
    });

    test('today still counts while the reminder time is ahead', () {
      // Due 14 Oct: 30 days after a 14 Sep backup. It's 15:30, so an evening reminder still fires today.
      final items = [item('a', created: DateTime(2026, 9, 1), updated: DateTime(2026, 10, 1))];
      expect(
        nextBackupNudge(items: items, lastBackup: DateTime(2026, 9, 14), everyDays: 30, minutes: 19 * 60, now: now),
        DateTime(2026, 10, 14, 19),
      );
      expect(
        nextBackupNudge(items: items, lastBackup: DateTime(2026, 9, 14), everyDays: 30, minutes: nine, now: now),
        DateTime(2026, 11, 13, 9),
      );
    });

    test('none when nothing needs protecting', () {
      final items = [item('a', created: DateTime(2026, 9, 1))];
      expect(
        nextBackupNudge(items: items, lastBackup: DateTime(2026, 9, 2), everyDays: 30, minutes: nine, now: now),
        isNull,
      );
      expect(nextBackupNudge(items: items, lastBackup: null, everyDays: 0, minutes: nine, now: now), isNull);
    });
  });

  test('every interval has a label', () {
    expect(backupEveryLabel(30), 'Every month');
    expect(backupEveryLabel(0), 'Off');
    expect(backupEveryLabel(45), 'Every 45 days');
  });
}
