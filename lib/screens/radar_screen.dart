import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory.dart';
import '../state/vault_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/mascot.dart';
import '../widgets/memory_cards.dart';
import '../widgets/renew_sheet.dart';
import '../widgets/swipe_actions.dart';

class RadarScreen extends ConsumerWidget {
  const RadarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vc;
    final radar = ref.watch(radarProvider);
    final groups = <(String, List<Memory>)>[
      ('Overdue', radar.where((m) => m.daysLeft! < 0).toList()),
      ('Next 2 weeks', radar.where((m) => m.daysLeft! >= 0 && m.daysLeft! <= 14).toList()),
      ('Next 2 months', radar.where((m) => m.daysLeft! > 14 && m.daysLeft! <= 60).toList()),
      ('Later', radar.where((m) => m.daysLeft! > 60).toList()),
    ];
    final urgent = groups[0].$2.length + groups[1].$2.length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.page, 20, Space.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Radar', style: context.type.display),
                  const SizedBox(height: 6),
                  Text('Everything with a date, most urgent first.', style: context.type.bodySoft),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      _Stat(value: urgent, label: 'Urgent', color: urgent > 0 ? c.danger : null),
                      _divider(c),
                      _Stat(value: groups[2].$2.length, label: 'Soon'),
                      _divider(c),
                      _Stat(value: groups[3].$2.length, label: 'Later'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (radar.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'Nothing on the radar',
              subtitle: 'Give anything a date and it shows up here, counting down.',
              mood: MascotMood.sleepy,
              prop: MascotProp.zzz,
            ),
          )
        else
          for (final (title, items) in groups)
            if (items.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, 30, Space.page, 10),
                  child: Eyebrow('$title  ·  ${items.length}', color: title == 'Overdue' ? c.danger : null),
                ),
              ),
              SliverToBoxAdapter(
                child: MemoryList(
                  items: items,
                  rowBuilder: (m, row) => _SwipeToArchive(memory: m, child: row),
                ),
              ),
            ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 18, Space.page, 0),
            child: Text(
              radar.isEmpty
                  ? ''
                  : 'Swipe right when you’ve renewed something, left to archive. Birthdays and subscriptions roll over on their own.',
              style: context.type.caption.copyWith(color: c.inkFaint),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ],
    );
  }

  Widget _divider(VaultyColors c) =>
      Container(width: 1, height: 40, margin: const EdgeInsets.symmetric(horizontal: 18), color: c.line);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});

  final int value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: context.type.numeral(40, color)),
        const SizedBox(height: 4),
        Eyebrow(label),
      ],
    );
  }
}

class _SwipeToArchive extends ConsumerWidget {
  const _SwipeToArchive({required this.memory, required this.child});

  final Memory memory;
  final Widget child;

  Future<void> _renew(BuildContext context, WidgetRef ref) async {
    final toast = toaster(context);
    final date = await showRenewSheet(context, memory);
    if (date != null) {
      await ref.read(vaultProvider.notifier).renew(memory, date);
      toast('Renewed until ${dateFmt.format(date)}');
    }
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final toast = toaster(context);
    final notifier = ref.read(vaultProvider.notifier);
    await notifier.setArchived(memory.id, true);
    toast(
      'Archived “${memory.title}”',
      icon: G.archive,
      action: ToastAction('Undo', () => notifier.setArchived(memory.id, false)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vc;
    final renewable = !memory.isRecurring;
    if (context.isCupertino) {
      // iOS rows reveal buttons: tap one, or swipe all the way through.
      return SwipeActions(
        key: ValueKey('radar-${memory.id}'),
        leading: !renewable
            ? null
            : SwipeAction(label: 'Renewed', glyph: G.repeat, color: c.ok, onTrigger: () => _renew(context, ref)),
        trailing: SwipeAction(
          label: 'Archive',
          glyph: G.archive,
          color: c.brand,
          removes: true,
          onTrigger: () => _archive(context, ref),
        ),
        child: child,
      );
    }
    return Dismissible(
      key: ValueKey('radar-${memory.id}'),
      direction: renewable ? DismissDirection.horizontal : DismissDirection.endToStart,
      // Swipe right: renewed it. Swipe left: archive.
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 22),
        color: c.okSoft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VIcon(G.repeat, size: 18, color: c.ok),
            const SizedBox(width: 8),
            Text(
              'Renewed',
              style: context.type.caption.copyWith(color: c.ok, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        color: c.sunken,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Archive',
              style: context.type.caption.copyWith(color: c.ink, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            VIcon(G.archive, size: 18, color: c.ink),
          ],
        ),
      ),
      // Archive inside confirmDismiss so the row leaves the list before the
      // dismiss animation finishes (onDismissed would race the async reload).
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          await _renew(context, ref);
          return false; // The row stays; it just moves to its new slot.
        }
        await _archive(context, ref);
        return true;
      },
      child: child,
    );
  }
}
