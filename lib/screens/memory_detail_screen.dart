import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/memory.dart';
import '../services/auth_service.dart';
import '../services/settings.dart';
import '../state/vault_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/encrypted_image.dart';
import '../widgets/glyphs.dart';
import '../widgets/mascot.dart';
import '../widgets/reminder_sheet.dart';
import '../widgets/renew_sheet.dart';
import '../widgets/tag_widgets.dart';
import 'memory_editor_screen.dart';

class MemoryDetailScreen extends ConsumerStatefulWidget {
  const MemoryDetailScreen({super.key, required this.memoryId});

  final String memoryId;

  @override
  ConsumerState<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends ConsumerState<MemoryDetailScreen> {
  bool _revealed = false;

  Memory? _find() {
    final live = ref.watch(memoryByIdProvider(widget.memoryId));
    if (live != null) return live;
    return ref.watch(archivedProvider).value?.where((m) => m.id == widget.memoryId).firstOrNull;
  }

  Future<void> _reveal() async {
    final ok = await AuthService.authenticate('Reveal this secret');
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      setState(() => _revealed = true);
    }
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    showToast(context, 'Copied', icon: G.copy);
  }

  Future<void> _more(Memory m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: ListGroup(
            children: [
              ListRow(
                title: m.isArchived ? 'Restore' : 'Archive',
                glyph: m.isArchived ? G.unarchive : G.archive,
                chevron: false,
                onTap: () => Navigator.pop(ctx, 'archive'),
              ),
              ListRow(
                title: 'Delete',
                glyph: G.trash,
                danger: true,
                chevron: false,
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    final notifier = ref.read(vaultProvider.notifier);
    final nav = Navigator.of(context);
    final toast = toaster(context);
    switch (action) {
      case 'archive':
        await notifier.setArchived(m.id, !m.isArchived);
        nav.pop();
        toast(m.isArchived ? 'Restored “${m.title}”' : 'Archived “${m.title}”', icon: G.archive);
      case 'delete':
        // No "are you sure?": deleting is undoable for a few seconds instead.
        nav.pop();
        await notifier.delete(m);
        toast(
          'Deleted “${m.title}”',
          icon: G.trash,
          action: SnackBarAction(label: 'Undo', onPressed: () => notifier.undoDelete(m.id)),
        );
    }
  }

  Future<void> _renew(Memory m) async {
    final date = await showRenewSheet(context, m);
    if (date == null || !mounted) return;
    final toast = toaster(context);
    await ref.read(vaultProvider.notifier).renew(m, date);
    toast('Renewed until ${DateFormat('d MMM yyyy').format(date)}', icon: G.check);
  }

  Future<void> _editReminders(Memory m) async {
    final defaults = ref.read(settingsProvider).reminders;
    final choice = await showReminderSheet(
      context,
      defaults: defaults,
      offsets: m.reminderOffsets,
      minutes: m.reminderMinutes,
      remind: m.remind,
      recurrence: m.recurrence,
    );
    if (choice == null || !mounted) return;
    await ref
        .read(vaultProvider.notifier)
        .save(
          m.copyWith(
            remind: choice.remind,
            reminderOffsets: choice.offsets,
            clearReminderOffsets: choice.offsets == null,
            reminderMinutes: choice.minutes,
            clearReminderMinutes: choice.minutes == null,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final m = _find();
    if (m == null) {
      return Scaffold(
        appBar: AppBar(
          leading: VIconButton(G.chevronLeft, label: 'Back', onTap: () => Navigator.pop(context)),
        ),
        body: const Center(
          child: EmptyState(title: 'Gone', subtitle: 'This memory no longer exists.', mood: MascotMood.wow),
        ),
      );
    }
    final hidden = m.isSensitive && !_revealed;
    // One reveal button is enough: put it on the first blurred section.
    final firstSecret = m.metadata.isNotEmpty ? 0 : (m.attachments.isNotEmpty ? 1 : 2);

    return Scaffold(
      appBar: AppBar(
        leading: VIconButton(G.chevronLeft, label: 'Back', onTap: () => Navigator.pop(context)),
        actions: [
          VIconButton(
            G.pen,
            label: 'Edit',
            onTap: () async {
              if (m.isSensitive && !_revealed) {
                await _reveal();
                if (!_revealed || !context.mounted) return;
              }
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemoryEditorScreen(initial: m)));
            },
          ),
          VIconButton(G.more, label: 'More', onTap: () => _more(m)),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, 48),
        children: [
          Row(
            children: [
              CategoryLabel.of(m),
              if (m.isSensitive) ...[
                const SizedBox(width: 12),
                VIcon(G.lock, size: 13, color: c.inkFaint, stroke: 1.9),
                const SizedBox(width: 4),
                Text('SECRET', style: context.type.eyebrow),
              ],
              if (m.isArchived) ...[const SizedBox(width: 12), Text('ARCHIVED', style: context.type.eyebrow)],
            ],
          ),
          const SizedBox(height: 12),
          Text(m.title, style: context.type.display.copyWith(fontSize: 38)),
          if (m.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final t in m.tags) TagChip(tag: t, onTap: () => openTag(context, t))],
            ),
          ],
          if (m.hasExpiry) ...[
            const SizedBox(height: 24),
            _Countdown(memory: m, onRenew: m.isRecurring || m.isArchived ? null : () => _renew(m)),
          ],
          if (m.metadata.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Eyebrow('Details'),
            const SizedBox(height: 10),
            _Secret(
              hidden: hidden,
              onReveal: _reveal,
              showButton: firstSecret == 0,
              child: VCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < m.metadata.length; i++) ...[
                      if (i > 0) const Hairline(indent: 18),
                      _DetailRow(entry: m.metadata[i], onCopy: hidden ? null : () => _copy(m.metadata[i].value)),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (m.attachments.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Eyebrow('Photos'),
            const SizedBox(height: 10),
            _Secret(
              hidden: hidden,
              onReveal: _reveal,
              showButton: firstSecret == 1,
              child: SizedBox(
                height: 140,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: m.attachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: hidden ? null : () => openImageViewer(context, m.attachments[i]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.m),
                      child: SizedBox(width: 140, child: EncryptedImage(attachment: m.attachments[i])),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (m.rawContent.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Eyebrow('Notes'),
            const SizedBox(height: 10),
            _Secret(
              hidden: hidden,
              onReveal: _reveal,
              showButton: firstSecret == 2,
              child: VCard(child: SelectableText(m.rawContent, style: context.type.body)),
            ),
          ],
          if (m.hasExpiry && !m.isArchived) ...[
            const SizedBox(height: 28),
            Row(
              children: [
                const Expanded(child: Eyebrow('Reminders')),
                Pressable(
                  onTap: () => _editReminders(m),
                  semanticLabel: 'Edit reminders',
                  child: Text(
                    'Edit',
                    style: context.type.caption.copyWith(color: c.brand, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(m.reminderSummary(ref.watch(settingsProvider).reminders), style: context.type.caption),
            const SizedBox(height: 10),
            if (m.remind) _Reminders(memoryId: m.id),
          ],
          const SizedBox(height: 32),
          Row(
            children: [
              VIcon(G.shield, size: 14, color: c.inkFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Encrypted on this phone  ·  added ${DateFormat('d MMM yyyy').format(m.createdAt)}',
                  style: context.type.caption.copyWith(color: c.inkFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.memory, this.onRenew});

  final Memory memory;

  /// Shown for one-off dates: a one-tap renewal instead of editing.
  final VoidCallback? onRenew;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final days = memory.daysLeft!;
    final u = memory.urgency!;
    final color = u == Urgency.chill ? c.ink : u.color(c);
    final span = memory.recurrence == Recurrence.monthly ? 31 : 365;
    final progress = days < 0 ? 1.0 : (1 - days / span).clamp(0.02, 1.0);
    final next = memory.nextDate!;
    return VCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${days.abs()}', style: context.type.numeral(72, color)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  days < 0 ? 'days overdue' : memory.countdownUnit,
                  style: context.type.item.copyWith(color: c.inkSoft, fontWeight: FontWeight.w500),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: VIcon(memory.dateGlyph, size: 22, color: color),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: c.sunken, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            [
              if (memory.isRecurring && !memory.isOccasion)
                'Renews'
              else if (!memory.isRecurring)
                (days < 0 ? 'Expired' : 'Expires'),
              DateFormat('EEEE, d MMMM yyyy').format(next),
            ].join(' '),
            style: context.type.body,
          ),
          if (memory.isRecurring) ...[
            const SizedBox(height: 2),
            Text(
              ['Repeats ${memory.recurrence.label.toLowerCase()}', ?memory.milestone].join('  ·  '),
              style: context.type.caption,
            ),
          ],
          if (onRenew != null) ...[
            const SizedBox(height: 16),
            VButton(
              label: 'Renewed it',
              icon: G.repeat,
              height: 46,
              // Loud when it matters (lapsed or soon), quiet otherwise.
              kind: days <= 60 ? ButtonStyleKind.ink : ButtonStyleKind.outline,
              onPressed: onRenew,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.entry, required this.onCopy});

  final MetaEntry entry;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Pressable(
      onTap: onCopy,
      scale: .99,
      semanticLabel: '${entry.key}, ${entry.value}. Tap to copy',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key, style: context.type.caption),
                  const SizedBox(height: 4),
                  Text(entry.value.isEmpty ? '—' : entry.value, style: context.type.mono(19)),
                ],
              ),
            ),
            if (onCopy != null) VIcon(G.copy, size: 18, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Blurs its child until the user passes biometric auth.
class _Secret extends StatelessWidget {
  const _Secret({required this.hidden, required this.onReveal, required this.child, this.showButton = true});

  final bool hidden;
  final VoidCallback onReveal;
  final Widget child;
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    if (!hidden) return child;
    final c = context.vc;
    return Stack(
      alignment: Alignment.center,
      children: [
        ExcludeSemantics(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: IgnorePointer(child: child),
          ),
        ),
        if (showButton)
          Pressable(
            onTap: onReveal,
            semanticLabel: 'Reveal hidden details',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VIcon(G.eye, size: 17, color: c.onInk),
                  const SizedBox(width: 8),
                  Text('Reveal', style: context.type.button.copyWith(color: c.onInk, fontSize: 14)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Reminders extends ConsumerWidget {
  const _Reminders({required this.memoryId});

  final String memoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vc;
    final reminders = ref.watch(remindersProvider(memoryId));
    final items = reminders.value ?? const <Reminder>[];
    if (!reminders.hasValue) {
      return Text('Checking…', style: context.type.caption);
    }
    if (items.isEmpty) {
      return VCard(
        child: Text('No upcoming reminders. The date may be too close or already past.', style: context.type.bodySoft),
      );
    }
    return VCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Hairline(indent: 52),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
              child: Row(
                children: [
                  VIcon(G.bell, size: 18, color: c.inkSoft),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(DateFormat('EEE d MMM yyyy').format(items[i].scheduledFor), style: context.type.body),
                  ),
                  Text(
                    items[i].offsetDays == 0 ? 'on the day' : '${items[i].offsetDays}d before',
                    style: context.type.mono(12.5, c.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
