import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glyphs.dart';

/// Slim progress rule with a step counter.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.step, required this.total, this.onBack});

  final int step;
  final int total;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Row(
      children: [
        if (onBack != null)
          VIconButton(G.chevronLeft, label: 'Back', size: 36, onTap: onBack)
        else
          const SizedBox(width: 36),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (step / total).clamp(0, 1)),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) =>
                  LinearProgressIndicator(value: v, minHeight: 3, backgroundColor: c.line, color: c.ink),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Text('$step/$total', style: context.type.mono(12, c.inkFaint)),
      ],
    );
  }
}

/// Answer row: glyph (or index) + label + selection circle.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.glyph,
    this.index,
    this.multi = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final G? glyph;

  /// Shown as "01", "02"… when there is no glyph.
  final int? index;

  /// Multi-select shows a check box; single-select shows a radio dot.
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Pressable(
      onTap: onTap,
      scale: .985,
      semanticLabel: label,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.l),
          border: Border.all(color: selected ? c.ink : c.line, width: selected ? 1.4 : 1),
        ),
        child: Row(
          children: [
            if (glyph != null)
              VIcon(glyph!, size: 21, color: selected ? c.ink : c.inkSoft)
            else if (index != null)
              Text((index! + 1).toString().padLeft(2, '0'), style: context.type.mono(13, c.inkFaint)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: context.type.body.copyWith(
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: multi ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: multi ? BorderRadius.circular(7) : null,
                color: selected ? c.ink : Colors.transparent,
                border: Border.all(color: selected ? c.ink : c.line, width: 1.4),
              ),
              alignment: Alignment.center,
              child: selected ? VIcon(G.check, size: 14, color: c.onInk, stroke: 2.4) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single promise line on the welcome screen.
class FeatureLine extends StatelessWidget {
  const FeatureLine({super.key, required this.glyph, required this.text});
  final G glyph;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          VIcon(glyph, size: 20, color: c.ink),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: context.type.body)),
        ],
      ),
    );
  }
}

/// Typographic before/after: struck-through worries, checked outcomes.
class BeforeAfter extends StatelessWidget {
  const BeforeAfter({super.key});

  static const _before = [
    'Texting Mom for her shoe size',
    'Late fees you didn’t see coming',
    'Digging for the passport number',
  ];
  static const _after = [
    'Every size and code in one place',
    'A nudge before anything lapses',
    'Answers in a second, offline',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Before'),
        const SizedBox(height: 12),
        for (final b in _before)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              b,
              style: context.type.body.copyWith(
                fontSize: 17,
                color: c.inkFaint,
                decoration: TextDecoration.lineThrough,
                decorationColor: c.inkFaint,
              ),
            ),
          ),
        const SizedBox(height: 22),
        Eyebrow('After', color: c.brand),
        const SizedBox(height: 12),
        for (final a in _after)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: c.acid, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const VIcon(G.check, size: 13, color: Color(0xFF151419), stroke: 2.4),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(a, style: context.type.body.copyWith(fontSize: 17, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Mock notification to preview reminders.
class NotificationPreview extends StatelessWidget {
  const NotificationPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return VCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text(
              'v',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 24,
                height: 1,
                color: c.acid,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('VAULTY', style: context.type.eyebrow),
                    const Spacer(),
                    Text('9:00', style: context.type.mono(11, c.inkFaint)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Passport expires in 1 week', style: context.type.item),
                const SizedBox(height: 2),
                Text('Plenty of time to renew. Details are in your vault.', style: context.type.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
