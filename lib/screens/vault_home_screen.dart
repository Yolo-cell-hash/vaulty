import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory.dart';
import '../services/personalization.dart';
import '../services/settings.dart';
import '../state/vault_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/flow_sheet.dart';
import '../widgets/glyphs.dart';
import '../widgets/mascot.dart';
import '../widgets/memory_cards.dart';
import '../widgets/tag_widgets.dart';
import 'capture/capture_sheet.dart';
import 'capture/quick_capture_screen.dart';

class VaultHomeScreen extends ConsumerStatefulWidget {
  const VaultHomeScreen({super.key, required this.onOpenRadar, required this.onOpenSearch, required this.onOpenMe});

  final VoidCallback onOpenRadar;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenMe;

  @override
  ConsumerState<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

/// Memory Bank filters: categories first, then the user's own tags.
class _Filter {
  const _Filter(this.label, this.test);
  final String label;
  final bool Function(Memory) test;
}

class _VaultHomeScreenState extends ConsumerState<VaultHomeScreen> {
  int _filter = 0;

  List<_Filter> _filters(List<Tag> tags) => [
    _Filter('All', (m) => !m.hasExpiry),
    _Filter('Docs', (m) => m.category == MemoryCategory.expiryDoc),
    _Filter('Subs', (m) => m.category == MemoryCategory.subscription),
    _Filter('Facts', (m) => m.category == MemoryCategory.staticFact),
    _Filter('Sizes', (m) => m.category == MemoryCategory.measurement),
    _Filter('Other', (m) => m.category == MemoryCategory.other),
    for (final t in tags)
      if (!t.isPerson && t.uses > 0) _Filter('#${t.name}', (m) => m.tags.any((x) => x.id == t.id)),
  ];

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultProvider);
    final items = vault.value ?? const <Memory>[];
    final radar = ref.watch(radarProvider);
    final people = ref.watch(peopleProvider).where((p) => p.uses > 0).toList();
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];

    final filters = _filters(tags);
    final active = _filter < filters.length ? _filter : 0;
    final counts = [for (final f in filters) items.where(f.test).length];
    // Hide empty category tabs (except "All") so the row stays tight.
    final visible = [
      for (var i = 0; i < filters.length; i++)
        if (i == 0 || counts[i] > 0) i,
    ];
    final bank = items.where(filters[active].test).toList();

    return PageScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Header(items: items, radar: radar, onSearch: widget.onOpenSearch, onMe: widget.onOpenMe),
        ),
        if (vault.isLoading && !vault.hasValue)
          const SliverFillRemaining(child: Center(child: Spinner()))
        else if (vault.hasError && !vault.hasValue)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(title: 'The vault won’t open', subtitle: '${vault.error}', mood: MascotMood.wow),
          )
        else if (items.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: _EmptyVault())
        else ...[
          if (radar.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 20, Space.l, 0),
                child: HeroCard(memory: radar.first),
              ),
            ),
            if (radar.length > 1) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Coming up',
                  action: radar.length > 5 ? 'All ${radar.length}' : 'Radar',
                  onAction: widget.onOpenRadar,
                ),
              ),
              SliverToBoxAdapter(child: MemoryList(items: radar.skip(1).take(4).toList())),
            ],
          ],
          if (people.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader(title: 'People')),
            SliverToBoxAdapter(child: PeopleStrip(people: people)),
          ],
          const SliverToBoxAdapter(
            child: SectionHeader(title: 'Memory bank', padding: EdgeInsets.fromLTRB(Space.page, 28, Space.page, 6)),
          ),
          SliverToBoxAdapter(
            child: UnderlineTabs(
              labels: [for (final i in visible) filters[i].label],
              counts: [for (final i in visible) counts[i]],
              index: visible.indexOf(active).clamp(0, visible.length - 1),
              onChanged: (i) => setState(() => _filter = visible[i]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
          if (bank.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                child: VCard(
                  child: Row(
                    children: [
                      const Mascot(size: 54, mood: MascotMood.wink, animate: false),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          active == 0
                              ? 'Stash the little things too: shoe sizes, paint codes, the Wi-Fi password.'
                              : 'Nothing here yet.',
                          style: context.type.bodySoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverToBoxAdapter(child: MemoryGrid(items: bank)),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.items, required this.radar, required this.onSearch, required this.onMe});

  final List<Memory> items;
  final List<Memory> radar;
  final VoidCallback onSearch;
  final VoidCallback onMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vc;
    final settings = ref.watch(settingsProvider);
    final name = settings.name.trim();
    final week = radar.where((m) => m.daysLeft! <= 7).length;
    final month = radar.where((m) => m.daysLeft! <= 30).length;
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? 'Up late'
        : hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final summary = items.isEmpty
        ? 'Your vault is ready when you are.'
        : week > 0
        ? '$week ${week == 1 ? 'thing needs' : 'things need'} you this week.'
        : month > 0
        ? 'Quiet week. $month coming up this month.'
        : 'All clear. Nothing due this month.';

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Wordmark(size: 24),
                const Spacer(),
                VIconButton(G.search, onTap: onSearch, label: 'Search'),
                if (settings.streak > 1) ...[_Streak(days: settings.streak), const SizedBox(width: 4)],
                Pressable(
                  onTap: onMe,
                  semanticLabel: 'Your settings',
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Monogram(
                      tag: Tag(id: 'me', name: name.isEmpty ? 'You' : name, kind: TagKind.person),
                      size: 34,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$greeting${name.isEmpty ? '.' : ','}'),
                  if (name.isNotEmpty) ...[
                    const TextSpan(text: '\n'),
                    TextSpan(text: '$name.', style: context.type.accent),
                  ],
                ],
              ),
              style: context.type.display,
            ),
            const SizedBox(height: 10),
            Text(summary, style: context.type.bodySoft.copyWith(color: c.inkSoft)),
          ],
        ),
      ),
    );
  }
}

class _Streak extends StatelessWidget {
  const _Streak({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Semantics(
      label: '$days day streak',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 5, 10, 5),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VIcon(G.flame, size: 15, color: c.ink, stroke: 1.8),
            const SizedBox(width: 3),
            Text('$days', style: context.type.mono(13)),
          ],
        ),
      ),
    );
  }
}

class _EmptyVault extends ConsumerWidget {
  const _EmptyVault();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final examples = examplesFor(ref.watch(settingsProvider.select((s) => s.goals)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.page, 28, Space.page, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VCard(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Mascot(size: 64, prop: MascotProp.sparkles, animate: false),
                    Spacer(),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Start with one thing\nyou always forget.', style: context.type.headline.copyWith(fontSize: 26)),
                const SizedBox(height: 8),
                Text('Type it the way you’d text a friend. Vaulty figures out the rest.', style: context.type.bodySoft),
                const SizedBox(height: 18),
                VButton(label: 'Add your first memory', icon: G.plus, onPressed: () => showCaptureSheet(context)),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const Eyebrow('Try saying'),
          const SizedBox(height: 10),
          for (final e in examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Pressable(
                onTap: () => presentFlow<void>(context, (_) => QuickCaptureScreen(initialText: e)),
                child: Row(
                  children: [
                    VIcon(G.arrowUpRight, size: 15, color: context.vc.inkFaint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e, style: context.type.body.copyWith(color: context.vc.inkSoft)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
