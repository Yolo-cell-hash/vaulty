import 'package:flutter_test/flutter_test.dart';
import 'package:vaulty/models/memory.dart';
import 'package:vaulty/screens/capture/draft.dart';
import 'package:vaulty/services/calendar_service.dart';

/// What goes into Vaulty's calendar, and what comes out of the phone's. The
/// calendar reads and writes themselves are native (CalendarBridge).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  Memory item(
    String title, {
    DateTime? date,
    Recurrence recurrence = Recurrence.none,
    bool archived = false,
    MemoryCategory category = MemoryCategory.other,
  }) => Memory(
    id: title,
    title: title,
    category: category,
    expiryDate: date,
    recurrence: recurrence,
    isArchived: archived,
    createdAt: today,
    updatedAt: today,
    metadata: const [MetaEntry(id: 'm', key: 'Passport #', value: 'K1234567')],
  );

  group('Vaulty’s calendar', () {
    test('holds one event per dated, active item', () {
      final entries = calendarEntriesFor([
        item('Passport', date: DateTime(2031, 3, 15, 10, 30)),
        item('Paint colour'),
        item('Old lease', date: DateTime(2025, 1, 1), archived: true),
      ]);
      expect(entries.map((e) => e.memoryId), ['Passport']);
      expect(entries.single.date, DateTime(2031, 3, 15));
    });

    test('titles read like the notifications, and never carry details', () {
      final passport = CalendarEntry.of(item('Passport', date: DateTime(2031, 3, 15)));
      final netflix = CalendarEntry.of(item('Netflix', date: DateTime(2026, 1, 5), recurrence: Recurrence.monthly));
      final birthday = CalendarEntry.of(
        item('Joe’s birthday', date: DateTime(1998, 9, 24), recurrence: Recurrence.yearly),
      );
      expect(passport.title, 'Passport expires');
      expect(netflix.title, 'Netflix renews');
      expect(birthday.title, 'Joe’s birthday');
      expect(birthday.date, DateTime(1998, 9, 24), reason: 'a series starts on the date entered');
      for (final e in [passport, netflix, birthday]) {
        expect(e.toArgs().values.join(' '), isNot(contains('K1234567')));
      }
    });

    test('the fingerprint changes only when the event must be rewritten', () {
      final a = CalendarEntry.of(item('Passport', date: DateTime(2031, 3, 15)));
      expect(a.fingerprint, CalendarEntry.of(item('Passport', date: DateTime(2031, 3, 15, 18))).fingerprint);
      expect(a.fingerprint, isNot(CalendarEntry.of(item('Passport', date: DateTime(2031, 3, 16))).fingerprint));
      expect(
        a.fingerprint,
        isNot(
          CalendarEntry.of(item('Passport', date: DateTime(2031, 3, 15), recurrence: Recurrence.yearly)).fingerprint,
        ),
      );
    });
  });

  group('importing', () {
    CalendarEvent event(
      String title, {
      DateTime? date,
      Recurrence recurrence = Recurrence.none,
      String calendar = 'Personal',
      CalendarKind kind = CalendarKind.regular,
    }) => CalendarEvent(
      id: title,
      calendarName: calendar,
      title: title,
      date: date ?? today,
      recurrence: recurrence,
      kind: kind,
    );

    test('iOS’s "32nd Birthday" drops the age but keeps the year it implies', () {
      final next = today.add(const Duration(days: 20));
      final m = memoryFromEvent(
        event('Joe Smith’s 32nd Birthday', date: next, recurrence: Recurrence.yearly, kind: CalendarKind.birthdays),
      );
      expect(m.title, 'Joe Smith’s Birthday');
      expect(m.people.map((p) => p.name), ['Joe Smith']);
      expect(m.expiryDate, DateTime(next.year - 32, next.month, next.day));
      expect(m.nextDate, next);
      expect(m.milestone, 'turns 32');
    });

    test('public holidays are listed but never ticked, even "birthdays" of public figures', () {
      final holidays = [
        event('Republic Day', recurrence: Recurrence.yearly, calendar: 'India Holidays', kind: CalendarKind.subscribed),
        event(
          'Maharishi Valmiki’s Birthday',
          recurrence: Recurrence.yearly,
          calendar: 'India Holidays',
          kind: CalendarKind.subscribed,
        ),
        event('Christmas Day', recurrence: Recurrence.yearly, calendar: 'Holidays in United Kingdom'),
      ];
      for (final e in holidays) {
        expect(suggestedForImport(e), isFalse, reason: e.title);
      }
      expect(suggestedForImport(event('Sam’s birthday', kind: CalendarKind.birthdays)), isTrue);
    });

    test('a contact birthday keeps the whole name and repeats yearly', () {
      final m = memoryFromEvent(event('Joe Smith’s Birthday', recurrence: Recurrence.yearly, calendar: 'Birthdays'));
      expect(m.title, 'Joe Smith’s Birthday');
      expect(m.people.map((p) => p.name), ['Joe Smith']);
      expect(m.recurrence, Recurrence.yearly);
      expect(m.isOccasion, isTrue);
    });

    test('a birthday calendar that titles events with just a name still reads as a birthday', () {
      final m = memoryFromEvent(event('Priya Raman', calendar: 'Contacts’ birthdays'));
      expect(m.title, 'Priya Raman’s birthday');
      expect(m.people.map((p) => p.name), ['Priya Raman']);
      expect(m.recurrence, Recurrence.yearly);
    });

    test('other events are sorted the way a typed capture would be', () {
      final passport = memoryFromEvent(event('Passport expiry', date: DateTime(2031, 3, 15)));
      expect(passport.category, MemoryCategory.expiryDoc);
      expect(passport.recurrence, Recurrence.none);
      expect(passport.expiryDate, DateTime(2031, 3, 15));

      final gym = memoryFromEvent(event('Gym membership', recurrence: Recurrence.monthly));
      expect(gym.category, MemoryCategory.subscription);
      expect(gym.recurrence, Recurrence.monthly);
    });

    test('people already in the vault are linked, not duplicated', () {
      const mom = Tag(id: 'mom', name: 'Mom', kind: TagKind.person);
      final m = memoryFromEvent(event('Mom’s anniversary', recurrence: Recurrence.yearly), known: const [mom]);
      expect(m.people.single.id, 'mom');
    });

    test('suggests dates worth keeping, not meetings', () {
      expect(suggestedForImport(event('Car insurance renewal')), isTrue);
      expect(suggestedForImport(event('Visa appointment')), isTrue);
      expect(suggestedForImport(event('Wedding anniversary', recurrence: Recurrence.yearly)), isTrue);
      expect(suggestedForImport(event('Sam', calendar: 'Birthdays')), isTrue);
      expect(suggestedForImport(event('Team standup')), isFalse);
      expect(suggestedForImport(event('Dinner with Alex')), isFalse);
    });

    test('knows what the vault already has', () {
      final next = today.add(const Duration(days: 40));
      final existing = [item('Passport expiry', date: next)];
      expect(alreadyInVault(memoryFromEvent(event('passport expiry', date: next)), existing), isTrue);
      expect(
        alreadyInVault(memoryFromEvent(event('Passport expiry', date: next.add(const Duration(days: 1)))), existing),
        isFalse,
      );
    });

    test('reads the native bridge’s rows', () {
      final e = CalendarEvent.fromMap({
        'id': '42',
        'title': 'Lease ends',
        'date': '2027-06-30',
        'calendar': 'Home',
        'kind': 'regular',
        'recurrence': 'NONE',
      });
      expect(e.date, DateTime(2027, 6, 30));
      expect(e.recurrence, Recurrence.none);
      expect(e.fromBirthdayCalendar, isFalse);
      expect(
        CalendarEvent.fromMap({'id': '1', 'date': '2027-01-26', 'kind': 'subscribed'}).fromSubscribedCalendar,
        isTrue,
      );
      expect(CalendarEvent.fromMap({'id': '2', 'date': '2027-01-26', 'kind': 'mystery'}).kind, CalendarKind.regular);
    });
  });
}
