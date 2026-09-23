import 'package:flutter_test/flutter_test.dart';
import 'package:vaulty/models/memory.dart';
import 'package:vaulty/services/smart_parser.dart';

void main() {
  group('occurrenceOnOrAfter', () {
    final today = DateTime(2026, 9, 23);

    test('yearly rolls to next year once the day has passed', () {
      expect(occurrenceOnOrAfter(DateTime(2026, 9, 24), Recurrence.yearly, today), DateTime(2026, 9, 24));
      expect(occurrenceOnOrAfter(DateTime(2026, 9, 23), Recurrence.yearly, today), DateTime(2026, 9, 23));
      expect(occurrenceOnOrAfter(DateTime(2026, 9, 22), Recurrence.yearly, today), DateTime(2027, 9, 22));
      expect(occurrenceOnOrAfter(DateTime(1998, 5, 12), Recurrence.yearly, today), DateTime(2027, 5, 12));
    });

    test('leap-day birthdays land on Feb 28 in normal years', () {
      expect(occurrenceOnOrAfter(DateTime(2000, 2, 29), Recurrence.yearly, today), DateTime(2027, 2, 28));
      expect(
        occurrenceOnOrAfter(DateTime(2000, 2, 29), Recurrence.yearly, DateTime(2027, 3, 1)),
        DateTime(2028, 2, 29),
      );
    });

    test('monthly clamps to short months', () {
      expect(occurrenceOnOrAfter(DateTime(2026, 1, 5), Recurrence.monthly, today), DateTime(2026, 10, 5));
      expect(occurrenceOnOrAfter(DateTime(2026, 1, 31), Recurrence.monthly, today), DateTime(2026, 9, 30));
      expect(
        occurrenceOnOrAfter(DateTime(2026, 1, 31), Recurrence.monthly, DateTime(2027, 2, 2)),
        DateTime(2027, 2, 28),
      );
    });

    test('future anchors are returned as-is; one-offs never move', () {
      expect(occurrenceOnOrAfter(DateTime(2027, 1, 1), Recurrence.monthly, today), DateTime(2027, 1, 1));
      expect(occurrenceOnOrAfter(DateTime(2020, 1, 1), Recurrence.none, today), DateTime(2020, 1, 1));
    });
  });

  group('Memory with recurrence', () {
    Memory m(DateTime date, Recurrence r, {String title = 'Joe Birthday'}) => Memory(
      id: 'x',
      title: title,
      expiryDate: date,
      recurrence: r,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('a passed birthday never shows as expired', () {
      final now = DateTime.now();
      final yesterday = DateTime(now.year - 30, now.month, now.day - 1);
      final bday = m(yesterday, Recurrence.yearly);
      expect(bday.daysLeft, greaterThan(300));
      expect(bday.urgency, isNot(Urgency.expired));
      expect(bday.isOccasion, isTrue);
      expect(bday.milestone, startsWith('turns '));
      expect(bday.countdownText, startsWith('In '));
    });

    test('upcomingDates gives consecutive cycles', () {
      final now = DateTime.now();
      final start = DateTime(now.year - 1, now.month, now.day);
      final dates = m(start, Recurrence.yearly).upcomingDates(2);
      expect(dates, [DateTime(now.year, now.month, now.day), DateTime(now.year + 1, now.month, now.day)]);
      expect(m(start, Recurrence.none).upcomingDates(2), [start]);
    });
  });

  group('parser cadence', () {
    final parser = SmartParser(now: DateTime(2026, 9, 23));

    test('birthdays and anniversaries repeat yearly', () {
      final p = parser.parseText('Joe Birthday 24th Sept');
      expect(p.recurrence, Recurrence.yearly);
      expect(p.expiry, DateTime(2026, 9, 24));
      expect(parser.parseText('Our anniversary June 3').recurrence, Recurrence.yearly);
    });

    test('birth year is kept as the anchor', () {
      final p = parser.parseText("Mom's birthday 12 May 1968");
      expect(p.recurrence, Recurrence.yearly);
      expect(p.expiry, DateTime(1968, 5, 12));
    });

    test('monthly cues', () {
      expect(parser.parseText(r'Netflix $15.49/mo renews on the 5th').recurrence, Recurrence.monthly);
      expect(parser.parseText('Rent due every month on the 1st').recurrence, Recurrence.monthly);
    });

    test('yearly cues and plain expiries', () {
      expect(parser.parseText('Domain renews yearly on 3 Mar').recurrence, Recurrence.yearly);
      expect(parser.parseText('Passport expires 15 Mar 2031').recurrence, Recurrence.none);
      expect(parser.parseText('Meeting at 5 p.m. tomorrow').recurrence, Recurrence.none);
      expect(parser.parseText('Monthly pass, no date').recurrence, Recurrence.none);
    });

    test('subscriptions without a cadence repeat monthly, trials do not', () {
      expect(parser.parseText('Spotify renews 12 Oct').recurrence, Recurrence.monthly);
      expect(parser.parseText('Gym membership due 3 Nov').recurrence, Recurrence.monthly);
      expect(parser.parseText('Adobe renews annually on 4 Feb').recurrence, Recurrence.yearly);
      expect(parser.parseText('Disney trial ends 30 Sept').recurrence, Recurrence.none);
    });
  });
}
