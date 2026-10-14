import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/vault_database.dart';
import '../models/memory.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../services/notification_service.dart';
import '../services/review_service.dart';
import '../services/settings.dart';
import '../services/update_service.dart';
import '../state/vault_state.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/mascot.dart';
import '../widgets/memory_cards.dart';
import '../widgets/nav_bar.dart';
import '../widgets/reminder_sheet.dart';
import '../widgets/update_prompt.dart';
import 'backup_screen.dart';
import 'calendar_import_screen.dart';
import 'tag_screen.dart';

class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vc;
    final settings = ref.watch(settingsProvider);
    final items = ref.watch(vaultProvider).value ?? const [];
    final soon = ref.watch(radarProvider).where((m) => m.daysLeft! >= 0 && m.daysLeft! <= 30).length;
    final people = ref.watch(peopleProvider).length;
    final notifier = ref.read(settingsProvider.notifier);
    final name = settings.name.trim();
    // iOS names the unlock it actually has; Android copy stays generic.
    final ios = context.isCupertino;
    final biometric = ref.watch(biometricProvider).value ?? Biometric.faceId;
    final version = ref.watch(packageInfoProvider).value?.version;
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return ListView(
      padding:
          context.pageInsets + EdgeInsets.fromLTRB(Space.page, MediaQuery.paddingOf(context).top + 20, Space.page, 140),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                name.isEmpty ? 'You' : name,
                style: context.type.display,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            VIconButton(G.pen, label: 'Edit name', filled: true, onTap: () => _editName(context, ref, settings.name)),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            _Stat(value: items.length, label: 'Memories'),
            _Stat(value: soon, label: 'Due in 30 days'),
            _Stat(value: people, label: 'People'),
            _Stat(value: settings.streak, label: 'Day streak'),
          ],
        ),
        const SizedBox(height: 28),
        VCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  VIcon(G.shield, size: 20, color: c.ok),
                  const SizedBox(width: 10),
                  Text('Private by design', style: context.type.item),
                ],
              ),
              const SizedBox(height: 12),
              const _Check('AES-256 encrypted vault'),
              _Check('Keys held by ${Platform.isIOS ? 'the iOS Keychain' : 'Android Keystore'}'),
              const _Check('Reading, search and reminders run on this phone'),
              const _Check('No account, no cloud, no trackers'),
              if (!VaultDatabase.ftsAvailable)
                const _Check('Full-text index unavailable, using basic search', ok: false),
            ],
          ),
        ),
        const SizedBox(height: 28),
        ListGroup(
          header: 'Security',
          children: [
            ListRow(
              title: 'App lock',
              subtitle: !ios
                  ? 'Fingerprint or PIN to open'
                  : (biometric == Biometric.passcode ? 'Passcode to open' : '${biometric.label} or passcode to open'),
              glyph: ios ? biometric.glyph : G.fingerprint,
              chevron: false,
              trailing: Switch.adaptive(
                value: settings.lockEnabled,
                onChanged: (v) async {
                  final toast = toaster(context);
                  if (!await AuthService.isAvailable()) {
                    toast('Set up a screen lock on your phone first', icon: G.lock);
                    return;
                  }
                  final ok = await AuthService.authenticate(v ? 'Turn on app lock' : 'Turn off app lock');
                  if (!ok) return;
                  Haptics.success();
                  await notifier.change((s) => s.copyWith(lockEnabled: v));
                  if (v) ref.read(unlockedProvider.notifier).set(true);
                },
              ),
            ),
            ListRow(
              title: 'Backup',
              subtitle: settings.lastBackup == null ? 'No backup yet' : 'Last one ${_since(settings.lastBackup!)}',
              glyph: G.upload,
              onTap: () => push(const BackupScreen()),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ListGroup(
          header: 'Vault',
          children: [
            ListRow(title: 'People & tags', glyph: G.people, onTap: () => push(const ManageTagsScreen())),
            ListRow(title: 'Archived', glyph: G.archive, onTap: () => push(const _ArchivedScreen())),
            ListRow(
              title: 'Reminders',
              subtitle:
                  '${settings.reminderOffsets.map(offsetShort).join(', ')} · ${timeLabel(settings.reminderMinutes)}',
              glyph: G.bell,
              onTap: () async {
                final toast = toaster(context);
                final choice = await showReminderSheet(context, defaults: settings.reminders, forDefaults: true);
                if (choice == null) return;
                await notifier.change(
                  (s) => s.copyWith(
                    reminderOffsets: choice.offsets ?? s.reminderOffsets,
                    reminderMinutes: choice.minutes ?? s.reminderMinutes,
                  ),
                );
                final ok = await AuthService.guardExternal(NotificationService.requestPermission);
                toast(
                  ok ? 'Default reminders saved' : 'Saved. Turn on notifications for Vaulty in Settings',
                  icon: G.bell,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        ListGroup(
          header: 'Calendar',
          children: [
            ListRow(
              title: 'Show dates in my calendar',
              subtitle: settings.calendarSync
                  ? 'In a calendar called Vaulty, kept up to date'
                  : 'Titles and dates only, never the details',
              glyph: G.calendar,
              chevron: false,
              trailing: Switch.adaptive(
                value: settings.calendarSync,
                onChanged: (on) => _setCalendarSync(context, ref, on),
              ),
            ),
            ListRow(
              title: 'Import from calendar',
              subtitle: 'Birthdays, renewals and deadlines you already have',
              glyph: G.download,
              onTap: () => push(const CalendarImportScreen()),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ListGroup(
          header: 'Appearance',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  VIcon(G.sun, size: 21, color: c.inkSoft),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Theme', style: context.type.item.copyWith(fontWeight: FontWeight.w500)),
                  ),
                  _ThemePicker(
                    value: settings.themeMode,
                    onChanged: (m) => notifier.change((s) => s.copyWith(themeMode: m)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ListGroup(
          header: 'About',
          children: [
            ListRow(
              title: 'Rate Vaulty',
              subtitle: 'A review helps other people find it',
              glyph: G.star,
              onTap: () async {
                final toast = toaster(context);
                final opened = await ReviewService.openStorePage(learnedAppStoreId: settings.appStoreId);
                if (!opened) toast('Ratings open once Vaulty is in the App Store', icon: G.star);
              },
            ),
            ListRow(
              title: 'Check for updates',
              subtitle: version == null ? null : 'You have version $version',
              glyph: G.download,
              onTap: () => checkForUpdate(context, ref, manual: true),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ListGroup(
          children: [
            ListRow(
              title: 'Erase everything',
              subtitle: 'Deletes every memory and photo on this phone',
              glyph: G.trash,
              danger: true,
              onTap: () => _nuke(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 36),
        const Center(child: Wordmark(size: 22)),
        const SizedBox(height: 6),
        Center(
          child: Text(
            '${version == null ? '' : 'Version $version  ·  '}made without servers',
            style: context.type.caption.copyWith(color: c.inkFaint),
          ),
        ),
      ],
    );
  }

  static String _since(DateTime d) {
    final days = DateUtils.dateOnly(DateTime.now()).difference(DateUtils.dateOnly(d)).inDays;
    return days <= 0 ? 'today' : (days == 1 ? 'yesterday' : '$days days ago');
  }

  /// Turning on asks for calendar access, says where the calendar will sync
  /// if it isn't kept on the phone, then fills it. Turning off deletes it.
  Future<void> _setCalendarSync(BuildContext context, WidgetRef ref, bool on) async {
    final toast = toaster(context);
    final vault = ref.read(vaultProvider.notifier);
    final settings = ref.read(settingsProvider.notifier);
    if (!on) {
      try {
        await vault.stopCalendarSync();
        toast('Removed the Vaulty calendar', icon: G.calendar);
      } catch (e) {
        toast('Couldn’t remove the calendar: $e', icon: G.warning);
      }
      return;
    }
    if (!await CalendarService.requestAccess().catchError((Object _) => false)) {
      toast(
        'Allow calendar access for Vaulty in Settings',
        icon: G.calendar,
        action: const ToastAction('Settings', CalendarService.openSettings),
      );
      return;
    }
    final home = await CalendarService.home();
    if (!home.local) {
      if (!context.mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Sync with ${home.name}?',
        message:
            'Your phone keeps its calendars in ${home.name}, so the Vaulty calendar will sync there too. '
            'It holds titles and dates only. Details, numbers and photos stay in Vaulty.',
        confirm: 'Turn on',
      );
      if (!ok) return;
    }
    await settings.change((s) => s.copyWith(calendarSync: true));
    try {
      final count = await vault.syncCalendar();
      Haptics.success();
      toast(
        count == 0
            ? 'Calendar on. Dated items will show up there'
            : 'Added $count ${count == 1 ? 'date' : 'dates'} to your calendar',
        icon: G.calendar,
      );
    } catch (e) {
      await settings.change((s) => s.copyWith(calendarSync: false));
      toast('Couldn’t set up the calendar: $e', icon: G.warning);
    }
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    if (context.isCupertino) {
      final name = await showTextAlert(
        context,
        title: 'What should we call you?',
        initial: current,
        placeholder: 'Name or nickname',
        capitalization: TextCapitalization.words,
        maxLength: 24,
        allowEmpty: true,
      );
      if (name != null) await ref.read(settingsProvider.notifier).change((s) => s.copyWith(name: name.trim()));
      return;
    }
    final ctrl = TextEditingController(text: current);
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, MediaQuery.viewInsetsOf(ctx).bottom + 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What should we call you?', style: ctx.type.headline.copyWith(fontSize: 26)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 24,
                style: ctx.type.body,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Name or nickname', counterText: ''),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
              const SizedBox(height: 16),
              VButton(label: 'Save', onPressed: () => Navigator.pop(ctx, ctrl.text)),
            ],
          ),
        ),
      ),
    );
    if (name != null) {
      await ref.read(settingsProvider.notifier).change((s) => s.copyWith(name: name.trim()));
    }
  }

  Future<void> _nuke(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Erase everything?',
      message:
          'Every memory, photo and reminder will be permanently deleted from this phone. '
          'Only a .vault backup can bring it back, so make one first if you might want it.',
      confirm: 'Erase',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final toast = toaster(context);
    if (!await AuthService.authenticate('Confirm erasing your vault')) return;
    await ref.read(vaultProvider.notifier).nuke();
    ref.invalidate(vaultProvider);
    toast('Vault erased', icon: G.trash);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: context.type.numeral(34)),
          const SizedBox(height: 4),
          Text(label, style: context.type.caption.copyWith(fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check(this.text, {this.ok = true});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          VIcon(ok ? G.check : G.info, size: 16, color: ok ? c.ok : c.warn, stroke: 2.2),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.type.bodySoft.copyWith(fontSize: 14))),
        ],
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    const options = [
      (ThemeMode.light, G.sun, 'Light'),
      (ThemeMode.dark, G.moon, 'Dark'),
      (ThemeMode.system, G.phone, 'System'),
    ];
    if (context.isCupertino) {
      return CupertinoSlidingSegmentedControl<ThemeMode>(
        groupValue: value,
        onValueChanged: (m) {
          if (m != null) onChanged(m);
        },
        children: {
          for (final (mode, glyph, label) in options)
            mode: Semantics(
              label: '$label theme',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: VIcon(glyph, size: 16, color: value == mode ? c.ink : c.inkFaint),
              ),
            ),
        },
      );
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (mode, glyph, label) in options)
            Pressable(
              onTap: () => onChanged(mode),
              semanticLabel: '$label theme',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: value == mode ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: value == mode ? Border.all(color: c.line) : null,
                ),
                child: VIcon(glyph, size: 16, color: value == mode ? c.ink : c.inkFaint),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArchivedScreen extends ConsumerWidget {
  const _ArchivedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedProvider);
    final items = archived.value ?? const [];
    return Scaffold(
      appBar: vAppBar(
        context,
        leading: VIconButton(G.chevronLeft, label: 'Back', onTap: () => Navigator.pop(context)),
        largeTitle: 'Archived',
      ),
      body: ListView(
        padding: context.pageInsets + const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 4, Space.page, 20),
            child: Text('Archived', style: context.type.display.copyWith(fontSize: 36)),
          ),
          if (archived.isLoading && !archived.hasValue)
            const Center(child: Spinner())
          else if (items.isEmpty)
            const EmptyState(
              title: 'Nothing archived',
              subtitle: 'Swipe items away on the Radar to tuck them here.',
              mood: MascotMood.sleepy,
              prop: MascotProp.zzz,
              size: 100,
            )
          else
            MemoryList(items: items),
        ],
      ),
    );
  }
}
