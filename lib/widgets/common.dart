import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/memory.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'glyphs.dart';
import 'mascot.dart';

// ---------------------------------------------------------------- styling --

extension CategoryStyle on MemoryCategory {
  G get glyph => switch (this) {
    MemoryCategory.staticFact => G.sparkle,
    MemoryCategory.expiryDoc => G.document,
    MemoryCategory.subscription => G.repeat,
    MemoryCategory.measurement => G.ruler,
    MemoryCategory.other => G.box,
  };

  Color color(VaultyColors c) => switch (this) {
    MemoryCategory.staticFact => c.brand,
    MemoryCategory.expiryDoc => c.ochre,
    MemoryCategory.subscription => c.rose,
    MemoryCategory.measurement => c.teal,
    MemoryCategory.other => c.slate,
  };
}

extension UrgencyStyle on Urgency {
  /// Only things that need you get colour; everything else stays ink.
  Color color(VaultyColors c) => switch (this) {
    Urgency.expired || Urgency.urgent => c.danger,
    Urgency.soon => c.warn,
    Urgency.chill => c.inkSoft,
  };

  Color soft(VaultyColors c) => switch (this) {
    Urgency.expired || Urgency.urgent => c.dangerSoft,
    Urgency.soon => c.warnSoft,
    Urgency.chill => c.sunken,
  };
}

extension TagStyle on Tag {
  Color color(VaultyColors c) {
    final palette = [c.brand, c.rose, c.teal, c.ochre, c.slate, c.ok];
    final hash = name.toLowerCase().codeUnits.fold<int>(7, (h, u) => (h * 31 + u) & 0x7fffffff);
    return palette[hash % palette.length];
  }
}

extension MemoryStyle on Memory {
  G get dateGlyph => isOccasion ? G.cake : (isRecurring ? G.repeat : G.clock);
}

extension BiometricStyle on Biometric {
  G get glyph => switch (this) {
    Biometric.faceId => G.faceId,
    Biometric.touchId => G.fingerprint,
    Biometric.passcode => G.lock,
  };
}

// ------------------------------------------------------------ interaction --

/// Quiet press feedback: a small scale + optional light haptic.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = .97,
    this.haptic = true,
    this.semanticLabel,
    this.selected,
    this.excludeSemantics,
    this.dimWhenDisabled = false,
    this.highlight = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final String? semanticLabel;

  /// Announced as "selected" by screen readers (tabs, chips, options).
  final bool? selected;

  /// Read only [semanticLabel], not the text inside, so nothing is read
  /// twice. Defaults to true whenever a label is given; pass false when the
  /// child holds its own controls (a chip with a remove button).
  final bool? excludeSemantics;

  /// Fade when there's no handler. Only controls that can be "off" (buttons)
  /// want this; display-only rows and chips should look normal.
  final bool dimWhenDisabled;

  /// List rows: on iOS they shade while pressed, like a table cell, instead
  /// of shrinking. Elsewhere they scale like everything else.
  final bool highlight;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final ios = context.isCupertino;
    final content = AnimatedOpacity(
      opacity: enabled || !widget.dimWhenDisabled ? 1 : .4,
      duration: const Duration(milliseconds: 150),
      child: widget.child,
    );
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      selected: widget.selected,
      excludeSemantics: widget.semanticLabel != null && (widget.excludeSemantics ?? true),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                // iOS keeps plain taps silent, like UIKit buttons; only
                // selection controls (tabs, chips, options) tick.
                if (widget.haptic && (!ios || widget.selected != null)) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: widget.highlight && ios
            ? AnimatedContainer(
                duration: Duration(milliseconds: _down ? 0 : 250),
                // Fade alpha only, so the shade never passes through grey.
                color: context.vc.line.withValues(alpha: _down ? 1 : 0),
                child: content,
              )
            : AnimatedScale(
                scale: _down ? widget.scale : 1,
                duration: Duration(milliseconds: _down ? 80 : 220),
                curve: _down ? Curves.easeOut : Curves.easeOutBack,
                child: content,
              ),
      ),
    );
  }
}

enum ButtonStyleKind { ink, brand, outline, ghost, danger }

