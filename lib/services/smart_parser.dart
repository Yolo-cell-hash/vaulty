import '../models/memory.dart';

/// Result of parsing free text or OCR output into a memory draft.
class ParsedCapture {
  const ParsedCapture({
    required this.title,
    required this.category,
    required this.fields,
    required this.rawText,
    this.expiry,
    this.isSensitive = false,
    this.people = const [],
    this.tags = const [],
    this.recurrence = Recurrence.none,
  });

  final String title;
  final MemoryCategory category;
  final DateTime? expiry;
  final List<(String, String)> fields;
  final String rawText;
  final bool isSensitive;

  /// Names of people this is about ("Mom", "Joe").
  final List<String> people;

  /// Hashtags without the '#'.
  final List<String> tags;

  /// Whether the date repeats (birthdays, monthly renewals).
  final Recurrence recurrence;

  bool get isEmpty => title.isEmpty && fields.isEmpty && expiry == null;
}

class _Span {
  _Span(this.start, this.end, {this.cut});
  final int start;
  final int end;

  /// Where the title should be cut if this entity comes first.
  final int? cut;

  bool overlaps(_Span o) => start < o.end && o.start < end;
}

class _DateHit extends _Span {
  _DateHit(super.start, super.end, this.date) : super(cut: start);
  final DateTime date;
}

class _Field extends _Span {
  _Field(super.start, super.end, this.key, this.value, {super.cut});
  final String key;
  final String value;
}

/// Offline regex + heuristics parser. No network, no model downloads.
class SmartParser {
  SmartParser({DateTime? now, this.dayFirst = true, this.knownPeople = const []}) : now = now ?? DateTime.now();

  final DateTime now;

  /// People already in the vault; any mention of them links the memory.
  final List<String> knownPeople;

  /// Whether ambiguous numeric dates like 03/04/2027 are read as day/month.
  final bool dayFirst;

  DateTime get _today => DateTime(now.year, now.month, now.day);

  static const _monthRe =
      r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

  static final _expiryKw = RegExp(
    r'\b(exp(?:iry|ires?|iring|iration|\.)?|valid\s+(?:until|till|thru|through|upto|up\s+to|to)|due(?:\s+(?:on|by|date))?|renews?(?:\s+on)?|renewal(?:\s+date)?|ends?\s+on|deadline|use\s+by|best\s+before|until|till)\b',
    caseSensitive: false,
  );

  static final _subscriptionKw = RegExp(
    r'\b(subscription|subscribed?|renews?|renewal|monthly|yearly|annual(?:ly)?|per\s+month|membership|billing|billed|netflix|spotify|prime|youtube|disney|hulu|icloud|google\s+one|gym|chatgpt|apple\s+music|hotstar|zee5|sonyliv|adobe|notion|dropbox|patreon|xbox|playstation|nintendo)\b|/\s*(?:mo|month|yr|year)\b',
    caseSensitive: false,
  );

  static final _measureKw = RegExp(
    r'\b(size|sizes|cm|mm|inch(?:es)?|ft|feet|kg|lbs?|waist|inseam|chest|height|width|length|depth|dimensions?|measurements?|bust|hips|collar|sleeve)\b',
    caseSensitive: false,
  );

  static final _docKw = RegExp(
    r"\b(passport|driv(?:ing|er'?s)\s+licen[cs]e|licen[cs]e|visa|insurance|policy|id\s+card|aadhaar|pan\s+card|registration|warranty|guarantee|permit|certificate|lease|contract|vaccine|prescription|puc|rc\s+book|voter\s+id|residence\s+permit|green\s+card|credit\s+card|debit\s+card)\b",
    caseSensitive: false,
  );

  static final _yearlyOccasionKw = RegExp(r"\b(birthday|bday|b'day|anniversary)\b", caseSensitive: false);

  static final _yearlyKw = RegExp(
    r'\b(every\s+year|each\s+year|yearly|annual(?:ly)?|per\s+(?:year|annum))\b|/\s*(?:yr|year)\b',
    caseSensitive: false,
  );

  static final _monthlyKw = RegExp(
    r'\b(every\s+month|each\s+month|monthly|per\s+month)\b|/\s*(?:mo|month)\b|\bon\s+the\s+\d{1,2}(?:st|nd|rd|th)\b',
    caseSensitive: false,
  );

