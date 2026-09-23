import 'package:flutter/widgets.dart' show StringCharacters;

enum MemoryCategory {
  staticFact('STATIC_FACT', 'Fact'),
  expiryDoc('EXPIRY_DOC', 'Document'),
  subscription('SUBSCRIPTION', 'Subscription'),
  measurement('MEASUREMENT', 'Measurement'),
  other('OTHER', 'Other');

  const MemoryCategory(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static MemoryCategory fromDb(String? v) =>
      values.firstWhere((c) => c.dbValue == v, orElse: () => MemoryCategory.staticFact);
}

class MetaEntry {
  const MetaEntry({required this.id, required this.key, required this.value});

  final String id;
  final String key;
  final String value;

  MetaEntry copyWith({String? key, String? value}) =>
      MetaEntry(id: id, key: key ?? this.key, value: value ?? this.value);
}

class Attachment {
  const Attachment({required this.id, required this.filePath, required this.mimeType});

  final String id;

  /// Path of the AES-GCM encrypted blob inside the app sandbox.
  final String filePath;
  final String mimeType;
}

class Reminder {
  const Reminder({
    required this.id,
    required this.memoryId,
    required this.notificationId,
    required this.scheduledFor,
    required this.offsetDays,
  });

  final String id;
  final String memoryId;
  final String notificationId;
  final DateTime scheduledFor;
  final int offsetDays;
}

enum TagKind {
  person('PERSON'),
  tag('TAG');

  const TagKind(this.dbValue);
  final String dbValue;

  static TagKind fromDb(String? v) => v == 'PERSON' ? TagKind.person : TagKind.tag;
}

/// A person ("Mom", "Joe") or a free-form tag ("car", "home") on memories.
class Tag {
  const Tag({required this.id, required this.name, required this.kind, this.emoji, this.uses = 0});

  final String id;
  final String name;
  final TagKind kind;

  /// Legacy per-tag emoji (kept for old backups; the UI uses monograms).
  final String? emoji;

  /// Number of memories using it (only filled when listing tags).
  final int uses;

  bool get isPerson => kind == TagKind.person;
  String get label => isPerson ? name : '#$name';

  /// One or two letters for a monogram avatar ("Mom" → "M", "Mary Jane" → "MJ").
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }

  bool sameAs(Tag o) => kind == o.kind && name.toLowerCase() == o.name.toLowerCase();

  Tag copyWith({String? name, String? emoji, bool clearEmoji = false}) =>
      Tag(id: id, name: name ?? this.name, kind: kind, emoji: clearEmoji ? null : (emoji ?? this.emoji), uses: uses);
}

enum Recurrence {
  none('NONE', 'Never'),
  monthly('MONTHLY', 'Monthly'),
  yearly('YEARLY', 'Yearly');

  const Recurrence(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static Recurrence fromDb(String? v) => values.firstWhere((r) => r.dbValue == v, orElse: () => Recurrence.none);

  /// Day offsets for reminders. Repeating things get fewer, closer nudges.
  List<int> get reminderOffsets => switch (this) {
    none => const [90, 30, 7, 1, 0],
    yearly => const [30, 7, 1, 0],
    monthly => const [3, 1, 0],
  };
}

/// The same calendar day in [year]/[month], clamped (Jan 31 → Feb 28).
DateTime _clampedDay(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > last ? last : day);
}

/// First occurrence of [anchor] repeating by [r] that falls on or after [from].
DateTime occurrenceOnOrAfter(DateTime anchor, Recurrence r, DateTime from) {
  final a = DateTime(anchor.year, anchor.month, anchor.day);
  final f = DateTime(from.year, from.month, from.day);
  if (r == Recurrence.none || !a.isBefore(f)) return a;
  if (r == Recurrence.yearly) {
    final thisYear = _clampedDay(f.year, a.month, a.day);
    return thisYear.isBefore(f) ? _clampedDay(f.year + 1, a.month, a.day) : thisYear;
  }
  final thisMonth = _clampedDay(f.year, f.month, a.day);
  return thisMonth.isBefore(f) ? _clampedDay(f.year, f.month + 1, a.day) : thisMonth;
}

/// App-wide reminder defaults (set in onboarding and in Settings).
class ReminderDefaults {
  const ReminderDefaults({this.offsets = standardOffsets, this.minutes = 9 * 60});

  /// Days before a one-off date. Repeating dates use their own cadence.
  final List<int> offsets;

  /// Time of day, minutes after midnight.
  final int minutes;

  static const standardOffsets = [90, 30, 7, 1, 0];

