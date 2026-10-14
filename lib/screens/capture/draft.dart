import 'dart:ui';

import 'package:uuid/uuid.dart';

import '../../models/memory.dart';
import '../../services/calendar_service.dart';
import '../../services/smart_parser.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Month-first numeric dates are only the norm in a handful of regions.
SmartParser deviceParser({List<Tag> known = const []}) {
  const monthFirst = {'US', 'PH', 'FM', 'MH', 'PW'};
  final country = PlatformDispatcher.instance.locale.countryCode ?? '';
  return SmartParser(
    dayFirst: !monthFirst.contains(country.toUpperCase()),
    knownPeople: [
      for (final t in known)
        if (t.isPerson) t.name,
    ],
  );
}

/// Reuses an existing person/tag when the name matches, else makes a new one.
Tag resolveTag(String name, TagKind kind, List<Tag> known) {
  final draft = Tag(id: newId(), name: name, kind: kind);
  return known.where((t) => t.sameAs(draft)).firstOrNull ?? draft;
}

Memory memoryFromParsed(ParsedCapture p, {List<Attachment> attachments = const [], List<Tag> known = const []}) {
  final now = DateTime.now();
  return Memory(
    id: newId(),
    title: p.title.isEmpty ? 'Untitled memory' : p.title,
    rawContent: p.rawText,
    category: p.category,
    isSensitive: p.isSensitive,
    expiryDate: p.expiry,
    recurrence: p.recurrence,
    createdAt: now,
    updatedAt: now,
    metadata: [for (final (k, v) in p.fields) MetaEntry(id: newId(), key: k, value: v)],
    attachments: attachments,
    tags: [
      for (final name in p.people) resolveTag(name, TagKind.person, known),
      for (final name in p.tags) resolveTag(name, TagKind.tag, known),
    ],
  );
}

Memory blankMemory({
  String title = '',
  MemoryCategory category = MemoryCategory.staticFact,
  List<String> keys = const [],
  bool sensitive = false,
  Recurrence recurrence = Recurrence.none,
}) {
  final now = DateTime.now();
  return Memory(
    id: newId(),
    title: title,
    category: category,
    isSensitive: sensitive,
    recurrence: recurrence,
    createdAt: now,
    updatedAt: now,
    metadata: [for (final k in keys) MetaEntry(id: newId(), key: k, value: '')],
  );
}

/// "Joe Smith’s birthday" → "Joe Smith": the whole name, not just the surname.
final _ownerRe = RegExp(r"^(.{2,40}?)['’]s\s+(?:birthday|bday|b'day|anniversary)$", caseSensitive: false);
final _occasionWordRe = RegExp(r"\b(birthday|bday|b'day|anniversary)\b", caseSensitive: false);

/// iOS titles each birthday with that year's age: "Joe’s 32nd Birthday".
final _ordinalRe = RegExp(
  r"\s+(\d{1,3})(?:st|nd|rd|th)(?=\s+(?:birthday|bday|b'day|anniversary)\b)",
  caseSensitive: false,
);

/// A memory for a calendar event: the event's own title and day, sorted and
/// linked to people the way a typed capture would be.
Memory memoryFromEvent(CalendarEvent e, {List<Tag> known = const []}) {
  var title = e.title.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (title.isEmpty) title = 'Untitled event';
  // "32nd" would be wrong next year; it does tell us the year it started,
  // which gives "turns 33" next time.
  var date = e.date;
  final ordinal = _ordinalRe.firstMatch(title);
  if (ordinal != null) {
    final years = int.parse(ordinal[1]!);
    if (years > 0 && years < 130) date = DateTime(date.year - years, date.month, date.day);
    title = title.replaceRange(ordinal.start, ordinal.end, '');
  }
  // Contact-birthday calendars often title the event with just the name.
  if (e.fromBirthdayCalendar && !_occasionWordRe.hasMatch(title)) title = '$title’s birthday';
  if (title.length > 80) title = '${title.substring(0, 79).trim()}…';

  final category = SmartParser.categoryFor(title, hasDate: true);
  final recurrence = e.recurrence != Recurrence.none
      ? e.recurrence
      : (e.fromBirthdayCalendar ? Recurrence.yearly : SmartParser.recurrenceFor(title, category));
  final owner = _ownerRe.firstMatch(title)?.group(1);
  final people = owner != null ? [owner] : deviceParser(known: known).findPeople(title);
  final now = DateTime.now();
  return Memory(
    id: newId(),
    title: title,
    rawContent: title,
    category: category,
    expiryDate: date,
    recurrence: recurrence,
    createdAt: now,
    updatedAt: now,
    tags: [for (final name in people) resolveTag(name, TagKind.person, known)],
  );
}

/// Whether an event looks worth keeping, so the import list can tick it
/// up front: birthdays, yearly dates, renewals, documents and deadlines.
/// Public holidays repeat yearly too, but they're nobody's to keep track of.
bool suggestedForImport(CalendarEvent e) =>
    e.fromBirthdayCalendar ||
    (!e.fromSubscribedCalendar && (e.recurrence == Recurrence.yearly || SmartParser.soundsTrackable(e.title)));

/// Whether the vault already has [candidate]: the same title due the same day.
bool alreadyInVault(Memory candidate, List<Memory> items) {
  final title = candidate.title.toLowerCase();
  return items.any((m) => m.title.trim().toLowerCase() == title && m.nextDate == candidate.nextDate);
}
