import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/memory.dart';
import '../services/attachment_store.dart';
import '../services/ocr_service.dart';
import '../services/settings.dart';
import '../state/vault_state.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import '../widgets/encrypted_image.dart';
import '../widgets/flow_sheet.dart';
import '../widgets/glyphs.dart';
import '../widgets/memory_cards.dart';
import '../widgets/reminder_sheet.dart';
import '../widgets/tag_widgets.dart';
import 'capture/draft.dart';

class _MetaRow {
  _MetaRow(this.id, String key, String value)
    : key = TextEditingController(text: key),
      value = TextEditingController(text: value);

  final String id;
  final TextEditingController key;
  final TextEditingController value;

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

class MemoryEditorScreen extends ConsumerStatefulWidget {
  const MemoryEditorScreen({super.key, required this.initial, this.isNew = false, this.notice});

  final Memory initial;
  final bool isNew;
  final String? notice;

  @override
  ConsumerState<MemoryEditorScreen> createState() => _MemoryEditorScreenState();
}

class _MemoryEditorScreenState extends ConsumerState<MemoryEditorScreen> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _notes = TextEditingController(text: widget.initial.rawContent);
  late MemoryCategory _category = widget.initial.category;
  late DateTime? _expiry = widget.initial.expiryDate;
  late Recurrence _recurrence = widget.initial.recurrence;
  late bool _remind = widget.initial.remind;
  late List<int>? _reminderOffsets = widget.initial.reminderOffsets;
  late int? _reminderMinutes = widget.initial.reminderMinutes;
  late bool _sensitive = widget.initial.isSensitive;
  late final List<_MetaRow> _rows = [for (final e in widget.initial.metadata) _MetaRow(e.id, e.key, e.value)];
  late final List<Attachment> _attachments = [...widget.initial.attachments];
  late final List<Tag> _tags = [...widget.initial.tags];

  /// Photos encrypted during this edit session (not yet in the database).
  late final List<Attachment> _created = [if (widget.isNew) ...widget.initial.attachments];
  bool _dirty = false;
  bool _saving = false;

  static const _suggestedKeys = <MemoryCategory, List<String>>{
    MemoryCategory.staticFact: ['Brand', 'Color', 'Code', 'Model', 'Password'],
    MemoryCategory.expiryDoc: ['Policy #', 'Passport #', 'License #', 'Issued by', 'Phone'],
    MemoryCategory.subscription: ['Price', 'Plan', 'Account', 'Billing'],
    MemoryCategory.measurement: ['Size', 'Brand', 'Waist', 'Length', 'Width'],
    MemoryCategory.other: ['Note', 'Where', 'Who'],
  };

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// Something here would be lost by closing: an edit, or a new item's photos.
  bool get _unsaved => _dirty || (widget.isNew && _attachments.isNotEmpty);

  Future<bool> _confirmDiscard() async {
    if (!_unsaved) return true;
    final ok = await confirmDialog(
      context,
      title: 'Discard changes?',
      message: 'What you’ve typed here won’t be saved.',
      confirm: 'Discard',
      destructive: true,
    );
    if (ok) {
      for (final a in _created) {
        await AttachmentStore.remove(a);
      }
    }
    return ok;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await pickDate(
      context,
      initial: _expiry ?? now.add(const Duration(days: 30)),
      first: DateTime(now.year - 100),
      last: DateTime(now.year + 50),
      title: 'Pick a date',
    );
    if (picked != null) {
      HapticFeedback.selectionClick();
      setState(() => _expiry = picked);
      _touch();
    }
  }

