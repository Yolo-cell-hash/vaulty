import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/settings.dart';
import '../state/vault_state.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/mascot.dart';
import '../widgets/nav_bar.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _includePhotos = true;
  String? _busy;

  Future<T> _working<T>(String label, Future<T> Function() job) async {
    setState(() => _busy = label);
    try {
      return await job();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ---------------------------------------------------------------- export --

  Future<void> _export() async {
    if (!await AuthService.authenticate('Back up your vault')) return;
    if (!mounted) return;
    final passphrase = await _askPassphrase(context, creating: true);
    if (passphrase == null || !mounted) return;
    final toast = toaster(context);
    try {
      final memories = await ref.read(vaultProvider.notifier).snapshot();
      final bytes = await _working(
        'Encrypting ${memories.length} memories',
        () => VaultBackup.export(memories: memories, passphrase: passphrase, includePhotos: _includePhotos),
      );
      final saved = await AuthService.guardExternal(
        () => FilePicker.saveFile(
          fileName: VaultBackup.suggestedFileName(DateTime.now()),
          bytes: bytes,
          dialogTitle: 'Save your Vaulty backup',
        ),
      );
      if (saved == null) return;
      Haptics.success();
      await ref.read(settingsProvider.notifier).change((s) => s.copyWith(lastBackup: DateTime.now()));
      toast('Backup saved. Keep the passphrase somewhere safe.', icon: G.shield);
    } on Object catch (e) {
      toast('Backup failed: $e', icon: G.warning);
    }
  }

  // --------------------------------------------------------------- restore --

  Future<void> _restore() async {
    final picked = await AuthService.guardExternal(
      () => FilePicker.pickFile(dialogTitle: 'Pick a .vault backup', type: FileType.any),
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.xFile.readAsBytes();
    if (!mounted) return;
    final toast = toaster(context);

    BackupContents? contents;
    var error = '';
    while (contents == null) {
      final passphrase = await _askPassphrase(context, creating: false, error: error);
      if (passphrase == null || !mounted) return;
      try {
        contents = await _working('Unlocking backup', () => VaultBackup.open(bytes, passphrase));
      } on BackupException catch (e) {
        Haptics.error();
        if (!e.message.startsWith('Wrong')) {
          toast(e.message, icon: G.warning);
          return;
        }
        error = e.message;
      }
      if (!mounted) return;
    }

    final found = contents;
    final ok = await confirmDialog(
      context,
      title: 'Restore this backup?',
      message:
          '${found.memories.length} memories and ${found.photoCount} photos from '
          '${DateFormat('d MMM yyyy, HH:mm').format(found.exportedAt)}.\n\n'
          'They’ll be merged in. Where something exists in both, the most recently edited copy wins.',
      confirm: 'Restore',
    );
    if (!ok || !mounted) return;
    try {
      final summary = await _working('Restoring', () => ref.read(vaultProvider.notifier).restore(found));
      if (!mounted) return;
      Haptics.success();
      final rows = [
        _SummaryRow(label: 'Added', value: summary.added),
        _SummaryRow(label: 'Updated', value: summary.updated),
        _SummaryRow(label: 'Kept (yours were newer)', value: summary.skipped),
      ];
      await (context.isCupertino
          ? showCupertinoDialog<void>(
              context: context,
              builder: (ctx) => CupertinoAlertDialog(
                title: const Text('Welcome back'),
                content: Column(
                  children: [
                    const Mascot(size: 72, mood: MascotMood.grin, prop: MascotProp.check, animate: false),
                    const SizedBox(height: 8),
                    ...rows,
                  ],
                ),
                actions: [
                  CupertinoDialogAction(
                    isDefaultAction: true,
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ],
              ),
            )
          : showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                icon: const Mascot(size: 84, mood: MascotMood.grin, prop: MascotProp.check, animate: false),
                title: const Text('Welcome back', textAlign: TextAlign.center),
                content: Column(mainAxisSize: MainAxisSize.min, children: rows),
                actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                actions: [VButton(label: 'Done', height: 48, onPressed: () => Navigator.pop(ctx))],
              ),
            ));
    } on Object catch (e) {
      toast('Restore failed: $e', icon: G.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final lastBackup = ref.watch(settingsProvider.select((s) => s.lastBackup));
    final count = (ref.watch(vaultProvider).value ?? const []).length;

    return PopScope(
      canPop: _busy == null,
      child: Stack(
        children: [
          Scaffold(
            appBar: vAppBar(
              context,
              leading: VIconButton(G.chevronLeft, label: 'Back', onTap: () => Navigator.pop(context)),
              largeTitle: 'Backup',
            ),
            body: ListView(
              padding: context.pageInsets + const EdgeInsets.fromLTRB(Space.page, 4, Space.page, 40),
              children: [
                Text('Backup', style: context.type.display),
                const SizedBox(height: 8),
                Text(
                  'One encrypted file, sealed with a passphrase only you know. Keep it in Files, iCloud Drive, '
                  'Google Drive or on a USB stick. Without the passphrase it’s unreadable.',
                  style: context.type.bodySoft,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: lastBackup == null ? c.warn : c.ok, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      lastBackup == null ? 'No backup yet' : 'Last backup ${_ago(lastBackup)}',
                      style: context.type.caption.copyWith(color: c.ink, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Eyebrow('Create'),
                const SizedBox(height: 10),
                VCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Everything in one .vault file', style: context.type.item),
                      const SizedBox(height: 4),
                      Text('All $count memories, archived ones included.', style: context.type.caption),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: Text('Include photos', style: context.type.body)),
                          Switch.adaptive(value: _includePhotos, onChanged: (v) => setState(() => _includePhotos = v)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      VButton(label: 'Create backup', icon: G.upload, onPressed: count == 0 ? null : _export),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Eyebrow('Restore'),
                const SizedBox(height: 10),
                VCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bring a backup back', style: context.type.item),
                      const SizedBox(height: 4),
                      Text('Merges into this phone. Nothing here gets deleted.', style: context.type.caption),
                      const SizedBox(height: 16),
                      VButton(
                        label: 'Choose a file',
                        icon: G.download,
                        kind: ButtonStyleKind.outline,
                        onPressed: _restore,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'AES-256-GCM  ·  PBKDF2-SHA256, ${NumberFormat.compact().format(VaultBackup.defaultIterations)} rounds  ·  made on this phone',
                  style: context.type.mono(11, c.inkFaint),
                ),
              ],
            ),
          ),
          if (_busy != null) Positioned.fill(child: _BusyOverlay(label: _busy!)),
        ],
      ),
    );
  }

  static String _ago(DateTime d) {
    final days = DateUtils.dateOnly(DateTime.now()).difference(DateUtils.dateOnly(d)).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 30) return '$days days ago';
    return 'on ${DateFormat('d MMM yyyy').format(d)}';
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        // In an iOS alert, the alert's own type; in the Material dialog, ours.
        Expanded(
          child: Text(label, textAlign: TextAlign.start, style: context.isCupertino ? null : context.type.body),
        ),
        Text('$value', style: context.type.mono(15)),
      ],
    ),
  );
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Material(
      color: c.bg.withValues(alpha: .94),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Mascot(size: 120, prop: MascotProp.key),
            const SizedBox(height: 18),
            Text(label, style: context.type.headline.copyWith(fontSize: 24)),
            const SizedBox(height: 16),
            if (context.isCupertino)
              const Spinner()
            else
              SizedBox(
                width: 140,
                child: LinearProgressIndicator(minHeight: 2, color: c.ink, backgroundColor: c.line),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a passphrase; when [creating], asks twice and shows strength.
Future<String?> _askPassphrase(BuildContext context, {required bool creating, String error = ''}) {
  return showVSheet<String>(
    context,
    (_) => _PassphraseSheet(creating: creating, error: error),
    isScrollControlled: true,
  );
}

class _PassphraseSheet extends StatefulWidget {
  const _PassphraseSheet({required this.creating, required this.error});

  final bool creating;
  final String error;

  @override
  State<_PassphraseSheet> createState() => _PassphraseSheetState();
}

class _PassphraseSheetState extends State<_PassphraseSheet> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  int get _score {
    final p = _pass.text;
    var s = 0;
    if (p.length >= VaultBackup.minPassphraseLength) s++;
    if (p.length >= 14) s++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) s++;
    if (RegExp(r'\d').hasMatch(p)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s;
  }

  String? get _problem {
    if (_pass.text.length < VaultBackup.minPassphraseLength) {
      return 'At least ${VaultBackup.minPassphraseLength} characters';
    }
    if (widget.creating && _confirm.text != _pass.text) return 'Passphrases don’t match';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final score = _score;
    final (label, color) = switch (score) {
      <= 1 => ('Weak', c.danger),
      2 => ('Fair', c.warn),
      3 => ('Strong', c.ok),
      _ => ('Very strong', c.ok),
    };
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      suffixIcon: VIconButton(
        _obscure ? G.eye : G.eyeOff,
        label: _obscure ? 'Show' : 'Hide',
        size: 40,
        color: c.inkSoft,
        onTap: () => setState(() => _obscure = !_obscure),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.creating ? 'Choose a passphrase' : 'Enter the passphrase',
              style: context.type.headline.copyWith(fontSize: 26),
            ),
            const SizedBox(height: 6),
            Text(
              widget.creating
                  ? 'You’ll need it to restore. Forget it and nobody can open this backup, including us.'
                  : 'The one you chose when you made this backup.',
              style: context.type.bodySoft,
            ),
            if (widget.error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  VIcon(G.warning, size: 16, color: c.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.error, style: context.type.caption.copyWith(color: c.danger)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _pass,
              autofocus: true,
              obscureText: _obscure,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              style: context.type.body,
              decoration: deco('Passphrase'),
            ),
            if (widget.creating) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Container(
                        height: 3,
                        margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                        decoration: BoxDecoration(
                          color: _pass.text.isNotEmpty && i < score.clamp(1, 4) ? color : c.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _pass.text.isEmpty ? 'A few random words beat one clever word.' : label,
                style: context.type.caption.copyWith(color: _pass.text.isEmpty ? c.inkFaint : color),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                enableSuggestions: false,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                style: context.type.body,
                decoration: deco('Type it again'),
              ),
            ],
            const SizedBox(height: 8),
            if (_pass.text.isNotEmpty && _problem != null) Text(_problem!, style: context.type.caption),
            const SizedBox(height: 14),
            VButton(
              label: widget.creating ? 'Encrypt and save' : 'Unlock backup',
              icon: widget.creating ? G.lock : G.unlock,
              onPressed: _problem == null ? () => Navigator.pop(context, _pass.text) : null,
            ),
          ],
        ),
      ),
    );
  }
}