  /// Birthdays/anniversaries repeat yearly; explicit cadences win otherwise.
  static Recurrence detectRecurrence(String text) {
    if (_yearlyOccasionKw.hasMatch(text)) return Recurrence.yearly;
    if (_monthlyKw.hasMatch(text)) return Recurrence.monthly;
    if (_yearlyKw.hasMatch(text)) return Recurrence.yearly;
    return Recurrence.none;
  }

  static final _oneOffKw = RegExp(
    r'\b(trial|cancel(?:led|ed)?|ends?|ending|expires?|expiry|last\s+day)\b',
    caseSensitive: false,
  );

  /// Like [detectRecurrence], but a subscription with no stated cadence is
  /// assumed monthly, unless it reads like a one-off (a trial ending).
  static Recurrence recurrenceFor(String text, MemoryCategory category) {
    final r = detectRecurrence(text);
    if (r != Recurrence.none || category != MemoryCategory.subscription) return r;
    return _oneOffKw.hasMatch(text) ? Recurrence.none : Recurrence.monthly;
  }

  static final _sensitiveKw = RegExp(
    r'\b(password|passcode|pin|cvv|ssn|social\s+security|passport|aadhaar|pan|bank|account|acct|iban|routing|ifsc|seed|recovery|secret|wi-?fi|card\s+(?:no|number|#))\b',
    caseSensitive: false,
  );

  // ------------------------------------------------------------------ API --

  ParsedCapture parseText(String input) {
    final tags = findHashtags(input);
    final text = input.replaceAll(_hashtagRe, ' ').replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
    if (text.isEmpty) {
      return const ParsedCapture(title: '', category: MemoryCategory.staticFact, fields: [], rawText: '');
    }

    final dates = _findDates(text);
    final fields = _findFields(text, dates);
    final kwSpans = _expiryKw.allMatches(text).map((m) => _Span(m.start, m.end, cut: m.start)).toList();

    final expiry = _pickExpiry(text, dates, preferKeywordOnly: false);

    // Title: everything before the first recognised entity.
    final cuts = <int>[
      ...dates.map((d) => d.cut!),
      ...fields.map((f) => f.cut ?? f.start),
      ...kwSpans.map((k) => k.cut!),
    ];
    final firstCut = cuts.isEmpty ? text.length : cuts.reduce((a, b) => a < b ? a : b);
    var title = _cleanTitle(text.substring(0, firstCut));
    if (_meaningfulWords(title) == 0) {
      final colonKey = fields.where((f) => f.cut == f.start).map((f) => f.key).firstOrNull;
      title = colonKey ?? _fallbackTitle(text, [...dates, ...fields, ...kwSpans]);
    }

    final category = _inferCategory(text, expiry != null);
    return ParsedCapture(
      title: _titleCase(title),
      category: category,
      expiry: expiry,
      fields: fields.map((f) => (f.key, f.value)).toList(),
      rawText: input.trim(),
      isSensitive: _sensitiveKw.hasMatch(text),
      people: findPeople(text),
      tags: tags,
      recurrence: expiry == null ? Recurrence.none : recurrenceFor(text, category),
    );
  }

  ParsedCapture parseOcr(String ocrText) {
    final text = ocrText.replaceAll('\r', '').trim();
    final dates = _findDates(text);
    final fields = <_Field>[];
    var offset = 0;
    for (final line in text.split('\n')) {
      final lineDates = dates
          .where((d) => d.start >= offset && d.end <= offset + line.length)
          .map((d) => _DateHit(d.start - offset, d.end - offset, d.date))
          .toList();
      for (final f in _findFields(line, lineDates, ocr: true)) {
        if (fields.length >= 10) break;
        if (fields.any((e) => e.value == f.value)) continue;
        fields.add(f);
      }
      offset += line.length + 1;
    }

    final expiry = _pickExpiry(text, dates, preferKeywordOnly: true);
    final docMatch = _docKw.firstMatch(text);
    final title = docMatch != null ? _titleCase(docMatch.group(0)!.toLowerCase()) : _ocrTitle(text);

    final category = _inferCategory(text, expiry != null);
    return ParsedCapture(
      title: title,
      category: category,
      expiry: expiry,
      fields: fields.map((f) => (f.key, f.value)).toList(),
      rawText: text,
      isSensitive: _sensitiveKw.hasMatch(text),
      people: findPeople(text),
      tags: findHashtags(text),
      recurrence: expiry == null ? Recurrence.none : recurrenceFor(text, category),
    );
  }

