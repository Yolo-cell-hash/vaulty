import 'package:flutter_test/flutter_test.dart';
import 'package:vaulty/services/review_service.dart';
import 'package:vaulty/services/update_service.dart';

/// The store-facing rules: when to offer an update, and when to ask for a
/// rating. The store calls themselves need a device with Play or the App Store.
void main() {
  final now = DateTime(2026, 10, 14, 12);

  group('isNewerVersion', () {
    test('compares numerically, part by part', () {
      expect(isNewerVersion('1.10.0', '1.9.2'), isTrue);
      expect(isNewerVersion('2.0', '1.99.99'), isTrue);
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    });

    test('missing parts are zero, and equal versions are not newer', () {
      expect(isNewerVersion('1.2', '1.2.0'), isFalse);
      expect(isNewerVersion('1.2.0', '1.2'), isFalse);
      expect(isNewerVersion('1.2.1', '1.2'), isTrue);
    });

    test('ignores build numbers and junk', () {
      expect(isNewerVersion('1.0.0+9', '1.0.0+1'), isFalse);
      expect(isNewerVersion('1.1.0-beta', '1.0.0'), isTrue);
      expect(isNewerVersion('', '1.0.0'), isFalse);
    });
  });

  group('update checks', () {
    test('run about once a day', () {
      expect(UpdateService.checkDue(null, now), isTrue);
      expect(UpdateService.checkDue(now.subtract(const Duration(hours: 3)), now), isFalse);
      expect(UpdateService.checkDue(now.subtract(const Duration(hours: 21)), now), isTrue);
    });

    test('"Later" holds that version back for a week, but not the next one', () {
      final yesterday = now.subtract(const Duration(days: 1));
      expect(UpdateService.shouldOffer('1.2.0', skippedVersion: '1.2.0', skippedAt: yesterday, now: now), isFalse);
      expect(UpdateService.shouldOffer('1.3.0', skippedVersion: '1.2.0', skippedAt: yesterday, now: now), isTrue);
      expect(
        UpdateService.shouldOffer(
          '1.2.0',
          skippedVersion: '1.2.0',
          skippedAt: now.subtract(const Duration(days: 7)),
          now: now,
        ),
        isTrue,
      );
      expect(UpdateService.shouldOffer('1.2.0', skippedVersion: '', now: now), isTrue);
    });

    test('reads Apple\'s lookup', () {
      final r = StoreRelease.fromLookup({
        'version': '1.4.0',
        'trackViewUrl': 'https://apps.apple.com/app/vaulty/id123456789',
        'trackId': 123456789,
        'releaseNotes': ' Faster search. ',
        'minimumOsVersion': '15.5',
      });
      expect(r.version, '1.4.0');
      expect(r.storeId, '123456789');
      expect(r.notes, 'Faster search.');
      expect(r.url.host, 'apps.apple.com');
    });
  });

  group('review prompt', () {
    final firstOpened = now.subtract(const Duration(days: 10));

    bool ask({DateTime? first, DateTime? last, int memories = 8}) =>
        ReviewService.shouldAsk(firstOpened: first, lastAsked: last, memories: memories, now: now);

    test('waits for a few days and a handful of memories', () {
      expect(ask(first: firstOpened), isTrue);
      expect(ask(first: null), isFalse);
      expect(ask(first: now.subtract(const Duration(days: 2))), isFalse);
      expect(ask(first: firstOpened, memories: 4), isFalse);
    });

    test('asks at most every four months', () {
      expect(ask(first: firstOpened, last: now.subtract(const Duration(days: 30))), isFalse);
      expect(ask(first: firstOpened, last: now.subtract(const Duration(days: 120))), isTrue);
    });
  });
}
