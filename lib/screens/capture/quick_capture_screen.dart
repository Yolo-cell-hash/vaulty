import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/memory.dart';
import '../../services/settings.dart';
import '../../services/smart_parser.dart';
import '../../state/vault_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/memory_cards.dart';
import '../../widgets/tag_widgets.dart';
import '../memory_editor_screen.dart';
import 'draft.dart';

class QuickCaptureScreen extends ConsumerStatefulWidget {
  const QuickCaptureScreen({super.key, this.initialText = '', this.cursorAtStart = false});

  final String initialText;

  /// Put the caret before the prefilled text (used for "#tag" prefills).
  final bool cursorAtStart;

  @override
  ConsumerState<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends ConsumerState<QuickCaptureScreen> {
  late final _controller = TextEditingController(text: widget.initialText)
    ..selection = TextSelection.collapsed(offset: widget.cursorAtStart ? 0 : widget.initialText.length);
  late final List<Tag> _known = ref.read(tagsProvider).value ?? const [];
  late final _parser = deviceParser(known: _known);
  late ParsedCapture _parsed = _parser.parseText(widget.initialText);
  bool _saving = false;

  /// Prefills from a person/tag page want the keyboard up; examples don't.
  bool get _autofocus => widget.initialText.isEmpty || widget.cursorAtStart || widget.initialText.endsWith(' ');

  static const _examples = [
    'Passport expires 15 Mar 2031, no K1234567',
    "Dad's waist 34 in, shirt size L",
    'Spotify ₹119/mo renews on the 20th',
    'Home wifi password is sunshine22',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) => setState(() => _parsed = _parser.parseText(text));

  Future<void> _save() async {
    if (_parsed.isEmpty || _saving) return;
    setState(() => _saving = true);
    await ref.read(vaultProvider.notifier).save(memoryFromParsed(_parsed, known: _known));
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    final toast = toaster(context);
    Navigator.of(context).pop();
    toast('Saved “${_parsed.title}”');
  }

  void _fineTune() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MemoryEditorScreen(initial: memoryFromParsed(_parsed, known: _known), isNew: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final hasText = _controller.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        leading: VIconButton(G.close, label: 'Close', onTap: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, 20),
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Just '),
                        TextSpan(text: 'say it.', style: context.type.accent),
                      ],
                    ),
                    style: context.type.display.copyWith(fontSize: 36),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    autofocus: _autofocus,
                    minLines: 3,
                    maxLines: 6,
                    onChanged: _onChanged,
                    textCapitalization: TextCapitalization.sentences,
                    style: context.type.body.copyWith(fontSize: 19, height: 1.4),
                    decoration: InputDecoration(
                      hintText: 'Car insurance expires Nov 12, Policy #9812',
                      hintStyle: context.type.body.copyWith(fontSize: 19, height: 1.4, color: c.inkFaint),
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dates, sizes, codes, people like “Mom’s” and #tags are picked up. Tap the keyboard mic to talk.',
                    style: context.type.caption.copyWith(color: c.inkFaint),
                  ),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: hasText ? _preview() : _examplesList(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: VButton(
                      label: 'Edit details',
                      kind: ButtonStyleKind.outline,
                      onPressed: hasText ? _fineTune : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: VButton(label: 'Save', busy: _saving, onPressed: hasText && !_parsed.isEmpty ? _save : null),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _examplesList() {
    final c = context.vc;
    return Column(
      key: const ValueKey('examples'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('For example'),
        const SizedBox(height: 12),
        for (final e in _examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Pressable(
              onTap: () {
                _controller.text = e;
                _controller.selection = TextSelection.collapsed(offset: e.length);
                _onChanged(e);
              },
              child: Row(
                children: [
                  VIcon(G.arrowUpRight, size: 15, color: c.inkFaint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(e, style: context.type.body.copyWith(color: c.inkSoft)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _preview() {
    final c = context.vc;
    final p = _parsed;
    final draft = memoryFromParsed(p, known: _known);
    return Column(
      key: const ValueKey('preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Understood as'),
        const SizedBox(height: 12),
        VCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryLabel.of(draft, size: 13),
                  const Spacer(),
                  if (p.isSensitive) ...[
                    VIcon(G.lock, size: 13, color: c.inkFaint, stroke: 1.9),
                    const SizedBox(width: 4),
                    Text('SECRET', style: context.type.eyebrow),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(p.title.isEmpty ? 'Untitled' : p.title, style: context.type.headline.copyWith(fontSize: 24)),
              if (draft.hasExpiry) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    CountdownTag(memory: draft),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        [dateFmt.format(draft.nextDate!), ?draft.milestone].join('  ·  '),
                        style: context.type.caption,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  draft.reminderSummary(ref.watch(settingsProvider).reminders),
                  style: context.type.caption.copyWith(color: c.inkFaint),
                ),
              ],
              if (draft.tags.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final t in draft.tags) TagChip(tag: t, dense: true)]),
              ],
              if (p.fields.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Hairline(),
                for (final (k, v) in p.fields)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        SizedBox(width: 110, child: Text(k, style: context.type.caption)),
                        Expanded(child: Text(p.isSensitive ? '••••••' : v, style: context.type.mono(15))),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