  // --------------------------------------------------------- people & tags --

  static final _hashtagRe = RegExp(r'(?<![\w#&])#([A-Za-z][A-Za-z0-9_-]{1,24})\b');

  static const _relations = [
    'mom',
    'mum',
    'mother',
    'mommy',
    'mummy',
    'amma',
    'dad',
    'father',
    'daddy',
    'papa',
    'appa',
    'wife',
    'husband',
    'hubby',
    'partner',
    'boyfriend',
    'girlfriend',
    'fiance',
    'fiancee',
    'sister',
    'sis',
    'brother',
    'bro',
    'son',
    'daughter',
    'niece',
    'nephew',
    'cousin',
    'grandma',
    'granny',
    'nana',
    'grandpa',
    'grandad',
    'baby',
    'uncle',
    'aunt',
    'aunty',
    'auntie',
    'boss',
    'roommate',
    'bestie',
  ];

  /// Capitalised words that look like names but aren't.
  static const _notNames = {
    'i',
    'it',
    'its',
    'this',
    'that',
    'today',
    'tomorrow',
    'yesterday',
    'everyone',
    'nobody',
    'someone',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
    'car',
    'home',
    'house',
    'next',
    'last',
    'new',
    'old',
    'my',
    'our',
    'the',
    'what',
    'where',
    'when',
    'policy',
    'passport',
    'netflix',
    'spotify',
    'amazon',
    'apple',
    'google',
    'gym',
    'wifi',
    'wi-fi',
  };

  static List<String> findHashtags(String text) {
    final hex = RegExp(r'^[0-9a-fA-F]{6}$');
    final out = <String>[];
    for (final m in _hashtagRe.allMatches(text)) {
      final tag = m[1]!.toLowerCase();
      if (hex.hasMatch(tag) || out.contains(tag)) continue;
      out.add(tag);
    }
    return out;
  }

  List<String> findPeople(String text) {
    final found = <String>[];
    void add(String name) {
      final clean = name.trim();
      if (clean.length < 2 || _notNames.contains(clean.toLowerCase())) return;
      final display = clean[0].toUpperCase() + clean.substring(1);
      if (!found.any((f) => f.toLowerCase() == display.toLowerCase())) found.add(display);
    }

    // People already in the vault, matched as whole words.
    for (final name in knownPeople) {
      if (RegExp(r'(?<![\w])' + RegExp.escape(name) + r'(?![\w])', caseSensitive: false).hasMatch(text)) {
        add(name);
      }
    }
    // Relationship words: "Mom's shoe size", "dad waist 34".
    final relations = RegExp(r"\b(" + _relations.join('|') + r")(?:['’]s)?\b", caseSensitive: false);
    for (final m in relations.allMatches(text)) {
      add(m[1]!.toLowerCase());
    }
    // Possessive names: "Priya's ring size".
    for (final m in RegExp(r"\b([A-Z][a-z]{1,20})['’]s\b").allMatches(text)) {
      add(m[1]!);
    }
    // Occasions: "Joe birthday 24th Sept", "Sam anniversary".
    final occasion = RegExp(r"\b([A-Z][a-z]{1,20})(?:['’]s)?\s+(?:[Bb]irthday|[Bb]day|[Bb]'day|[Aa]nniversary)\b");
    for (final m in occasion.allMatches(text)) {
      add(m[1]!);
    }
    return found;
  }

  // ---------------------------------------------------------------- dates --

