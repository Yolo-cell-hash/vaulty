import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory.dart';
import '../services/calendar_service.dart';
import '../services/settings.dart';
import '../state/vault_state.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/mascot.dart';
import '../widgets/memory_cards.dart';
import '../widgets/nav_bar.dart';
import 'capture/draft.dart';

/// Brings dates in from the phone's calendars: birthdays, renewals, deadlines.
/// Vaulty copies each picked event's title and day; the calendar is untouched.
class CalendarImportScreen extends ConsumerStatefulWidget {
  const CalendarImportScreen({super.key});

  @override
  ConsumerState<CalendarImportScreen> createState() => _CalendarImportScreenState();
}

class _Candidate {
  const _Candidate(this.event, this.memory, {required this.suggested, required this.inVault});

  final CalendarEvent event;
  final Memory memory;
  final bool suggested;
  final bool inVault;
}

enum _Stage { loading, ask, refused, ready, failed }

class _CalendarImportScreenState extends ConsumerState<CalendarImportScreen> {
  _Stage _stage = _Stage.loading;
  List<_Candidate> _candidates = const [];
  final Set<String> _picked = {};
  bool _showAll = false;
  bool _busy = false;

  /// How far ahead to look. A year catches every birthday once.
  static const _window = Duration(days: 366);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final granted = await CalendarService.hasAccess().catchError((Object _) => false);
    if (!mounted) return;
    if (granted) return _load();
    setState(() => _stage = _Stage.ask);
  }

  Future<void> _ask() async {
    final granted = await CalendarService.requestAccess().catchError((Object _) => false);
    if (!mounted) return;
    if (granted) return _load();
    setState(() => _stage = _Stage.refused);
  }

  Future<void> _load() async {
    setState(() => _stage = _Stage.loading);
    try {
      final today = DateUtils.dateOnly(DateTime.now());
      final events = await CalendarService.events(
        from: today,
        to: today.add(_window),
        exclude: ref.read(settingsProvider).calendarId,
      );
      final items = ref.read(vaultProvider).value ?? const <Memory>[];
      final known = ref.read(tagsProvider).value ?? const <Tag>[];
      final candidates = [
        for (final e in events)
          if (e.title.trim().isNotEmpty)
            () {
              final memory = memoryFromEvent(e, known: known);
              return _Candidate(e, memory, suggested: suggestedForImport(e), inVault: alreadyInVault(memory, items));
            }(),
      ];
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _picked
          ..clear()
          ..addAll([
            for (final c in candidates)
              if (c.suggested && !c.inVault) c.event.id,
          ]);
        _stage = _Stage.ready;
      });
    } catch (e) {
      debugPrint('calendar read failed: $e');
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  Future<void> _import() async {
    final memories = [
      for (final c in _candidates)
        if (_picked.contains(c.event.id)) c.memory,
    ];
    if (memories.isEmpty) return;
    setState(() => _busy = true);
    await ref.read(vaultProvider.notifier).saveAll(memories);
    if (!mounted) return;
    Haptics.success();
    final toast = toaster(context);
    Navigator.pop(context);
    toast('Imported ${memories.length} ${memories.length == 1 ? 'date' : 'dates'}', icon: G.calendar);
  }

  void _toggle(String id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));

  @override
  Widget build(BuildContext context) {
    final suggested = _candidates.where((c) => c.suggested).toList();
    final others = _candidates.where((c) => !c.suggested).toList();
    return Scaffold(
      appBar: vAppBar(
        context,
        leading: VIconButton(G.chevronLeft, label: 'Back', onTap: () => Navigator.pop(context)),
        largeTitle: 'Import',
      ),
      body: ListView(
        padding: context.pageInsets + const EdgeInsets.fromLTRB(Space.page, 4, Space.page, 40),
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'From your '),
                TextSpan(text: 'calendar.', style: context.type.accent),
              ],
            ),
            style: context.type.display.copyWith(fontSize: 36),
          ),
          const SizedBox(height: 8),
          Text(
            'Pick the dates worth keeping. Vaulty copies the title and the day, and your calendar stays as it is.',
            style: context.type.bodySoft,
          ),
          const SizedBox(height: 24),
          ...switch (_stage) {
            _Stage.loading => [
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: Spinner()),
              ),
            ],
            _Stage.ask => [
              const EmptyState(
                title: 'Let Vaulty look',
                subtitle: 'It reads your calendars on this phone to find dates. Nothing is sent anywhere.',
                prop: MascotProp.magnifier,
                size: 100,
              ),
              const SizedBox(height: 20),
              VButton(label: 'Allow calendar access', icon: G.calendar, onPressed: _ask),
            ],
            _Stage.refused => [
              const EmptyState(
                title: 'No calendar access',
                subtitle: 'Turn on Calendars for Vaulty in Settings, then come back here.',
                mood: MascotMood.wow,
                size: 100,
              ),
              const SizedBox(height: 20),
              VButton(label: 'Open Settings', onPressed: () => CalendarService.openSettings()),
              const SizedBox(height: 8),
              VButton(label: 'Try again', kind: ButtonStyleKind.ghost, height: 44, onPressed: _start),
            ],
            _Stage.failed => [
              const EmptyState(
                title: 'Couldn’t read your calendars',
                subtitle: 'Something went wrong on the way. Try again in a moment.',
                mood: MascotMood.wow,
                size: 100,
              ),
              const SizedBox(height: 20),
              VButton(label: 'Try again', kind: ButtonStyleKind.outline, onPressed: _load),
            ],
            _Stage.ready when _candidates.isEmpty => [
              const EmptyState(
                title: 'Nothing coming up',
                subtitle: 'Your calendars have no events in the next year.',
                mood: MascotMood.sleepy,
                prop: MascotProp.zzz,
                size: 100,
              ),
            ],
            _Stage.ready => [
              if (suggested.isNotEmpty) ListGroup(header: 'Suggested', children: [for (final c in suggested) _row(c)]),
              if (suggested.isNotEmpty && others.isNotEmpty) const SizedBox(height: 24),
              if (others.isNotEmpty && (_showAll || suggested.isEmpty))
                ListGroup(header: 'Everything else', children: [for (final c in others) _row(c)])
              else if (others.isNotEmpty)
                VButton(
                  label: 'Show ${others.length} more ${others.length == 1 ? 'event' : 'events'}',
                  kind: ButtonStyleKind.outline,
                  height: 48,
                  onPressed: () => setState(() => _showAll = true),
                ),
            ],
          },
        ],
      ),
      bottomNavigationBar: _stage == _Stage.ready && _candidates.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: context.pageInsets + const EdgeInsets.fromLTRB(Space.page, 8, Space.page, 8),
                child: VButton(
                  label: _picked.isEmpty
                      ? 'Pick something to import'
                      : 'Import ${_picked.length} ${_picked.length == 1 ? 'date' : 'dates'}',
                  icon: _picked.isEmpty ? null : G.download,
                  busy: _busy,
                  onPressed: _picked.isEmpty ? null : _import,
                ),
              ),
            )
          : null,
    );
  }

  Widget _row(_Candidate c) {
    final picked = _picked.contains(c.event.id);
    final repeats = switch (c.memory.recurrence) {
      Recurrence.yearly => '  ·  Yearly',
      Recurrence.monthly => '  ·  Monthly',
      Recurrence.none => '',
    };
    final where = c.event.calendarName.isEmpty ? '' : '  ·  ${c.event.calendarName}';
    return Semantics(
      checked: c.inVault ? null : picked,
      child: Opacity(
        opacity: c.inVault ? .55 : 1,
        child: ListRow(
          title: c.memory.title,
          subtitle: c.inVault ? 'Already in your vault' : '${dateFmt.format(c.event.date)}$repeats$where',
          chevron: false,
          trailing: c.inVault ? null : _Tick(picked: picked),
          onTap: c.inVault ? null : () => _toggle(c.event.id),
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.picked});

  final bool picked;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: picked ? c.ink : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: picked ? c.ink : c.line, width: 1.5),
      ),
      alignment: Alignment.center,
      child: picked ? VIcon(G.check, size: 14, color: c.onInk, stroke: 2.4) : null,
    );
  }
}