/// Pill button. `ink` is the default primary action.
class VButton extends StatelessWidget {
  const VButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = ButtonStyleKind.ink,
    this.busy = false,
    this.expand = true,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final G? icon;
  final ButtonStyleKind kind;
  final bool busy;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final (bg, fg, border) = switch (kind) {
      ButtonStyleKind.ink => (c.ink, c.onInk, null),
      ButtonStyleKind.brand => (c.brand, Colors.white, null),
      ButtonStyleKind.outline => (Colors.transparent, c.ink, c.line),
      ButtonStyleKind.ghost => (Colors.transparent, c.inkSoft, null),
      ButtonStyleKind.danger => (c.dangerSoft, c.danger, null),
    };
    final enabled = onPressed != null && !busy;
    return Pressable(
      onTap: enabled ? onPressed : null,
      semanticLabel: label,
      dimWhenDisabled: !busy,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: expand ? 0 : 22),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(height),
          border: border == null ? null : Border.all(color: border, width: 1.2),
        ),
        alignment: Alignment.center,
        child: busy
            ? Spinner(color: fg)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[VIcon(icon!, size: 19, color: fg), const SizedBox(width: 9)],
                  Text(label, style: context.type.button.copyWith(color: fg)),
                ],
              ),
      ),
    );
  }
}

/// Round icon button (top bars, inline actions).
class VIconButton extends StatelessWidget {
  const VIconButton(
    this.glyph, {
    super.key,
    required this.onTap,
    this.label,
    this.filled = false,
    this.color,
    this.size = 40,
  });

  final G glyph;
  final VoidCallback? onTap;
  final String? label;
  final bool filled;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      scale: .9,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? c.surface : Colors.transparent,
          border: filled ? Border.all(color: c.line) : null,
        ),
        alignment: Alignment.center,
        child: VIcon(glyph, size: size * .5, color: color ?? c.ink),
      ),
    );
  }
}

// --------------------------------------------------------------- surfaces --

/// Flat surface with a hairline. No drop shadows anywhere in the app.
class VCard extends StatelessWidget {
  const VCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.onTap,
    this.radius = Radii.l,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final double radius;

  /// Full spoken description for tappable cards; replaces the inner text.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final card = Container(
      width: double.infinity,
      padding: padding,
      // Row highlights and swipe actions stay inside the rounded corners.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.line.withValues(alpha: context.isDark ? 1 : .8)),
      ),
      child: child,
    );
    return onTap == null
        ? card
        : Pressable(onTap: onTap, scale: .985, semanticLabel: semanticLabel, excludeSemantics: true, child: card);
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0});
  final double indent;

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: EdgeInsets.only(left: indent),
    color: context.vc.line.withValues(alpha: .8),
  );
}

/// Small caps label.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.dot});
  final String text;
  final Color? color;

  /// Optional coloured dot before the label (category/status).
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final label = Text(text.toUpperCase(), style: context.type.eyebrow.copyWith(color: color));
    if (dot == null) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        label,
      ],
    );
  }
}

/// Section heading with an optional text action ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction, this.padding});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(Space.page, 28, Space.page, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: Text(title, style: context.type.title)),
          if (action != null)
            Pressable(
              onTap: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action!,
                    style: context.type.caption.copyWith(color: c.inkSoft, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 2),
                  VIcon(G.chevronRight, size: 14, color: c.inkSoft),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- status --

/// Countdown label. Neutral unless the date actually needs attention.
class CountdownTag extends StatelessWidget {
  const CountdownTag({super.key, required this.memory, this.compact = false});

  final Memory memory;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final u = memory.urgency!;
    final fg = u.color(c);
    final tag = Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3.5 : 5),
      decoration: BoxDecoration(color: u.soft(c), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          VIcon(memory.dateGlyph, size: compact ? 12 : 13.5, color: fg, stroke: 2),
          const SizedBox(width: 5),
          Text(
            memory.countdownText,
            style: context.type.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11.5 : 12.5,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
    // A dense badge: grows with text size, but not so far it crowds the title.
    return Semantics(
      label: memory.spokenCountdown,
      excludeSemantics: true,
      child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.4, child: tag),
    );
  }
}

/// Category shown as coloured glyph + label (no icon-in-a-box).
class CategoryLabel extends StatelessWidget {
  const CategoryLabel({super.key, required this.category, this.size = 14, this.occasion = false});

  /// Birthdays/anniversaries read as "Occasion" with a cake, whatever their category.
  factory CategoryLabel.of(Memory m, {double size = 14}) =>
      CategoryLabel(category: m.category, size: size, occasion: m.isOccasion);

  final MemoryCategory category;
  final double size;
  final bool occasion;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VIcon(
          occasion ? G.cake : category.glyph,
          size: size,
          color: occasion ? c.rose : category.color(c),
          stroke: 1.9,
        ),
        const SizedBox(width: 6),
        Text(
          (occasion ? 'Occasion' : category.label).toUpperCase(),
          style: context.type.eyebrow.copyWith(color: c.inkSoft),
        ),
      ],
    );
  }
}