  List<_DateHit> _findDates(String text) {
    final hits = <_DateHit>[];
    void add(int s, int e, DateTime? d) {
      if (d == null) return;
      final hit = _DateHit(s, e, d);
      if (hits.any((h) => h.overlaps(hit))) return;
      hits.add(hit);
    }

    // 2027-03-15
    for (final m in RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b').allMatches(text)) {
      add(m.start, m.end, _date(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
    }
    // 15/03/2027, 03-15-27
    for (final m in RegExp(r'\b(\d{1,2})[/.-](\d{1,2})[/.-](\d{4}|\d{2})\b').allMatches(text)) {
      final a = int.parse(m[1]!), b = int.parse(m[2]!);
      var y = int.parse(m[3]!);
      if (y < 100) y += 2000;
      final dayFirstHere = a > 12 ? true : (b > 12 ? false : dayFirst);
      add(m.start, m.end, dayFirstHere ? _date(y, b, a) : _date(y, a, b));
    }
    // 12 Nov 2026 / 12th of November
    for (final m in RegExp(
      '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?$_monthRe\\b\\.?,?(?:\\s*(\\d{4}))?',
      caseSensitive: false,
    ).allMatches(text)) {
      final mo = _month(m[2]!);
      final y = m[3] != null ? int.parse(m[3]!) : null;
      add(m.start, m.end, _withYear(y, mo, int.parse(m[1]!)));
    }
    // Nov 12, 2026 / November 12th
    for (final m in RegExp(
      '\\b$_monthRe\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:,?\\s*(\\d{4}))?',
      caseSensitive: false,
    ).allMatches(text)) {
      final mo = _month(m[1]!);
      final y = m[3] != null ? int.parse(m[3]!) : null;
      add(m.start, m.end, _withYear(y, mo, int.parse(m[2]!)));
    }
    // March 2027 → end of that month
    for (final m in RegExp('\\b$_monthRe\\.?,?\\s+(\\d{4})\\b', caseSensitive: false).allMatches(text)) {
      final mo = _month(m[1]!);
      final y = int.parse(m[2]!);
      add(m.start, m.end, DateTime(y, mo + 1, 0));
    }
    // Card-style 10/28 (MM/YY), only right after an expiry keyword.
    for (final m in RegExp(r'\b(0?[1-9]|1[0-2])\s*/\s*(\d{2})\b').allMatches(text)) {
      final before = text.substring((m.start - 16).clamp(0, m.start), m.start);
      if (!_expiryKw.hasMatch(before)) continue;
      add(m.start, m.end, DateTime(2000 + int.parse(m[2]!), int.parse(m[1]!) + 1, 0));
    }
    // today / tomorrow
    for (final m in RegExp(r'\b(today|tonight|tomorrow)\b', caseSensitive: false).allMatches(text)) {
      final isTomorrow = m[1]!.toLowerCase() == 'tomorrow';
      add(m.start, m.end, _today.add(Duration(days: isTomorrow ? 1 : 0)));
    }
    // in 3 months / in a week
    const numberWords = {
      'a': 1,
      'an': 1,
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'eleven': 11,
      'twelve': 12,
    };
    for (final m in RegExp(
      r'\bin\s+(\d{1,3}|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(day|week|month|year)s?\b',
      caseSensitive: false,
    ).allMatches(text)) {
      final raw = m[1]!.toLowerCase();
      final n = int.tryParse(raw) ?? numberWords[raw] ?? 1;
      add(m.start, m.end, _shift(m[2]!.toLowerCase(), n));
    }
    // next week / next month / next year
    for (final m in RegExp(r'\bnext\s+(week|month|year)\b', caseSensitive: false).allMatches(text)) {
      add(m.start, m.end, _shift(m[1]!.toLowerCase(), 1));
    }
    // on the 5th → next occurrence of that day of month
    for (final m in RegExp(r'\b(?:on\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)\b', caseSensitive: false).allMatches(text)) {
      final day = int.parse(m[1]!);
      if (day < 1 || day > 31) continue;
      var d = _date(_today.year, _today.month, day);
      if (d == null || d.isBefore(_today)) {
        d = _date(_today.year, _today.month + 1, day) ?? DateTime(_today.year, _today.month + 2, 0);
      }
      add(m.start, m.end, d);
    }

    hits.sort((a, b) => a.start.compareTo(b.start));
    return hits;
  }

  DateTime? _pickExpiry(String text, List<_DateHit> dates, {required bool preferKeywordOnly}) {
    if (dates.isEmpty) return null;
    // A date shortly after an expiry keyword wins.
    for (final kw in _expiryKw.allMatches(text)) {
      final near = dates.where((d) => d.start >= kw.end && d.start - kw.end <= 28).toList();
      if (near.isNotEmpty) return near.first.date;
    }
    final future = dates.where((d) => !d.date.isBefore(_today)).toList();
    if (preferKeywordOnly) {
      // Scanned docs: skip past dates (DOB, issue date) and take the latest.
      if (future.isEmpty) return null;
      future.sort((a, b) => a.date.compareTo(b.date));
      return future.last.date;
    }
    return (future.isNotEmpty ? future : dates).first.date;
  }

  DateTime? _date(int y, int m, int d) {
    if (m < 1 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    if (dt.month != ((m - 1) % 12) + 1 || dt.day != d) return null;
    return dt;
  }

  DateTime? _withYear(int? year, int month, int day) {
    if (year != null) return _date(year, month, day);
    final thisYear = _date(_today.year, month, day);
    if (thisYear == null) return null;
    return thisYear.isBefore(_today) ? _date(_today.year + 1, month, day) : thisYear;
  }

  DateTime _shift(String unit, int n) => switch (unit) {
    'day' => _today.add(Duration(days: n)),
    'week' => _today.add(Duration(days: 7 * n)),
    'month' => DateTime(_today.year, _today.month + n, _today.day),
    _ => DateTime(_today.year + n, _today.month, _today.day),
  };

  int _month(String s) {
    const names = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    return names.indexOf(s.toLowerCase().substring(0, 3)) + 1;
  }

  // --------------------------------------------------------------- fields --

  static const _idKeys = <String, String>{
    'policy': 'Policy #',
    'account': 'Account #',
    'acct': 'Account #',
    'a/c': 'Account #',
    'member': 'Member #',
    'membership': 'Member #',
    'customer': 'Customer #',
    'passport': 'Passport #',
    'license': 'License #',
    'licence': 'License #',
    'dl': 'License #',
    'vin': 'VIN',
    'serial': 'Serial #',
    's/n': 'Serial #',
    'ref': 'Ref #',
    'reference': 'Ref #',
    'order': 'Order #',
    'pnr': 'PNR',
    'booking': 'Booking #',
    'ticket': 'Ticket #',
    'card': 'Card #',
    'invoice': 'Invoice #',
    'id': 'ID',
    'imei': 'IMEI',
    'model': 'Model',
    'registration': 'Reg #',
    'reg': 'Reg #',
    'folio': 'Folio #',
    'confirmation': 'Confirmation #',
    'tracking': 'Tracking #',
    'plan': 'Plan',
    'roll': 'Roll #',
    'uan': 'UAN',
    'pan': 'PAN',
    'ifsc': 'IFSC',
  };

  static const _expiryKeys = {
    'exp',
    'expiry',
    'expires',
    'expire',
    'expiration',
    'expiry date',
    'expiration date',
    'valid until',
    'valid till',
    'valid thru',
    'due',
    'due date',
    'renews',
    'renewal',
    'renewal date',
    'date of expiry',
  };

  List<_Field> _findFields(String text, List<_DateHit> dates, {bool ocr = false}) {
    final out = <_Field>[];
    bool free(_Span s) => !out.any((f) => f.overlaps(s)) && !dates.any((d) => d.overlaps(s));
    void add(_Field f) {
      if (f.value.trim().isEmpty || !free(f)) return;
      out.add(f);
    }

    // Passwords / PINs: "wifi password is abc123"
    for (final m in RegExp(
      r'\b((?:wi-?fi\s+)?(?:password|passcode|pin|pwd|cvv))\s*(?:is|:|=|-)?\s*(\S{3,64})',
      caseSensitive: false,
    ).allMatches(text)) {
      final key = m[1]!.toLowerCase();
      final label = key.contains('pin') ? 'PIN' : (key.contains('cvv') ? 'CVV' : 'Password');
      final vStart = m.start + m[0]!.lastIndexOf(m[2]!);
      add(_Field(vStart, m.end, label, _trimValue(m[2]!), cut: vStart));
    }

    // Colon / equals pairs: "Paint: Chantilly Lace OC-65"
    for (final m in RegExp(
      r"(?:^|(?<=[,;\n]))\s*([A-Za-z][A-Za-z0-9 #'’./()&-]{0,30}?)\s*[:=]\s*([^,;\n]+)",
    ).allMatches(text)) {
      final key = m[1]!.trim();
      final keyStart = m.start + m[0]!.indexOf(key);
      if (_expiryKeys.contains(key.toLowerCase().replaceAll('.', '').trim())) continue;
      add(_Field(keyStart, m.end, _titleCase(key), _trimValue(m[2]!), cut: keyStart));
    }

    // Sizes: "shoe size 7.5 US", "size M"
    for (final m in RegExp(
      r'\bsize\s*(?:is\s*)?[:=-]?\s*(\d{1,3}(?:\.\d)?(?:\s*/\s*\d{1,3})?(?:\s*(?:US|UK|EU|IN|IT|FR|JP|AU|cm|mm|in))?|XXS|XS|S|M|L|XL|XXL|XXXL|[2-5]XL|small|medium|large)\b',
      caseSensitive: false,
    ).allMatches(text)) {
      final vStart = m.start + m[0]!.lastIndexOf(m[1]!);
      add(_Field(vStart, m.end, 'Size', m[1]!.trim().toUpperCaseIfShort(), cut: vStart));
    }

    // Identifiers: "Policy #9812", "Passport No. K1234567"
    final idAlternation = _idKeys.keys.map(RegExp.escape).join('|');
    for (final m in RegExp(
      '\\b($idAlternation)\\.?\\s*(?:#|no\\.?|number|num|nr|id)?\\s*[:#-]?\\s*([A-Z0-9][A-Z0-9-]{2,24})\\b',
      caseSensitive: false,
    ).allMatches(text)) {
      final value = m[2]!;
      if (!RegExp(r'\d').hasMatch(value)) continue;
      add(_Field(m.start, m.end, _idKeys[m[1]!.toLowerCase()]!, value.toUpperCase(), cut: m.start));
    }

    // Dimensions: "120x60 cm"
    for (final m in RegExp(
      r'\b(\d+(?:\.\d+)?\s?[x×]\s?\d+(?:\.\d+)?(?:\s?[x×]\s?\d+(?:\.\d+)?)?)\s?(cm|mm|in|inches|ft|m)?\b',
      caseSensitive: false,
    ).allMatches(text)) {
      final unit = m[2] == null ? '' : ' ${m[2]}';
      add(_Field(m.start, m.end, 'Dimensions', '${m[1]!.replaceAll(' ', '')}$unit', cut: m.start));
    }

    // Measurements: "waist 32 in", "72 kg"
    const measureNames = {
      'waist',
      'chest',
      'height',
      'width',
      'length',
      'depth',
      'weight',
      'inseam',
      'bust',
      'hips',
      'sleeve',
      'neck',
      'arm',
      'head',
      'foot',
      'wrist',
      'ring',
    };
    for (final m in RegExp(
      r'\b(?:([a-z]+)\s+(?:is\s+)?)?(\d+(?:\.\d+)?)\s?(cm|mm|in|inch|inches|ft|feet|kg|g|lbs?|oz|ml|l|litres?|liters?|gal)\b',
      caseSensitive: false,
    ).allMatches(text)) {
      final name = m[1]?.toLowerCase();
      final isNamed = name != null && measureNames.contains(name);
      final vStart = m.start + m[0]!.indexOf(m[2]!);
      add(
        _Field(
          isNamed ? m.start : vStart,
          m.end,
          isNamed ? _titleCase(name) : 'Measurement',
          '${m[2]} ${m[3]}',
          cut: vStart,
        ),
      );
    }

    // Hex colours: "#F4EFE6"
    for (final m in RegExp(r'#[0-9a-fA-F]{6}\b').allMatches(text)) {
      add(_Field(m.start, m.end, 'Color', m[0]!.toUpperCase(), cut: m.start));
    }

    // Prices: "$15.49/mo", "₹499 per month", "299 INR"
    for (final m in RegExp(
      r'([$₹€£¥])\s?(\d+(?:[.,]\d{1,2})?)(?:\s*(?:/|per\s+)(mo|month|yr|year|wk|week))?|\b(\d+(?:\.\d{1,2})?)\s?(rs\.?|inr|usd|eur|gbp)\b',
      caseSensitive: false,
    ).allMatches(text)) {
      final value = m[1] != null
          ? '${m[1]}${m[2]}${m[3] != null ? '/${m[3]!.startsWith('m') ? 'mo' : (m[3]!.startsWith('w') ? 'wk' : 'yr')}' : ''}'
          : '${m[4]} ${m[5]!.toUpperCase().replaceAll('.', '')}';
      add(_Field(m.start, m.end, 'Price', value, cut: m.start));
    }

    // Phone numbers
    for (final m in RegExp(r'(?<![\w#])\+?\d[\d -]{8,14}\d\b').allMatches(text)) {
      add(_Field(m.start, m.end, 'Phone', m[0]!.trim(), cut: m.start));
    }

    // Emails
    for (final m in RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.]+\b').allMatches(text)) {
      add(_Field(m.start, m.end, 'Email', m[0]!, cut: m.start));
    }

    if (ocr) {
      // Stand-alone codes on scanned docs (passport numbers, VINs, serials).
      for (final m in RegExp(r'\b(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{6,17}\b').allMatches(text)) {
        add(_Field(m.start, m.end, 'Code', m[0]!, cut: m.start));
      }
    }

    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  // ---------------------------------------------------------------- title --

  MemoryCategory _inferCategory(String text, bool hasExpiry) {
    if (_subscriptionKw.hasMatch(text)) return MemoryCategory.subscription;
    if (hasExpiry && (_docKw.hasMatch(text) || _expiryKw.hasMatch(text))) return MemoryCategory.expiryDoc;
    if (_measureKw.hasMatch(text)) return MemoryCategory.measurement;
    if (_docKw.hasMatch(text)) return MemoryCategory.expiryDoc;
    if (hasExpiry) return MemoryCategory.other;
    return MemoryCategory.staticFact;
  }

  static final _trailingJunk = RegExp(
    r"(?:[\s,;:=\-–—#(]+|\s+(?:is|are|was|on|at|of|for|no\.?|number|num|=|-))+$",
    caseSensitive: false,
  );

  String _cleanTitle(String s) {
    var t = s.trim();
    String prev;
    do {
      prev = t;
      t = t.replaceAll(_trailingJunk, '').trim();
    } while (t != prev);
    t = t.replaceAll(RegExp(r'^[\s,;:\-–—]+'), '');
    return t.length > 48 ? '${t.substring(0, 47).trim()}…' : t;
  }

  int _meaningfulWords(String s) {
    const filler = {'my', 'the', 'a', 'an', 'our', 'his', 'her', 'their', 'is', 'its'};
    return s.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1 && !filler.contains(w)).length;
  }

  String _fallbackTitle(String text, List<_Span> spans) {
    final buf = StringBuffer();
    var i = 0;
    for (final s in [...spans]..sort((a, b) => a.start.compareTo(b.start))) {
      if (s.start > i) buf.write(text.substring(i, s.start));
      if (s.end > i) i = s.end;
    }
    if (i < text.length) buf.write(text.substring(i));
    final words = buf.toString().split(RegExp(r'[\s,;:]+')).where((w) => w.length > 1).take(5).join(' ');
    return words.isEmpty ? 'Untitled memory' : _cleanTitle(words);
  }

  String _ocrTitle(String text) {
    for (final line in text.split('\n').take(6)) {
      final l = line.trim();
      final letters = RegExp(r'[A-Za-z]').allMatches(l).length;
      if (letters >= 3 && l.length <= 40 && letters / l.length > 0.6 && !l.contains(':')) {
        return _titleCase(l.toLowerCase());
      }
    }
    return 'Scanned item';
  }

  String _trimValue(String v) => v.trim().replaceAll(RegExp(r'[.\s]+$'), '');

  static String _titleCase(String s) => s.splitMapJoin(
    RegExp(r"[A-Za-z][A-Za-z'’]*"),
    onMatch: (m) {
      final w = m[0]!;
      return w[0].toUpperCase() + w.substring(1);
    },
    onNonMatch: (n) => n,
  );
}

extension on String {
  String toUpperCaseIfShort() => length <= 4 ? toUpperCase() : this;
}
