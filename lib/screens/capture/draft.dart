import 'dart:ui';

import 'package:uuid/uuid.dart';

import '../../models/memory.dart';
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