  /// The lead times people can pick from, in days.
  static const choices = [0, 1, 3, 7, 14, 30, 90];

  @override
  bool operator ==(Object other) =>
      other is ReminderDefaults && other.minutes == minutes && other.offsets.join(',') == offsets.join(',');

  @override
  int get hashCode => Object.hash(minutes, offsets.join(','));
}

/// "on the day", "1 day", "1 week"… for a reminder offset.
String offsetLabel(int days) => switch (days) {
  0 => 'On the day',
  1 => '1 day before',
  7 => '1 week before',
  14 => '2 weeks before',
  30 => '1 month before',
  90 => '3 months before',
  _ => '$days days before',
};

String offsetShort(int days) => switch (days) {
  0 => 'on the day',
  1 => '1 day',
  7 => '1 week',
  14 => '2 weeks',
  30 => '1 month',
  90 => '3 months',
  _ => '$days days',
};

String timeLabel(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

final _occasionRe = RegExp(r"\b(birthday|bday|b'day|anniversary)\b", caseSensitive: false);
final _birthdayRe = RegExp(r"\b(birthday|bday|b'day)\b", caseSensitive: false);

class Memory {
  const Memory({
    required this.id,
    required this.title,
    this.rawContent = '',
    this.category = MemoryCategory.staticFact,
    this.isSensitive = false,
    this.expiryDate,
    this.recurrence = Recurrence.none,
    this.reminderOffsets,
    this.reminderMinutes,
    this.remind = true,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
    this.metadata = const [],
    this.attachments = const [],
    this.tags = const [],
  });

  final String id;
  final String title;
  final String rawContent;
  final MemoryCategory category;
  final bool isSensitive;

  /// The date the user entered. For repeating items this is the anchor (e.g.
  /// a birthday, possibly in a past year); see [nextDate] for the countdown.
  final DateTime? expiryDate;
  final Recurrence recurrence;

  /// Custom lead times in days; null means "use the defaults".
  final List<int>? reminderOffsets;

  /// Custom time of day (minutes after midnight); null means the default.
  final int? reminderMinutes;

  /// False mutes every reminder for this item.
  final bool remind;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MetaEntry> metadata;
  final List<Attachment> attachments;
  final List<Tag> tags;

  List<Tag> get people => tags.where((t) => t.isPerson).toList();
  List<Tag> get plainTags => tags.where((t) => !t.isPerson).toList();

  bool get hasExpiry => expiryDate != null;
  bool get isRecurring => hasExpiry && recurrence != Recurrence.none;

  /// Birthdays and anniversaries get party copy instead of "expires".
  bool get isOccasion => _occasionRe.hasMatch(title) || _occasionRe.hasMatch(rawContent);

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// The date to count down to: the expiry itself, or the next repeat.
  DateTime? get nextDate {
    final e = expiryDate;
    if (e == null) return null;
    return occurrenceOnOrAfter(e, recurrence, _today);
  }

  /// The next [count] occurrences from today (just one for one-off dates).
  List<DateTime> upcomingDates(int count) {
    final e = expiryDate;
    if (e == null) return const [];
    if (!isRecurring) return [DateTime(e.year, e.month, e.day)];
    final out = <DateTime>[];
    var from = _today;
    while (out.length < count) {
      final d = occurrenceOnOrAfter(e, recurrence, from);
      out.add(d);
      from = DateTime(d.year, d.month, d.day + 1);
    }
    return out;
  }

  /// The lead times that actually apply, given the app defaults.
  List<int> effectiveOffsets(ReminderDefaults d) {
    if (!remind || !hasExpiry) return const [];
    final list = reminderOffsets ?? (isRecurring ? recurrence.reminderOffsets : d.offsets);
    return (list.toSet().toList()..sort((a, b) => b.compareTo(a)));
  }

  int effectiveMinutes(ReminderDefaults d) => reminderMinutes ?? d.minutes;

  /// "1 week, 1 day & on the day · 09:00", or "Reminders off".
  String reminderSummary(ReminderDefaults d) {
    if (!remind) return 'Reminders off';
    final list = effectiveOffsets(d);
    if (list.isEmpty) return 'No reminders';
    final parts = list.map(offsetShort).toList();
    final joined = parts.length == 1 ? parts.first : '${parts.sublist(0, parts.length - 1).join(', ')} & ${parts.last}';
    return '${isRecurring ? '${recurrence.label} · ' : ''}$joined · ${timeLabel(effectiveMinutes(d))}';
  }

  /// Whole days until [nextDate], relative to the local calendar day.
  int? get daysLeft => nextDate?.difference(_today).inDays;

  Urgency? get urgency {
    final d = daysLeft;
    return d == null ? null : urgencyFor(d, recurring: isRecurring);
  }

  /// "turns 28" / "8 years" when a yearly date has a real starting year.
  String? get milestone {
    final e = expiryDate, next = nextDate;
    if (recurrence != Recurrence.yearly || e == null || next == null) return null;
    final years = next.year - e.year;
    if (years <= 0 || years > 130) return null;
    return _birthdayRe.hasMatch('$title $rawContent') ? 'turns $years' : '$years ${years == 1 ? 'year' : 'years'}';
  }

  /// The single most useful value to show on a micro-card.
  MetaEntry? get headline => metadata.isEmpty ? null : metadata.first;

  Memory copyWith({
    String? title,
    String? rawContent,
    MemoryCategory? category,
    bool? isSensitive,
    DateTime? expiryDate,
    bool clearExpiry = false,
    Recurrence? recurrence,
    List<int>? reminderOffsets,
    bool clearReminderOffsets = false,
    int? reminderMinutes,
    bool clearReminderMinutes = false,
    bool? remind,
    bool? isArchived,
    DateTime? updatedAt,
    List<MetaEntry>? metadata,
    List<Attachment>? attachments,
    List<Tag>? tags,
  }) => Memory(
    id: id,
    title: title ?? this.title,
    rawContent: rawContent ?? this.rawContent,
    category: category ?? this.category,
    isSensitive: isSensitive ?? this.isSensitive,
    expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
    recurrence: recurrence ?? this.recurrence,
    reminderOffsets: clearReminderOffsets ? null : (reminderOffsets ?? this.reminderOffsets),
    reminderMinutes: clearReminderMinutes ? null : (reminderMinutes ?? this.reminderMinutes),
    remind: remind ?? this.remind,
    isArchived: isArchived ?? this.isArchived,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    metadata: metadata ?? this.metadata,
    attachments: attachments ?? this.attachments,
    tags: tags ?? this.tags,
  );
}

/// Urgency buckets used for colouring countdowns across the app.
enum Urgency { expired, urgent, soon, chill }

/// Repeating dates never expire and only turn red in the last few days.
Urgency urgencyFor(int daysLeft, {bool recurring = false}) {
  if (daysLeft < 0) return Urgency.expired;
  if (daysLeft <= (recurring ? 3 : 14)) return Urgency.urgent;
  if (daysLeft <= (recurring ? 21 : 60)) return Urgency.soon;
  return Urgency.chill;
}

String countdownLabel(int days, {bool recurring = false}) {
  if (recurring) {
    if (days == 0) return 'Today!';
    if (days == 1) return 'Tomorrow!';
    return 'In $days days';
  }
  if (days < -1) return 'Expired ${-days}d ago';
  if (days == -1) return 'Expired yesterday';
  if (days == 0) return 'Expires today!';
  if (days == 1) return 'Tomorrow!';
  return '$days days left';
}

extension MemoryCountdown on Memory {
  /// e.g. "In 5 days", "Tomorrow!", "12 days left", "Expired 3d ago".
  String get countdownText => daysLeft == null ? '' : countdownLabel(daysLeft!, recurring: isRecurring);

  /// Words under a big countdown number.
  String get countdownUnit {
    final d = daysLeft ?? 0;
    if (d < 0) return 'days ago';
    if (isRecurring) return d == 1 ? 'day to go' : 'days to go';
    return d == 1 ? 'day left' : 'days left';
  }

  /// Screen-reader version of [countdownText]: no abbreviations or "!".
  String get spokenCountdown {
    final d = daysLeft;
    if (d == null) return '';
    if (d < -1) return 'expired ${-d} days ago';
    if (d == -1) return 'expired yesterday';
    final verb = isOccasion ? '' : (isRecurring ? 'renews ' : 'expires ');
    if (d == 0) return '${verb}today';
    if (d == 1) return '${verb}tomorrow';
    return '${verb}in $d days';
  }

  /// e.g. "Expires 5 Oct 2026", "Renews 5 Oct 2026" or "24 Sep 2026" (birthdays).
  String dateCaption(String Function(DateTime) format) {
    final d = nextDate;
    if (d == null) return '';
    if (isOccasion) return format(d);
    if (isRecurring) return 'Renews ${format(d)}';
    return '${(daysLeft ?? 0) < 0 ? 'Expired' : 'Expires'} ${format(d)}';
  }
}
