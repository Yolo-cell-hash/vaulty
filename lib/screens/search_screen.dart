import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/memory_repository.dart';
import '../models/memory.dart';
import '../state/vault_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/mascot.dart';
import '../widgets/memory_cards.dart';
import '../widgets/tag_widgets.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, required this.active});

  final bool active;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<String> _ids = [];
  bool _searching = false;
  bool _focused = false;
  int _seq = 0;

  static const _prompts = ["Mom's shoe size", 'Passport expiry', 'Paint color', 'Wi-Fi password', 'Policy number'];

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void didUpdateWidget(SearchScreen old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) _focus.unfocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () => _run(q));
  }

  Future<void> _run(String q) async {
    final seq = ++_seq;
    if (MemoryRepository.searchTerms(q).isEmpty) {
      setState(() => _ids = []);
      return;
    }
    setState(() => _searching = true);
    final ids = await repository.search(q);
    if (!mounted || seq != _seq) return;
    setState(() {
      _ids = ids;
      _searching = false;
    });
  }

  void _cancel() {
    _controller.clear();
    _onChanged('');
    _focus.unfocus();
  }

  void _usePrompt(String p) {
    _controller.text = p;
    _controller.selection = TextSelection.collapsed(offset: p.length);
    _onChanged(p);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    // Re-run the query when the vault changes so results never go stale.
    ref.listen(vaultProvider, (_, _) {
      if (_controller.text.isNotEmpty) _run(_controller.text);
    });
    final items = ref.watch(vaultProvider).value ?? const <Memory>[];
    final byId = {for (final m in items) m.id: m};
    final results = _ids.map((id) => byId[id]).whereType<Memory>().toList();
    final query = _controller.text.trim();

    return GestureDetector(
      onTap: () => _focus.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: PageScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.page, 20, Space.page, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Ask '),
                          TextSpan(text: 'anything.', style: context.type.accent),
                        ],
                      ),
                      style: context.type.display,
                    ),
                    const SizedBox(height: 6),
                    Text('Casual questions work. It all stays on this phone.', style: context.type.bodySoft),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focus,
                            onChanged: _onChanged,
                            textInputAction: TextInputAction.search,
                            style: context.type.body.copyWith(fontSize: 16),
                            decoration: InputDecoration(
                              hintText: 'What’s Mom’s shoe size?',
                              prefixIcon: Padding(
                                padding: const EdgeInsets.all(14),
                                child: VIcon(G.search, size: 19, color: c.inkSoft),
                              ),
                              suffixIcon: query.isEmpty
                                  ? null
                                  : VIconButton(
                                      G.close,
                                      label: 'Clear',
                                      size: 36,
                                      color: c.inkSoft,
                                      onTap: () {
                                        _controller.clear();
                                        _onChanged('');
                                      },
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: BorderSide(color: c.line),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: BorderSide(color: c.line),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: BorderSide(color: c.ink, width: 1.4),
                              ),
                            ),
                          ),
                        ),
                        // iOS: a search field in use gets a Cancel beside it.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: context.isCupertino && _focused
                              ? CupertinoButton(
                                  padding: const EdgeInsets.only(left: 14),
                                  minimumSize: Size.zero,
                                  onPressed: _cancel,
                                  child: Text(
                                    'Cancel',
                                    style: context.type.body.copyWith(color: c.brand, fontSize: 16),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (query.isEmpty)
            SliverToBoxAdapter(child: _suggestions(items))
          else if (results.isEmpty && !_searching)
            const SliverToBoxAdapter(
              child: EmptyState(
                title: 'No luck there',
                subtitle: 'Try fewer words, or a detail like a brand or a number.',
                mood: MascotMood.wow,
                prop: MascotProp.magnifier,
              ),
            )
          else if (results.isNotEmpty) ...[
            SliverToBoxAdapter(child: _AnswerCard(memory: results.first)),
            if (results.length > 1) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, 28, Space.page, 10),
                  child: Eyebrow('More matches  ·  ${results.length - 1}'),
                ),
              ),
              SliverToBoxAdapter(child: MemoryList(items: results.skip(1).toList())),
            ],
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 130)),
        ],
      ),
    );
  }

  Widget _suggestions(List<Memory> items) {
    final people = ref.watch(peopleProvider).where((p) => p.uses > 0).toList();
    final recent = items.take(5).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.page, 28, Space.page, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (people.isNotEmpty) ...[
            const Eyebrow('Everything about'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final p in people) TagChip(tag: p, onTap: () => openTag(context, p))],
            ),
            const SizedBox(height: 28),
          ],
          const Eyebrow('Try asking'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final p in _prompts) VChip(label: p, icon: G.search, onTap: () => _usePrompt(p))],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Eyebrow('Recently added'),
            const SizedBox(height: 10),
          ],
          if (recent.isEmpty) ...[
            const SizedBox(height: 40),
            const Center(child: Mascot(size: 110, prop: MascotProp.magnifier)),
          ],
        ],
      ),
    ).withRecent(recent);
  }
}

extension on Widget {
  /// Appends the recent list full-bleed (it has its own horizontal padding).
  Widget withRecent(List<Memory> recent) => recent.isEmpty
      ? this
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            this,
            MemoryList(items: recent),
          ],
        );
}

/// The top hit, presented like an instant answer.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final head = memory.headline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 22, Space.l, 0),
      child: VCard(
        onTap: () => openMemory(context, memory),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Eyebrow('Best match', color: c.brand),
                const Spacer(),
                CategoryLabel.of(memory, size: 13),
              ],
            ),
            const SizedBox(height: 12),
            Text(memory.title, style: context.type.headline.copyWith(fontSize: 26)),
            if (head != null) ...[
              const SizedBox(height: 16),
              Text(head.key, style: context.type.caption),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: Text(maskedValue(memory, head.value), style: context.type.mono(24))),
                  if (memory.isSensitive) VIcon(G.lock, size: 18, color: c.inkFaint),
                ],
              ),
            ],
            if (memory.hasExpiry) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  CountdownTag(memory: memory),
                  const SizedBox(width: 10),
                  Text(dateFmt.format(memory.nextDate!), style: context.type.caption),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
