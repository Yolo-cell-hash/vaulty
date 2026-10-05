import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/memory.dart';
import '../screens/memory_detail_screen.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'glyphs.dart';

final dateFmt = DateFormat('d MMM yyyy');
final _dayFmt = DateFormat('d');
final _monFmt = DateFormat('MMM');

String maskedValue(Memory m, String value) => m.isSensitive ? '•' * value.length.clamp(4, 8) : value;

/// One sentence a screen reader can say for a memory card: what it is, when
/// it's due, the value you came for (never a hidden one), and who it's for.
String memorySemantics(Memory m) {
  final head = m.headline;
  final next = m.nextDate;
  return [
    m.title.isEmpty ? 'Untitled' : m.title,
    m.isOccasion ? 'Occasion' : m.category.label,
    if (next != null) '${_capitalised(m.spokenCountdown)}, ${DateFormat('d MMMM yyyy').format(next)}',
    if (m.isSensitive) 'Hidden details' else if (head != null) '${head.key} ${head.value}',
    if (m.people.isNotEmpty) 'for ${m.people.map((p) => p.name).join(', ')}',
  ].join('. ');
}

String _capitalised(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

void openMemory(BuildContext context, Memory m) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemoryDetailScreen(memoryId: m.id)));
}

/// "Up next": an ink pass-style card with a big serif countdown.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final days = memory.daysLeft!;
    final overdue = days < 0;
    final numeralColor = overdue ? const Color(0xFFFF7A7F) : c.acid;
    // Ink card stays dark in both themes; in dark mode lift it slightly.
    final bg = context.isDark ? const Color(0xFF232329) : c.ink;
    const fg = Color(0xFFF6F4EF);
    const fgSoft = Color(0xFFA9A6B0);
    return Pressable(
      onTap: () => openMemory(context, memory),
      scale: .98,
      semanticLabel: 'Up next. ${memorySemantics(memory)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.xl)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('UP NEXT', style: context.type.eyebrow.copyWith(color: numeralColor)),
                const Spacer(),
                VIcon(memory.category.glyph, size: 16, color: fgSoft),
                const SizedBox(width: 6),
                Text(memory.category.label.toUpperCase(), style: context.type.eyebrow.copyWith(color: fgSoft)),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memory.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.headline.copyWith(color: fg, fontSize: 28),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        [memory.dateCaption(dateFmt.format), ?memory.milestone].join('  ·  '),
                        style: context.type.caption.copyWith(color: fgSoft),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${days.abs()}', style: context.type.numeral(days.abs() > 999 ? 48 : 68, numeralColor)),
                    const SizedBox(height: 4),
                    Text(memory.countdownUnit, style: context.type.caption.copyWith(color: fgSoft)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Serif day number over a small month label.
class DateBlock extends StatelessWidget {
  const DateBlock({super.key, required this.date, this.color});
  final DateTime date;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    // Sits in a fixed 44pt column, so it only grows a little with text size.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SizedBox(
        width: 44,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_dayFmt.format(date), style: context.type.numeral(28, color ?? c.ink)),
            const SizedBox(height: 3),
            Text(_monFmt.format(date).toUpperCase(), style: context.type.eyebrow.copyWith(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

/// The one list row used everywhere (home timeline, radar, search, people).
class MemoryRow extends StatelessWidget {
  const MemoryRow({super.key, required this.memory, this.subtitle});

  final Memory memory;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final next = memory.nextDate;
    final head = memory.headline;
    final meta =
        subtitle ??
        [
          if (memory.people.isNotEmpty) memory.people.map((p) => p.name).join(', '),
          if (next == null && head != null) '${head.key} ${maskedValue(memory, head.value)}',
          if (next != null && memory.milestone != null) memory.milestone!,
          if (next != null && memory.milestone == null) memory.category.label,
          if (next == null && head == null) memory.category.label,
        ].join('  ·  ');
    return Pressable(
      onTap: () => openMemory(context, memory),
      scale: .99,
      highlight: true,
      semanticLabel: memorySemantics(memory),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (next != null)
              DateBlock(date: next, color: memory.urgency == Urgency.chill ? null : memory.urgency!.color(c))
            else
              SizedBox(
                width: 44,
                child: Center(child: VIcon(memory.category.glyph, size: 22, color: memory.category.color(c))),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(memory.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.type.item),
                  const SizedBox(height: 3),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.type.caption),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (next != null)
              CountdownTag(memory: memory, compact: true)
            else
              VIcon(G.chevronRight, size: 16, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// A stack of [MemoryRow]s inside one hairline card.
class MemoryList extends StatelessWidget {
  const MemoryList({super.key, required this.items, this.rowBuilder});

  final List<Memory> items;

  /// Lets callers wrap rows (e.g. swipe-to-archive).
  final Widget Function(Memory m, Widget row)? rowBuilder;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) children.add(const Hairline(indent: 74));
      final row = MemoryRow(memory: items[i]);
      children.add(rowBuilder?.call(items[i], row) ?? row);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: VCard(
        padding: EdgeInsets.zero,
        child: Column(children: children),
      ),
    );
  }
}

/// Memory Bank card: category, title, and the one value you came for.
class FactCard extends StatelessWidget {
  const FactCard({super.key, required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final head = memory.headline;
    return VCard(
      onTap: () => openMemory(context, memory),
      semanticLabel: memorySemantics(memory),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: CategoryLabel.of(memory, size: 13)),
              if (memory.isSensitive) VIcon(G.lock, size: 14, color: c.inkFaint),
            ],
          ),
          const SizedBox(height: 14),
          Text(memory.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.type.item),
          const SizedBox(height: 10),
          if (head != null) ...[
            Text(
              head.key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.caption.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              maskedValue(memory, head.value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.mono(17),
            ),
          ] else if (memory.hasExpiry)
            CountdownTag(memory: memory, compact: true)
          else
            Text(
              memory.isSensitive ? 'Hidden' : (memory.rawContent.isEmpty ? 'No details yet' : memory.rawContent),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.type.caption,
            ),
          if (memory.people.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final p in memory.people.take(3))
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Monogram(tag: p, size: 22),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Two-column masonry of [FactCard]s.
class MemoryGrid extends StatelessWidget {
  const MemoryGrid({super.key, required this.items});

  final List<Memory> items;

  @override
  Widget build(BuildContext context) {
    final left = <Widget>[], right = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FactCard(memory: items[i]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: left)),
          const SizedBox(width: 10),
          Expanded(child: Column(children: right)),
        ],
      ),
    );
  }
}