/// Initials on a softly tinted disc.
class Monogram extends StatelessWidget {
  const Monogram({super.key, required this.tag, this.size = 40, this.ring = false});

  final Tag tag;
  final double size;

  /// Thin accent ring (used in the people row).
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final col = tag.color(c);
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: col.withValues(alpha: context.isDark ? .22 : .13),
      ),
      alignment: Alignment.center,
      child: Text(
        tag.initials,
        style: TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: size * (tag.initials.length > 1 ? .4 : .5),
          height: 1,
          color: col,
        ),
      ),
    );
    return Semantics(
      label: tag.name,
      excludeSemantics: true,
      child: !ring
          ? disc
          : Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: col.withValues(alpha: .5), width: 1.2),
              ),
              child: disc,
            ),
    );
  }
}

// ----------------------------------------------------------------- inputs --

/// Text tabs with a sliding underline. Premium alternative to pill chips.
class UnderlineTabs extends StatelessWidget {
  const UnderlineTabs({super.key, required this.labels, required this.index, required this.onChanged, this.counts});

  final List<String> labels;
  final List<int>? counts;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    // Fixed-height strip: let the labels grow a little, then scroll sideways.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          itemCount: labels.length,
          separatorBuilder: (_, _) => const SizedBox(width: 22),
          itemBuilder: (context, i) {
            final selected = i == index;
            return Pressable(
              onTap: () => onChanged(i),
              scale: 1,
              semanticLabel: counts == null ? labels[i] : '${labels[i]}, ${counts![i]}',
              selected: selected,
              excludeSemantics: true,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: labels[i]),
                        if (counts != null)
                          TextSpan(
                            text: ' ${counts![i]}',
                            style: context.type.mono(11.5, selected ? c.inkSoft : c.inkFaint),
                          ),
                      ],
                    ),
                    style: context.type.item.copyWith(
                      fontSize: 15,
                      color: selected ? c.ink : c.inkFaint,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: 2,
                    width: selected ? 18 : 0,
                    decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(2)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Small rounded chip for suggestions / quick picks.
class VChip extends StatelessWidget {
  const VChip({super.key, required this.label, this.onTap, this.icon, this.selected = false, this.leading});

  final String label;
  final VoidCallback? onTap;
  final G? icon;
  final bool selected;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.fromLTRB(leading != null ? 5 : 13, 7, 13, 7),
        decoration: BoxDecoration(
          color: selected ? c.ink : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.ink : c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 7)],
            if (icon != null) ...[
              VIcon(icon!, size: 15, color: selected ? c.onInk : c.inkSoft),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: context.type.caption.copyWith(
                fontSize: 13.5,
                color: selected ? c.onInk : c.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ lists --

/// iOS-style inset group of rows separated by hairlines.
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children, this.header});
  final List<Widget> children;
  final String? header;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Hairline(indent: 52));
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null) Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 10), child: Eyebrow(header!)),
        VCard(
          padding: EdgeInsets.zero,
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.glyph,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.chevron = true,
  });

  final String title;
  final G? glyph;
  final Widget? leading;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final fg = danger ? c.danger : c.ink;
    final row = Pressable(
      onTap: onTap,
      scale: .99,
      highlight: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: [
            if (leading != null)
              SizedBox(width: 24, child: leading)
            else if (glyph != null)
              VIcon(glyph!, size: 21, color: danger ? c.danger : c.inkSoft),
            if (leading != null || glyph != null) const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.type.item.copyWith(color: fg, fontWeight: FontWeight.w500),
                  ),
                  if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: context.type.caption)],
                ],
              ),
            ),
            ?trailing,
            if (trailing == null && chevron && onTap != null) VIcon(G.chevronRight, size: 16, color: c.inkFaint),
          ],
        ),
      ),
    );
    // A row with a switch reads as one control: "App lock, ..., switch, on".
    return trailing == null ? row : MergeSemantics(child: row);
  }
}

// --------------------------------------------------------------- feedback --

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.mood = MascotMood.happy,
    this.prop = MascotProp.none,
    this.size = 120,
    this.action,
  });

  final String title;
  final String subtitle;
  final MascotMood mood;
  final MascotProp prop;
  final double size;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Mascot(size: size, mood: mood, prop: prop),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: context.type.headline.copyWith(fontSize: 26)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: context.type.bodySoft),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// Indeterminate progress: the iOS activity indicator, or a thin ring.
