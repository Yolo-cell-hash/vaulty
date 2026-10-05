import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/nav_bar.dart';
import 'capture/capture_sheet.dart';
import 'me_screen.dart';
import 'radar_screen.dart';
import 'search_screen.dart';
import 'vault_home_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  /// One per tab, so the status-bar tap (iOS) and a second tap on the tab
  /// scroll only the page that's showing.
  final _scrolls = List.generate(4, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(settingsProvider.notifier).change((s) => s.withStreakTick(DateTime.now()));
    });
  }

  @override
  void dispose() {
    for (final s in _scrolls) {
      s.dispose();
    }
    super.dispose();
  }

  void _select(int i) {
    if (i == _tab) {
      // Tapping the open tab again goes back to its top.
      final s = _scrolls[i];
      if (s.hasClients && s.offset > 0) {
        s.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
      }
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(settingsProvider.select((s) => s.name.trim()));
    final tabs = [
      (
        const Wordmark(size: 20),
        VaultHomeScreen(onOpenRadar: () => _select(1), onOpenSearch: () => _select(2), onOpenMe: () => _select(3)),
      ),
      (const Text('Radar'), const RadarScreen()),
      (const Text('Search'), SearchScreen(active: _tab == 2)),
      (Text(name.isEmpty ? 'You' : name), const MeScreen()),
    ];
    return PrimaryScrollController(
      controller: _scrolls[_tab],
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < tabs.length; i++)
              PrimaryScrollController(
                controller: _scrolls[i],
                child: ScrollEdgeBar(title: tabs[i].$1, threshold: i == 0 ? 96 : 56, child: tabs[i].$2),
              ),
          ],
        ),
        bottomNavigationBar: _FloatingNav(index: _tab, onSelect: _select, onCapture: () => showCaptureSheet(context)),
      ),
    );
  }
}

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({required this.index, required this.onSelect, required this.onCapture});

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCapture;

  static const _tabs = [(G.vault, 'Vault'), (G.radar, 'Radar'), (G.search, 'Search'), (G.profile, 'You')];

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final bottom = MediaQuery.paddingOf(context).bottom;
    // The capsule is ink in light mode and a lifted graphite in dark mode.
    final capsule = context.isDark ? const Color(0xFF26262C) : c.ink;
    const on = Color(0xFFF6F4EF);
    // Fixed 64pt capsule; the icons carry it, so labels barely scale.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Padding(
        padding: context.pageInsets + EdgeInsets.fromLTRB(Space.page, 0, Space.page, bottom + 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: capsule, borderRadius: BorderRadius.circular(32)),
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Expanded(
                        child: Pressable(
                          onTap: () => onSelect(i),
                          haptic: false,
                          scale: .9,
                          semanticLabel: _tabs[i].$2,
                          selected: i == index,
                          child: SizedBox(
                            height: 64,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                VIcon(
                                  _tabs[i].$1,
                                  size: 24,
                                  color: i == index ? on : on.withValues(alpha: .42),
                                  stroke: 1.8,
                                ),
                                const SizedBox(height: 6),
                                // Scale (not size) so the springy overshoot can't
                                // produce negative constraints.
                                AnimatedScale(
                                  scale: i == index ? 1 : 0,
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutBack,
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(color: c.acid, shape: BoxShape.circle),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Pressable(
              onTap: onCapture,
              scale: .9,
              semanticLabel: 'Add a memory',
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: c.acid,
                  shape: BoxShape.circle,
                  border: Border.all(color: capsule, width: 1.5),
                ),
                alignment: Alignment.center,
                child: const VIcon(G.plus, size: 26, color: Color(0xFF151419), stroke: 2.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
