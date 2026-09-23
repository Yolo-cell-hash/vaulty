import 'package:flutter_test/flutter_test.dart';
import 'package:vaulty/models/memory.dart';
import 'package:vaulty/services/notification_service.dart';

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  const defaults = ReminderDefaults(offsets: [30, 7, 1, 0], minutes: 9 * 60);

  Memory item(
    String id,
    DateTime date, {
    Recurrence recurrence = Recurrence.none,
    List<int>? offsets,
    int? minutes,
    bool remind = true,
    bool archived = false,
  }) => Memory(
    id: id,
    title: id,
    expiryDate: date,
    recurrence: recurrence,
    reminderOffsets: offsets,
    reminderMinutes: minutes,
    remind: remind,
    isArchived: archived,
    createdAt: today,
    updatedAt: today,
  );

  test('uses the defaults and skips reminders already in the past', () {
    final plan = planReminders([item('policy', today.add(const Duration(days: 10)))], defaults, now);
    expect(plan.map((p) => p.offsetDays), [7, 1, 0]);
    expect(plan.every((p) => p.at.hour == 9 && p.at.minute == 0), isTrue);
    expect(plan.first.at, DateTime(today.year, today.month, today.day + 3, 9));
  });

  test('per-item days and time override the defaults', () {
    final plan = planReminders(
      [
        item('visa', today.add(const Duration(days: 40)), offsets: [14, 3], minutes: 19 * 60 + 30),
      ],
      defaults,
      now,
    );
    expect(plan.map((p) => p.offsetDays), [14, 3]);
    expect(plan.every((p) => p.at.hour == 19 && p.at.minute == 30), isTrue);
  });

  test("'don't remind me', archived and undated items are left out", () {
    final date = today.add(const Duration(days: 40));
    final plan = planReminders(
      [
        item('off', date, remind: false),
        item('archived', date, archived: true),
        Memory(id: 'fact', title: 'Shoe size', createdAt: today, updatedAt: today),
      ],
      defaults,
      now,
    );
    expect(plan, isEmpty);
  });

  test('repeating dates plan the next two occurrences, soonest first', () {
    final plan = planReminders(
      [
        item('rent', today.add(const Duration(days: 5)), recurrence: Recurrence.monthly, offsets: [1]),
      ],
      defaults,
      now,
    );
    expect(plan, hasLength(2));
    expect(plan[0].at.isBefore(plan[1].at), isTrue);
    expect(plan[1].occurrence.month, isNot(plan[0].occurrence.month));
  });

  test('keeps only the soonest reminders under the limit', () {
    final items = [for (var i = 1; i <= 30; i++) item('m$i', today.add(Duration(days: 40 + i)))];
    final plan = planReminders(items, defaults, now, limit: 10);
    expect(plan, hasLength(10));
    for (var i = 1; i < plan.length; i++) {
      expect(plan[i - 1].at.isAfter(plan[i].at), isFalse);
    }
  });
}
