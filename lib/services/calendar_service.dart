import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/memory.dart';
import 'auth_service.dart';
import 'secure_keys.dart';

/// A dated item as it appears in Vaulty's calendar: its title and day, never
/// the details inside it. Notifications follow the same rule.
class CalendarEntry {
  const CalendarEntry({required this.memoryId, required this.title, required this.date, required this.recurrence});

  factory CalendarEntry.of(Memory m) {
    final d = m.expiryDate!;
    return CalendarEntry(
      memoryId: m.id,
      title: m.isOccasion ? m.title : (m.isRecurring ? '${m.title} renews' : '${m.title} expires'),
      date: DateTime(d.year, d.month, d.day),
      recurrence: m.recurrence,
    );
  }

  final String memoryId;
  final String title;

  /// The day the user entered. Repeating items start their series here.
  final DateTime date;
  final Recurrence recurrence;

  /// Changes whenever the event needs rewriting.
  String get fingerprint => '$title|${date.year}-${date.month}-${date.day}|${recurrence.dbValue}';

  Map<String, Object?> toArgs() => {
    'title': title,
    'year': date.year,
    'month': date.month,
    'day': date.day,
    'recurrence': recurrence.dbValue,
    'notes': CalendarService.note,
  };
}

/// Every event Vaulty's calendar should hold: one per dated, active item.
List<CalendarEntry> calendarEntriesFor(List<Memory> items) => [
  for (final m in items)
    if (m.hasExpiry && !m.isArchived) CalendarEntry.of(m),
];

/// An event read from one of the phone's calendars, for importing. A
/// repeating event comes once, as its next occurrence.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.calendarName,
    required this.title,
    required this.date,
    this.recurrence = Recurrence.none,
    this.kind = CalendarKind.regular,
  });

  factory CalendarEvent.fromMap(Map<Object?, Object?> m) {
    final day = DateTime.parse(m['date']! as String);
    return CalendarEvent(
      id: m['id']! as String,
      calendarName: (m['calendar'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      date: DateTime(day.year, day.month, day.day),
      recurrence: Recurrence.fromDb(m['recurrence'] as String?),
      kind: CalendarKind.values.asNameMap()[m['kind']] ?? CalendarKind.regular,
    );
  }

  final String id;
  final String calendarName;
  final String title;
  final DateTime date;
  final Recurrence recurrence;
  final CalendarKind kind;

  /// The phone's contact birthdays, which repeat yearly whatever their rule says.
  bool get fromBirthdayCalendar => kind == CalendarKind.birthdays || calendarName.toLowerCase().contains('birthday');

  /// Public holidays and other calendars someone else publishes.
  bool get fromSubscribedCalendar => kind == CalendarKind.subscribed || calendarName.toLowerCase().contains('holiday');
}

/// What sort of calendar an event came from, as the native side reports it.
enum CalendarKind { regular, birthdays, subscribed }

/// Where Vaulty's calendar lives: on the phone only, or in an account that
/// syncs (iCloud, Google, Exchange).
class CalendarHome {
  const CalendarHome({required this.local, required this.name});

  final bool local;
  final String name;
}

/// The phone's calendars, through the native bridge (`CalendarBridge` in
/// MainActivity.kt's package and in ios/Runner). Vaulty only reads calendars
/// when importing, and only writes to its own "Vaulty" calendar.
abstract final class CalendarService {
  static const _channel = MethodChannel('vaulty/calendar');

  /// Which event holds which memory, and what was last written to it.
  static const _mapKey = 'calendar_events';

  static const note = 'Added by Vaulty. The details stay in the app.';

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  static Future<bool> hasAccess() async => supported && (await _channel.invokeMethod<bool>('hasAccess') ?? false);

  /// Shows the system prompt the first time; after a refusal only Settings
  /// can grant it (see [openSettings]).
  static Future<bool> requestAccess() async {
    if (!supported) return false;
    return AuthService.guardExternal(() async => await _channel.invokeMethod<bool>('requestAccess') ?? false);
  }

  static Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  static Future<CalendarHome> home() async {
    final m = await _channel.invokeMapMethod<String, Object?>('home') ?? const {};
    return CalendarHome(local: m['local'] != false, name: (m['name'] as String?) ?? 'this phone');
  }

  /// Events between [from] and [to] in every calendar but Vaulty's own.
  static Future<List<CalendarEvent>> events({required DateTime from, required DateTime to, String? exclude}) async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('events', {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
      'exclude': exclude == null || exclude.isEmpty ? null : exclude,
    });
    return [for (final m in list ?? const <Map<Object?, Object?>>[]) CalendarEvent.fromMap(m)];
  }

  static Future<void> _queue = Future.value();

  /// Brings Vaulty's calendar in line with [items]: new dated items get an
  /// event, changed ones are rewritten and removed ones deleted. Unchanged
  /// items cost nothing. Makes the calendar first if it's missing, so turning
  /// sync on, or deleting the calendar in the Calendar app, both just work.
  /// Returns the calendar's id. Runs one at a time.
  static Future<String> sync(List<Memory> items, {required String calendarId}) {
    final run = _queue.then((_) => _sync(items, calendarId));
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  static Future<String> _sync(List<Memory> items, String calendarId) async {
    final made = await _channel.invokeMapMethod<String, Object?>('ensureCalendar', {
      'id': calendarId.isEmpty ? null : calendarId,
    });
    final id = made?['id'] as String?;
    if (id == null) throw StateError('No calendar to write to');
    // A new (or emptied) calendar has none of the events we remember.
    final map = made?['fresh'] == true || id != calendarId ? <String, (String, String)>{} : await _loadMap();

    final wanted = {for (final e in calendarEntriesFor(items)) e.memoryId: e};
    for (final memoryId in map.keys.where((k) => !wanted.containsKey(k)).toList()) {
      await _channel.invokeMethod<void>('deleteEvent', {'id': map.remove(memoryId)!.$1});
    }
    for (final e in wanted.values) {
      final known = map[e.memoryId];
      if (known != null && known.$2 == e.fingerprint) continue;
      final eventId = await _channel.invokeMethod<String>('upsertEvent', {
        'calendarId': id,
        'eventId': known?.$1,
        ...e.toArgs(),
      });
      if (eventId != null) map[e.memoryId] = (eventId, e.fingerprint);
    }
    await _saveMap(map);
    return id;
  }

  /// Deletes Vaulty's calendar and everything in it.
  static Future<void> removeCalendar(String calendarId) async {
    await _queue;
    if (supported) {
      await _channel.invokeMethod<void>('removeCalendar', {'id': calendarId.isEmpty ? null : calendarId});
    }
    await SecureKeys.write(_mapKey, null);
  }

  static Future<Map<String, (String, String)>> _loadMap() async {
    final raw = await SecureKeys.read(_mapKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value is List && value.length == 2) key: (value[0] as String, value[1] as String),
      };
    } on FormatException {
      return {};
    }
  }

  static Future<void> _saveMap(Map<String, (String, String)> map) => SecureKeys.write(
    _mapKey,
    jsonEncode({
      for (final MapEntry(:key, :value) in map.entries) key: [value.$1, value.$2],
    }),
  );
}
