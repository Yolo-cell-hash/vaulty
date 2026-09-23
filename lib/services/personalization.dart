import '../models/memory.dart';

/// Onboarding goals. The labels are stored in settings, so keep them stable.
class Goals {
  static const expiries = 'Never miss an expiry';
  static const sizes = 'Remember sizes & specs';
  static const documents = 'Keep documents handy';
  static const subscriptions = 'Keep subscriptions in check';
  static const people = 'Birthdays & the people I love';
  static const lookups = 'Stop re-googling the same things';
  static const privacy = 'Keep it all private';

  static const all = [expiries, sizes, documents, subscriptions, people, lookups, privacy];
}

/// A starting point on the capture sheet.
class Template {
  const Template(this.label, this.category, this.keys, {this.sensitive = false, this.recurrence = Recurrence.none});

  final String label;
  final MemoryCategory category;
  final List<String> keys;
  final bool sensitive;
  final Recurrence recurrence;
}

const _templates = {
  'Passport': Template('Passport', MemoryCategory.expiryDoc, ['Passport #'], sensitive: true),
  'Car insurance': Template('Car insurance', MemoryCategory.expiryDoc, ['Policy #', 'Insurer']),
  'Shoe size': Template('Shoe size', MemoryCategory.measurement, ['Size', 'Brand']),
  'Paint color': Template('Paint color', MemoryCategory.staticFact, ['Brand', 'Color', 'Finish']),
  'Subscription': Template('Subscription', MemoryCategory.subscription, [
    'Price',
    'Plan',
  ], recurrence: Recurrence.monthly),
  'Birthday': Template('Birthday', MemoryCategory.other, ['Gift ideas'], recurrence: Recurrence.yearly),
  'Wi-Fi': Template('Wi-Fi', MemoryCategory.staticFact, ['Network', 'Password'], sensitive: true),
};

const _templatesForGoal = {
  Goals.expiries: ['Passport', 'Car insurance'],
  Goals.sizes: ['Shoe size', 'Paint color'],
  Goals.documents: ['Passport', 'Car insurance'],
  Goals.subscriptions: ['Subscription'],
  Goals.people: ['Birthday', 'Shoe size'],
  Goals.lookups: ['Wi-Fi', 'Paint color'],
  Goals.privacy: ['Wi-Fi', 'Passport'],
};

const _examplesForGoal = {
  Goals.expiries: 'Car insurance expires Nov 12, Policy #9812',
  Goals.sizes: "Mom's shoe size 7.5 US",
  Goals.documents: 'Passport expires 15 Mar 2031, no K1234567',
  Goals.subscriptions: r'Netflix $15.49/mo renews on the 5th',
  Goals.people: 'Joe birthday 24th Sept',
  Goals.lookups: 'Living room paint: Chantilly Lace OC-65',
  Goals.privacy: 'Home wifi password is sunshine22',
};

/// Picks what someone said they care about first, then fills in the rest.
List<T> _prioritised<T>(List<String> goals, Map<String, List<T>> byGoal, List<T> everything, int take) {
  final out = <T>[];
  for (final g in goals) {
    for (final item in byGoal[g] ?? <T>[]) {
      if (!out.contains(item)) out.add(item);
    }
  }
  for (final item in everything) {
    if (!out.contains(item)) out.add(item);
  }
  return out.take(take).toList();
}

List<Template> templatesFor(List<String> goals) =>
    _prioritised(goals, _templatesForGoal, _templates.keys.toList(), 7).map((k) => _templates[k]!).toList();

List<String> examplesFor(List<String> goals) => _prioritised(
  goals,
  {
    for (final e in _examplesForGoal.entries) e.key: [e.value],
  },
  _examplesForGoal.values.toList(),
  4,
);

/// Onboarding reminder-time answers → minutes after midnight.
const reminderTimeChoices = [
  ('Morning, around 9', 9 * 60),
  ('Lunchtime, 12:30', 12 * 60 + 30),
  ('Evening, around 7', 19 * 60),
  ('Late, around 9:30 pm', 21 * 60 + 30),
];

/// Onboarding lead-time answers → default reminder offsets.
const leadTimeChoices = [
  ('Just the day before', [1, 0]),
  ('About a week before', [7, 1, 0]),
  ('A month ahead', [30, 7, 1, 0]),
  ('Way ahead, I plan early', [90, 30, 7, 1, 0]),
];