  Future<void> _addPhoto() async {
    final source = context.isCupertino
        ? await showActionSheet<ImageSource>(context, [
            ('Take a photo', ImageSource.camera),
            ('Choose from library', ImageSource.gallery),
          ])
        : await showModalBottomSheet<ImageSource>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
                child: ListGroup(
                  children: [
                    ListRow(title: 'Take a photo', glyph: G.scan, onTap: () => Navigator.pop(ctx, ImageSource.camera)),
                    ListRow(
                      title: 'Choose from library',
                      glyph: G.image,
                      onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                    ),
                  ],
                ),
              ),
            ),
          );
    if (source == null) return;
    final file = await OcrService.pickImage(source);
    if (file == null) return;
    final a = await AttachmentStore.importFile(file);
    if (!mounted) return;
    _created.add(a);
    setState(() => _attachments.add(a));
    _touch();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showToast(context, 'Give it a name first', icon: G.pen);
      return;
    }
    setState(() => _saving = true);
    final meta = <MetaEntry>[
      for (final r in _rows)
        if (r.key.text.trim().isNotEmpty || r.value.text.trim().isNotEmpty)
          MetaEntry(
            id: r.id,
            key: r.key.text.trim().isEmpty ? 'Detail' : r.key.text.trim(),
            value: r.value.text.trim(),
          ),
    ];
    final memory = widget.initial.copyWith(
      title: title,
      rawContent: _notes.text.trim(),
      category: _category,
      isSensitive: _sensitive,
      expiryDate: _expiry,
      clearExpiry: _expiry == null,
      recurrence: _expiry == null ? Recurrence.none : _recurrence,
      remind: _remind,
      reminderOffsets: _reminderOffsets,
      clearReminderOffsets: _reminderOffsets == null,
      reminderMinutes: _reminderMinutes,
      clearReminderMinutes: _reminderMinutes == null,
      metadata: meta,
      attachments: _attachments,
      tags: _tags,
    );
    await ref.read(vaultProvider.notifier).save(memory);
    for (final a in _created.where((a) => !_attachments.contains(a))) {
      await AttachmentStore.remove(a);
    }
    if (!mounted) return;
    Haptics.success();
    final toast = toaster(context);
    closeFlow(context);
    toast(widget.isNew ? 'Saved “$title”' : 'Updated “$title”');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) closeFlow(context);
      },
      child: DismissGuard(
        locked: _unsaved,
        child: Scaffold(
          appBar: AppBar(
            leading: VIconButton(G.close, label: 'Close', onTap: () => Navigator.of(context).maybePop()),
            title: Text(widget.isNew ? 'New memory' : 'Edit'),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(Space.page, 4, Space.page, 24),
                    children: [
                      if (widget.notice != null) ...[
                        VCard(
                          color: c.warnSoft,
                          child: Row(
                            children: [
                              VIcon(G.info, size: 18, color: c.warn),
                              const SizedBox(width: 12),
                              Expanded(child: Text(widget.notice!, style: context.type.body)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _title,
                        onChanged: (_) => _touch(),
                        textCapitalization: TextCapitalization.sentences,
                        style: context.type.headline.copyWith(fontSize: 32),
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: 'What is it?',
                          hintStyle: context.type.headline.copyWith(fontSize: 32, color: c.inkFaint),
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const _Label('Type'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final cat in MemoryCategory.values)
                            VChip(
                              label: cat.label,
                              icon: cat.glyph,
                              selected: cat == _category,
                              onTap: () {
                                setState(() => _category = cat);
                                _touch();
                              },
                            ),
                        ],
                      ),
                      const _Label('Who & tags'),
                      _tagsSection(),
                      const _Label('Date'),
                      _dateSection(),
                      const _Label('Details'),
                      _detailsSection(),
                      const _Label('Photos'),
                      _photos(),
                      const _Label('Notes'),
                      TextField(
                        controller: _notes,
                        onChanged: (_) => _touch(),
                        minLines: 3,
                        maxLines: 8,
                        style: context.type.body,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(hintText: 'Anything else worth remembering'),
                      ),
                      const SizedBox(height: 20),
                      VCard(
                        padding: EdgeInsets.zero,
                        child: ListRow(
                          title: 'Keep it secret',
                          subtitle: 'Blurred until you unlock with your face or fingerprint',
                          glyph: G.lock,
                          chevron: false,
                          trailing: Switch.adaptive(
                            value: _sensitive,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _sensitive = v);
                              _touch();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, 12),
                  child: VButton(
                    label: widget.isNew ? 'Save to vault' : 'Save changes',
                    busy: _saving,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tagsSection() {
    Future<void> add(TagKind kind) async {
      final t = await pickTag(context, kind: kind, exclude: _tags);
      if (t == null || _tags.any((e) => e.sameAs(t))) return;
      setState(() => _tags.add(t));
      _touch();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in _tags)
          TagChip(
            tag: t,
            onRemove: () {
              setState(() => _tags.remove(t));
              _touch();
            },
          ),
        VChip(label: 'Person', icon: G.plus, onTap: () => add(TagKind.person)),
        VChip(label: 'Tag', icon: G.plus, onTap: () => add(TagKind.tag)),
      ],
    );
  }

  Widget _dateSection() {
    final c = context.vc;
    final e = _expiry;
    final preview = e == null
        ? null
        : widget.initial.copyWith(
            expiryDate: e,
            recurrence: _recurrence,
            title: _title.text,
            rawContent: _notes.text,
            remind: _remind,
            reminderOffsets: _reminderOffsets,
            clearReminderOffsets: _reminderOffsets == null,
            reminderMinutes: _reminderMinutes,
            clearReminderMinutes: _reminderMinutes == null,
          );
    final defaults = ref.watch(settingsProvider).reminders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VCard(
          onTap: _pickDate,
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              VIcon(preview?.dateGlyph ?? G.calendar, size: 21, color: c.inkSoft),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e == null ? 'Add a date' : dateFmt.format(e), style: context.type.item),
                    const SizedBox(height: 2),
                    Text(
                      e == null ? 'Expiry, renewal, birthday…' : 'Tap to change the date',
                      style: context.type.caption,
                    ),
                  ],
                ),
              ),
              if (preview != null) CountdownTag(memory: preview, compact: true),
              if (e != null)
                VIconButton(
                  G.close,
                  label: 'Remove date',
                  size: 36,
                  color: c.inkFaint,
                  onTap: () {
                    setState(() {
                      _expiry = null;
                      _recurrence = Recurrence.none;
                    });
                    _touch();
                  },
                ),
            ],
          ),
        ),
        if (e != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Repeats', style: context.type.caption),
              const SizedBox(width: 12),
              for (final r in Recurrence.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: VChip(
                    label: r.label,
                    selected: _recurrence == r,
                    onTap: () {
                      setState(() => _recurrence = r);
                      _touch();
                    },
                  ),
                ),
            ],
          ),
          if (preview?.milestone != null) ...[
            const SizedBox(height: 8),
            Text(
              'Next one: ${dateFmt.format(preview!.nextDate!)}  ·  ${preview.milestone}',
              style: context.type.caption,
            ),
          ],
          const SizedBox(height: 12),
          VCard(
            padding: EdgeInsets.zero,
            child: ListRow(
              title: 'Reminders',
              subtitle: preview!.reminderSummary(defaults),
              glyph: _remind ? G.bell : G.eyeOff,
              onTap: () async {
                final choice = await showReminderSheet(
                  context,
                  defaults: defaults,
                  offsets: _reminderOffsets,
                  minutes: _reminderMinutes,
                  remind: _remind,
                  recurrence: _recurrence,
                );
                if (choice == null) return;
                setState(() {
                  _remind = choice.remind;
                  _reminderOffsets = choice.offsets;
                  _reminderMinutes = choice.minutes;
                });
                _touch();
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _detailsSection() {
    final c = context.vc;
    final used = _rows.map((r) => r.key.text.trim().toLowerCase()).toSet();
    final suggestions = (_suggestedKeys[_category] ?? const []).where((k) => !used.contains(k.toLowerCase()));
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 112,
                  child: TextField(
                    controller: r.key,
                    onChanged: (_) => _touch(),
                    style: context.type.caption.copyWith(color: c.ink, fontSize: 14),
                    decoration: deco('Label'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: r.value,
                    onChanged: (_) => _touch(),
                    style: context.type.mono(15),
                    decoration: deco('Value'),
                  ),
                ),
                VIconButton(
                  G.close,
                  label: 'Remove detail',
                  size: 36,
                  color: c.inkFaint,
                  onTap: () {
                    setState(() => _rows.remove(r));
                    _touch();
                  },
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            VChip(
              label: 'Detail',
              icon: G.plus,
              selected: true,
              onTap: () {
                setState(() => _rows.add(_MetaRow(newId(), '', '')));
                _touch();
              },
            ),
            for (final k in suggestions)
              VChip(
                label: k,
                onTap: () {
                  setState(() => _rows.add(_MetaRow(newId(), k, '')));
                  _touch();
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _photos() {
    final c = context.vc;
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final a in _attachments)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: () => openImageViewer(context, a),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.m),
                      child: SizedBox.square(dimension: 104, child: EncryptedImage(attachment: a)),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Pressable(
                      onTap: () {
                        setState(() => _attachments.remove(a));
                        _touch();
                      },
                      semanticLabel: 'Remove photo',
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const VIcon(G.close, size: 12, color: Colors.white, stroke: 2.2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Pressable(
            onTap: _addPhoto,
            semanticLabel: 'Add photo',
            child: Container(
              width: 104,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.m),
                border: Border.all(color: c.line, width: 1.2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  VIcon(G.plus, size: 22, color: c.inkSoft),
                  const SizedBox(height: 6),
                  Text('Add photo', style: context.type.caption),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: 26, bottom: 10), child: Eyebrow(text));
}
