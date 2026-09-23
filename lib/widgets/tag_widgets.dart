import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory.dart';
import '../screens/capture/draft.dart';
import '../screens/tag_screen.dart';
import '../state/vault_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'glyphs.dart';

void openTag(BuildContext context, Tag tag) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TagScreen(tagId: tag.id)));
}

/// Pill for a person (mini monogram) or a tag (hash glyph).
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.tag, this.onTap, this.onRemove, this.dense = false});

  final Tag tag;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Pressable(
      onTap: onTap,
      semanticLabel: tag.isPerson ? 'Person ${tag.name}' : 'Tag ${tag.name}',
      excludeSemantics: onRemove == null,
      child: Container(
        padding: EdgeInsets.fromLTRB(tag.isPerson ? 4 : 10, 4, onRemove == null ? 12 : 4, 4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tag.isPerson)
              Monogram(tag: tag, size: dense ? 20 : 24)
            else
              VIcon(G.hash, size: dense ? 13 : 14, color: c.inkSoft, stroke: 2),
            SizedBox(width: tag.isPerson ? 7 : 4),
            Text(
              tag.name,
              style: context.type.caption.copyWith(
                color: c.ink,
                fontSize: dense ? 12.5 : 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (onRemove != null)
              Pressable(
                onTap: onRemove,
                semanticLabel: 'Remove ${tag.name}',
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: VIcon(G.close, size: 13, color: c.inkFaint, stroke: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row of people with ringed monograms.
class PeopleStrip extends StatelessWidget {
  const PeopleStrip({super.key, required this.people});

  final List<Tag> people;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final p = people[i];
          return Pressable(
            onTap: () => openTag(context, p),
            semanticLabel: '${p.name}, ${p.uses} memories',
            child: SizedBox(
              width: 62,
              child: Column(
                children: [
                  Monogram(tag: p, size: 54, ring: true),
                  const SizedBox(height: 7),
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.caption.copyWith(color: context.vc.ink, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Pick an existing person/tag or create one.
Future<Tag?> pickTag(BuildContext context, {required TagKind kind, List<Tag> exclude = const []}) {
  return showModalBottomSheet<Tag>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TagPickerSheet(kind: kind, exclude: exclude),
  );
}

class _TagPickerSheet extends ConsumerStatefulWidget {
  const _TagPickerSheet({required this.kind, required this.exclude});

  final TagKind kind;
  final List<Tag> exclude;

  @override
  ConsumerState<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<_TagPickerSheet> {
  final _query = TextEditingController();

  static const _personIdeas = ['Mom', 'Dad', 'Partner', 'Sister', 'Brother', 'Grandma', 'Bestie', 'Me'];
  static const _tagIdeas = ['car', 'home', 'travel', 'health', 'work', 'money', 'pets', 'gifts'];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _choose(Tag t) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, t);
  }

  void _create(String raw) {
    final name = raw.trim().replaceAll(RegExp(r'^#'), '');
    if (name.isEmpty) return;
    final known = ref.read(tagsProvider).value ?? const <Tag>[];
    _choose(
      resolveTag(
        widget.kind == TagKind.person ? name[0].toUpperCase() + name.substring(1) : name.toLowerCase(),
        widget.kind,
        known,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final person = widget.kind == TagKind.person;
    final q = _query.text.trim().toLowerCase().replaceAll('#', '');
    final all = (ref.watch(tagsProvider).value ?? const <Tag>[])
        .where((t) => t.kind == widget.kind && !widget.exclude.any((e) => e.sameAs(t)))
        .toList();
    final matches = all.where((t) => q.isEmpty || t.name.toLowerCase().contains(q)).toList();
    final exact = all.any((t) => t.name.toLowerCase() == q);
    final ideas = (person ? _personIdeas : _tagIdeas)
        .where((i) => !all.any((t) => t.name.toLowerCase() == i.toLowerCase()))
        .where((i) => !widget.exclude.any((e) => e.name.toLowerCase() == i.toLowerCase()))
        .where((i) => q.isEmpty || i.toLowerCase().contains(q))
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(person ? 'Who is this about?' : 'Add a tag', style: context.type.headline.copyWith(fontSize: 26)),
            const SizedBox(height: 14),
            TextField(
              controller: _query,
              autofocus: all.isEmpty,
              textCapitalization: person ? TextCapitalization.words : TextCapitalization.none,
              onChanged: (_) => setState(() {}),
              onSubmitted: _create,
              style: context.type.body,
              decoration: InputDecoration(
                hintText: person ? 'Name, like Mom or Joe' : 'Tag, like car',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(13),
                  child: VIcon(person ? G.person : G.hash, size: 18, color: c.inkSoft),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .35),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (q.isNotEmpty && !exact)
                      VChip(
                        label: person ? 'Add “${_query.text.trim()}”' : 'Add #$q',
                        icon: G.plus,
                        selected: true,
                        onTap: () => _create(q),
                      ),
                    for (final t in matches) TagChip(tag: t, onTap: () => _choose(t)),
                    for (final i in ideas) VChip(label: person ? i : '#$i', onTap: () => _create(i)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
