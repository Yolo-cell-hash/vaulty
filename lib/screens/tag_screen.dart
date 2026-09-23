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
import '../widgets/tag_widgets.dart';
import 'capture/quick_capture_screen.dart';

/// Everything about one person ("Mom") or tag ("#car").
class TagScreen extends ConsumerStatefulWidget {
  const TagScreen({super.key, required this.tagId});

  final String tagId;

  @override
  ConsumerState<TagScreen> createState() => _TagScreenState();
}

class _TagScreenState extends ConsumerState<TagScreen> {
  late String _tagId = widget.tagId;

  Future<void> _rename(Tag tag) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RenameSheet(tag: tag),
    );
    if (name == null || !mounted) return;
    final toast = toaster(context);
    final survivor = await ref.read(vaultProvider.notifier).updateTag(Tag(id: tag.id, name: name, kind: tag.kind));
    if (!mounted) return;
    if (survivor != tag.id) {
      setState(() => _tagId = survivor);
      toast('Merged into $name', icon: G.people);
    }
  }

  Future<void> _delete(Tag tag) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove ${tag.label}?',
      message: 'Your memories stay. They just won’t be linked to ${tag.label} anymore.',
      confirm: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    await ref.read(vaultProvider.notifier).deleteTag(tag.id);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final tag = (ref.watch(tagsProvider).value ?? const <Tag>[]).where((t) => t.id == _tagId).firstOrNull;
    final items = (ref.watch(vaultProvider).value ?? const <Memory>[])
        .where((m) => m.tags.any((t) => t.id == _tagId))
        .toList();
    if (tag == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final dated = items.where((m) => m.hasExpiry).toList()..sort((a, b) => a.nextDate!.compareTo(b.nextDate!));
    final bank = items.where((m) => !m.hasExpiry).toList();

    return Scaffold(
      appBar: AppBar(
        leading: VIconButton(G.chevronLeft, label: 'Back', onTap: () => Navigator.pop(context)),
        actions: [
          VIconButton(G.pen, label: 'Rename', onTap: () => _rename(tag)),
          VIconButton(G.trash, label: 'Remove', color: c.danger, onTap: () => _delete(tag)),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 140),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.page, 4, Space.page, 0),
                child: Row(
                  children: [
                    if (tag.isPerson)
                      Monogram(tag: tag, size: 72, ring: true)
                    else
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c.line),
                        ),
                        alignment: Alignment.center,
                        child: VIcon(G.hash, size: 30, color: c.ink),
                      ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(tag.isPerson ? 'Person' : 'Tag'),
                          const SizedBox(height: 4),
                          Text(tag.name, style: context.type.display.copyWith(fontSize: 36)),
                          const SizedBox(height: 2),
                          Text(
                            '${items.length} ${items.length == 1 ? 'memory' : 'memories'}'
                            '${dated.isEmpty ? '' : '  ·  ${dated.length} with dates'}',
                            style: context.type.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (items.isEmpty)
                EmptyState(
                  title: 'Nothing here yet',
                  subtitle: tag.isPerson
                      ? 'Sizes, birthdays, the gift they loved. Keep it all here.'
                      : 'Add ${tag.label} to anything to group it here.',
                  mood: MascotMood.wink,
                  size: 100,
                ),
              if (dated.isNotEmpty) ...[const SectionHeader(title: 'Coming up'), MemoryList(items: dated)],
              if (bank.isNotEmpty) ...[const SectionHeader(title: 'Good to know'), MemoryGrid(items: bank)],
            ],
          ),
          Positioned(
            left: Space.page,
            right: Space.page,
            bottom: MediaQuery.paddingOf(context).bottom + 16,
            child: VButton(
              label: tag.isPerson ? 'Add something for ${tag.name}' : 'Add to ${tag.label}',
              icon: G.plus,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => QuickCaptureScreen(
                    initialText: tag.isPerson ? "${tag.name}'s " : ' #${tag.name}',
                    cursorAtStart: !tag.isPerson,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.tag});

  final Tag tag;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final _name = TextEditingController(text: widget.tag.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.tag.isPerson ? 'Rename person' : 'Rename tag',
              style: context.type.headline.copyWith(fontSize: 26),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: context.type.body,
              textCapitalization: widget.tag.isPerson ? TextCapitalization.words : TextCapitalization.none,
              decoration: const InputDecoration(hintText: 'Name'),
            ),
            const SizedBox(height: 8),
            Text('Use a name that already exists to merge the two.', style: context.type.caption),
            const SizedBox(height: 18),
            VButton(
              label: 'Save',
              onPressed: _name.text.trim().isEmpty
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      final raw = _name.text.trim().replaceAll(RegExp(r'^#'), '');
                      Navigator.pop(context, widget.tag.isPerson ? raw : raw.toLowerCase());
                    },
            ),
          ],
        ),
      ),
    );
  }
}

/// Every person and tag (from the You tab).
class ManageTagsScreen extends ConsumerWidget {
  const ManageTagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vc;
    final all = ref.watch(tagsProvider).value ?? const <Tag>[];
    final people = all.where((t) => t.isPerson).toList();
    final tags = all.where((t) => !t.isPerson).toList();

    ListRow row(Tag t) => ListRow(
      title: t.isPerson ? t.name : '#${t.name}',
      subtitle: '${t.uses} ${t.uses == 1 ? 'memory' : 'memories'}',
      leading: t.isPerson ? Monogram(tag: t, size: 28) : VIcon(G.hash, size: 20, color: c.inkSoft),
      onTap: () => openTag(context, t),
    );

    return Scaffold(
      appBar: AppBar(
        leading: VIconButton(G.chevronLeft, label: 'Back', onTap: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, 4, Space.page, 40),
        children: [
          Text('People & tags', style: context.type.display.copyWith(fontSize: 36)),
          const SizedBox(height: 6),
          Text('Mentioning someone like “Mom’s” or a #tag while saving adds them here.', style: context.type.bodySoft),
          const SizedBox(height: 24),
          if (all.isEmpty)
            const EmptyState(
              title: 'No one here yet',
              subtitle: 'Try “Mom’s shoe size 7” or “#car” next time you save something.',
              mood: MascotMood.wink,
              size: 100,
            ),
          if (people.isNotEmpty) ...[
            ListGroup(header: 'People', children: people.map(row).toList()),
            const SizedBox(height: 24),
          ],
          if (tags.isNotEmpty) ListGroup(header: 'Tags', children: tags.map(row).toList()),
        ],
      ),
    );
  }
}
