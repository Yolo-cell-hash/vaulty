import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/vault_database.dart';
import '../../services/notification_service.dart';
import '../../services/secure_keys.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/mascot.dart';

/// Final onboarding screen. The steps are real: the key is generated, the
/// encrypted database created and the reminder engine warmed up.
class PersonalizingStep extends StatefulWidget {
  const PersonalizingStep({super.key, required this.onDone});

  final Future<void> Function() onDone;

  @override
  State<PersonalizingStep> createState() => _PersonalizingStepState();
}

class _PersonalizingStepState extends State<PersonalizingStep> with TickerProviderStateMixin {
  static const _labels = [
    ('Creating your key', G.key),
    ('Encrypting your vault', G.shield),
    ('Setting up reminders', G.bell),
  ];

  late final List<AnimationController> _bars = List.generate(
    _labels.length,
    (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 1100)),
  );
  int _active = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    for (final b in _bars) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    final jobs = <Future<void> Function()>[
      () async {
        await SecureKeys.databaseKey();
        await SecureKeys.mediaKey();
      },
      () async => VaultDatabase.instance,
      NotificationService.init,
    ];
    try {
      for (var i = 0; i < jobs.length; i++) {
        if (!mounted) return;
        setState(() => _active = i);
        final anim = _bars[i].animateTo(.9, curve: Curves.easeOutCubic);
        await Future.wait([jobs[i](), anim]);
        await _bars[i].animateTo(1, duration: const Duration(milliseconds: 180));
        HapticFeedback.selectionClick();
      }
      if (!mounted) return;
      setState(() => _active = jobs.length);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final done = _active >= _labels.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, 24, Space.page, Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Mascot(
              size: 120,
              mood: done ? MascotMood.grin : MascotMood.happy,
              prop: done ? MascotProp.check : MascotProp.key,
            ),
            const SizedBox(height: 22),
            Text(
              _error != null ? 'Something went sideways' : (done ? 'All set.' : 'Setting up\nyour vault'),
              style: context.type.display,
            ),
            const SizedBox(height: 28),
            if (_error != null) ...[
              Text(_error!, style: context.type.caption.copyWith(color: c.danger)),
              const SizedBox(height: 16),
              VButton(
                label: 'Try again',
                onPressed: () {
                  setState(() => _error = null);
                  for (final b in _bars) {
                    b.value = 0;
                  }
                  _run();
                },
              ),
            ] else
              VCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < _labels.length; i++) ...[
                      if (i > 0) const Hairline(indent: 56),
                      AnimatedBuilder(
                        animation: _bars[i],
                        builder: (context, _) => _StepRow(
                          label: _labels[i].$1,
                          glyph: _labels[i].$2,
                          progress: _bars[i].value,
                          state: i < _active ? 2 : (i == _active ? 1 : 0),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.glyph, required this.progress, required this.state});

  final String label;
  final G glyph;
  final double progress;

  /// 0 = waiting, 1 = running, 2 = done.
  final int state;

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final done = state == 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 26,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: state == 0 ? 0 : progress,
                  strokeWidth: 2,
                  backgroundColor: c.line,
                  color: done ? c.ok : c.ink,
                ),
                VIcon(
                  done ? G.check : glyph,
                  size: 13,
                  color: done ? c.ok : (state == 0 ? c.inkFaint : c.ink),
                  stroke: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: context.type.body.copyWith(
                color: state == 0 ? c.inkFaint : c.ink,
                fontWeight: state == 1 ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            done ? 'Done' : (state == 1 ? '${(progress * 100).round()}%' : ''),
            style: context.type.mono(12, done ? c.ok : c.inkSoft),
          ),
        ],
      ),
    );
  }
}