class Spinner extends StatelessWidget {
  const Spinner({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => context.isCupertino
      ? CupertinoActivityIndicator(radius: size / 2, color: color)
      : SizedBox.square(
          dimension: size,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        );
}

/// A button on a toast ("Undo").
class ToastAction {
  const ToastAction(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;
}

typedef Toast = void Function(String message, {G icon, ToastAction? action});

/// Captures what a toast needs up front, so it can still be shown after the
/// calling widget is gone (e.g. a row that was just archived or a popped page).
///
/// Android shows a snackbar above the nav. iOS has no snackbar, so it drops a
/// capsule in from the top, where the system shows its own confirmations.
Toast toaster(BuildContext context) {
  if (context.isCupertino) {
    final overlay = Overlay.of(context, rootOverlay: true);
    return (String message, {G icon = G.check, ToastAction? action}) => _TopToast.show(overlay, message, icon, action);
  }
  final c = context.vc;
  final m = ScaffoldMessenger.of(context);
  return (String message, {G icon = G.check, ToastAction? action}) {
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            VIcon(icon, size: 18, color: c.acid, stroke: 2),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        action: action == null ? null : SnackBarAction(label: action.label, onPressed: action.onPressed),
        duration: const Duration(milliseconds: 2200),
      ),
    );
  };
}

void showToast(BuildContext context, String message, {G icon = G.check, ToastAction? action}) =>
    toaster(context)(message, icon: icon, action: action);

class _TopToast extends StatefulWidget {
  const _TopToast({required this.message, required this.icon, this.action, required this.onGone});

  final String message;
  final G icon;
  final ToastAction? action;
  final VoidCallback onGone;

  static OverlayEntry? _current;

  static void show(OverlayState overlay, String message, G icon, ToastAction? action) {
    if (_current?.mounted ?? false) _current!.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopToast(
        message: message,
        icon: icon,
        action: action,
        onGone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast> with SingleTickerProviderStateMixin {
  late final _show = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 240),
  )..forward();
  Timer? _timer;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    // Leave an Undo up long enough to reach the top of the screen for it.
    _timer = Timer(Duration(milliseconds: widget.action == null ? 2200 : 5000), _hide);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _show.dispose();
    super.dispose();
  }

  Future<void> _hide() async {
    _timer?.cancel();
    if (!mounted) return;
    await _show.reverse();
    widget.onGone();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    // Same capsule as the nav: ink on paper, lifted graphite in the dark.
    final capsule = context.isDark ? const Color(0xFF26262C) : c.ink;
    const fg = Color(0xFFF6F4EF);
    final t = context.type;
    final action = widget.action;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 6,
      left: Space.l,
      right: Space.l,
      child: Center(
        child: AnimatedBuilder(
          animation: _show,
          builder: (context, child) {
            final v = Curves.easeOutBack.transform(_show.value);
            return Transform.translate(
              offset: Offset(0, -80 * (1 - v) + _drag),
              child: Opacity(opacity: _show.value, child: child),
            );
          },
          // The overlay sits above the routes, so supply text defaults.
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(-60.0, 8.0)),
              onVerticalDragEnd: (d) {
                if (_drag < -16 || d.primaryVelocity! < -300) {
                  _hide();
                } else {
                  setState(() => _drag = 0);
                }
              },
              child: Semantics(
                liveRegion: true,
                container: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480, minHeight: 48),
                  child: Container(
                    padding: EdgeInsets.fromLTRB(16, 6, action == null ? 20 : 6, 6),
                    decoration: BoxDecoration(color: capsule, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VIcon(widget.icon, size: 18, color: c.acid, stroke: 2),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.item.copyWith(color: fg, fontSize: 14.5),
                          ),
                        ),
                        if (action != null)
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            minimumSize: Size.zero,
                            onPressed: () {
                              action.onPressed();
                              _hide();
                            },
                            child: Text(action.label, style: t.item.copyWith(color: c.acid, fontSize: 14.5)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  bool destructive = false,
}) async {
  if (context.isCupertino) {
    // HIG: Cancel on the left, and bold when the other choice destroys data.
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: destructive,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: !destructive,
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        Row(
          children: [
            Expanded(
              child: VButton(
                label: 'Cancel',
                kind: ButtonStyleKind.outline,
                height: 48,
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VButton(
                label: confirm,
                kind: destructive ? ButtonStyleKind.danger : ButtonStyleKind.ink,
                height: 48,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Lowercase serif wordmark with the lime keyhole dot.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 26});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'vaulty',
          style: TextStyle(
            fontFamily: 'InstrumentSerif',
            fontStyle: FontStyle.italic,
            fontSize: size,
            height: 1,
            color: c.ink,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: size * .06, bottom: size * .14),
          child: Container(
            width: size * .22,
            height: size * .22,
            decoration: BoxDecoration(
              color: c.acid,
              shape: BoxShape.circle,
              border: Border.all(color: c.ink, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}
