import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/personalization.dart';
import '../../services/settings.dart';
import '../../state/vault_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/mascot.dart';
import 'onboarding_widgets.dart';
import 'personalizing_step.dart';

class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  int _step = 0;
  bool _forward = true;
  final Set<String> _goals = {};
  int? _reminderMinutes;
  List<int>? _leadOffsets;
  final _name = TextEditingController();
  bool _lock = false;

  /// Steps that show the progress rule (goals → reminders).
  static const _firstCounted = 2, _lastCounted = 7;

  static const _goalOptions = [
    (G.clock, Goals.expiries),
    (G.ruler, Goals.sizes),
    (G.document, Goals.documents),
    (G.repeat, Goals.subscriptions),
    (G.cake, Goals.people),
    (G.search, Goals.lookups),
    (G.lock, Goals.privacy),
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _forward = step > _step;
      _step = step;
    });
  }

  void _next() => _go(_step + 1);
  void _back() => _go(_step - 1);

  Future<void> _finish() async {
    await ref
        .read(settingsProvider.notifier)
        .change(
          (s) => s
              .copyWith(
                onboarded: true,
                name: _name.text.trim(),
                // Keep the order they appear on screen so the home screen and
                // templates lead with the first thing picked.
                goals: [
                  for (final (_, g) in _goalOptions)
                    if (_goals.contains(g)) g,
                ],
                lockEnabled: _lock,
                reminderMinutes: _reminderMinutes,
                reminderOffsets: _leadOffsets,
              )
              .withStreakTick(DateTime.now()),
        );
    ref.read(unlockedProvider.notifier).set(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0 && _step < 8) _back();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) {
            final incoming = child.key == ValueKey(_step);
            final dx = (incoming == _forward) ? .08 : -.08;
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(key: ValueKey(_step), child: _buildStep()),
        ),
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
    0 => _welcome(),
    1 => _beforeAfter(),
    2 => _goalsStep(),
    3 => _question(
      index: 3,
      question: 'When do reminders suit you best?',
      hint: 'Every nudge arrives at this time. You can change it per item.',
      options: [for (final (label, _) in reminderTimeChoices) label],
      selected: reminderTimeChoices.indexWhere((c) => c.$2 == _reminderMinutes),
      onPick: (i) => _reminderMinutes = reminderTimeChoices[i].$2,
      prop: MascotProp.sparkles,
    ),
    4 => _question(
      index: 4,
      question: 'How much warning do you like?',
      hint: 'For passports, policies and anything else that runs out.',
      options: [for (final (label, _) in leadTimeChoices) label],
      selected: leadTimeChoices.indexWhere((c) => listEquals(c.$2, _leadOffsets)),
      onPick: (i) => _leadOffsets = leadTimeChoices[i].$2,
      prop: MascotProp.magnifier,
    ),
    5 => _nameStep(),
    6 => _lockStep(),
    7 => _notifyStep(),
    _ => PersonalizingStep(onDone: _finish),
  };

  /// Common frame: progress rule, scrollable body, pinned actions.
  Widget _frame({required List<Widget> body, required List<Widget> actions, bool progress = true}) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (progress)
              StepProgress(step: _step - _firstCounted + 1, total: _lastCounted - _firstCounted + 1, onBack: _back),
            Expanded(
              child: ListView(padding: const EdgeInsets.only(top: 28, bottom: 16), children: body),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- steps --

  Widget _welcome() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, 16, Space.page, Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Wordmark(),
            const Spacer(),
            const Mascot(size: 150, wave: true),
            const SizedBox(height: 22),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Your second brain,\n'),
                  TextSpan(text: 'locked tight.', style: context.type.accent),
                ],
              ),
              style: context.type.display.copyWith(fontSize: 44),
            ),
            const SizedBox(height: 14),
            Text(
              'Sizes, codes, renewals and birthdays. Kept on your phone, remembered on time.',
              style: context.type.bodySoft,
            ),
            const SizedBox(height: 26),
            const FeatureLine(glyph: G.shield, text: 'Encrypted, and it never leaves this phone'),
            const FeatureLine(glyph: G.sparkle, text: 'Understands plain English'),
            const FeatureLine(glyph: G.bell, text: 'Reminds you before things lapse'),
            const Spacer(),
            VButton(label: 'Get started', icon: G.arrowRight, onPressed: _next),
            const SizedBox(height: 10),
            Center(child: Text('No account. No sign-up.', style: context.type.caption)),
          ],
        ),
      ),
    );
  }

  Widget _beforeAfter() {
    return _frame(
      progress: false,
      body: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Less '),
              TextSpan(text: 'remembering', style: context.type.accent),
              const TextSpan(text: ',\nmore living.'),
            ],
          ),
          style: context.type.display,
        ),
        const SizedBox(height: 32),
        const BeforeAfter(),
      ],
      actions: [VButton(label: 'Sounds good', onPressed: _next)],
    );
  }

  Widget _goalsStep() {
    return _frame(
      body: [
        Text('What should Vaulty take off your plate?', style: context.type.headline),
        const SizedBox(height: 8),
        Text('Pick as many as you like.', style: context.type.bodySoft),
        const SizedBox(height: 22),
        for (final (glyph, label) in _goalOptions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OptionTile(
              glyph: glyph,
              label: label,
              multi: true,
              selected: _goals.contains(label),
              onTap: () => setState(() => _goals.contains(label) ? _goals.remove(label) : _goals.add(label)),
            ),
          ),
      ],
      actions: [VButton(label: 'Continue', onPressed: _goals.isEmpty ? null : _next)],
    );
  }

  Widget _question({
    required int index,
    required String question,
    required String hint,
    required List<String> options,
    required int selected,
    required ValueChanged<int> onPick,
    required MascotProp prop,
  }) {
    return _frame(
      body: [
        Mascot(size: 72, prop: prop),
        const SizedBox(height: 14),
        Text(question, style: context.type.headline),
        const SizedBox(height: 8),
        Text(hint, style: context.type.bodySoft),
        const SizedBox(height: 24),
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OptionTile(
              index: i,
              label: options[i],
              selected: selected == i,
              onTap: () async {
                setState(() => onPick(i));
                await Future<void>.delayed(const Duration(milliseconds: 240));
                if (mounted && _step == index) _next();
              },
            ),
          ),
      ],
      actions: const [],
    );
  }

  Widget _nameStep() {
    final c = context.vc;
    return _frame(
      body: [
        Text('What should we call you?', style: context.type.headline),
        const SizedBox(height: 8),
        Text('It stays on this phone, like everything else.', style: context.type.bodySoft),
        const SizedBox(height: 28),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 24,
          style: context.type.display.copyWith(fontSize: 36),
          decoration: InputDecoration(
            hintText: 'Your name',
            hintStyle: context.type.display.copyWith(fontSize: 36, color: c.inkFaint),
            counterText: '',
            filled: false,
            contentPadding: const EdgeInsets.only(bottom: 8),
            border: UnderlineInputBorder(borderSide: BorderSide(color: c.line)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.line)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.ink, width: 1.4)),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _next(),
        ),
      ],
      actions: [VButton(label: _name.text.trim().isEmpty ? 'Skip' : 'Continue', onPressed: _next)],
    );
  }

  Widget _lockStep() {
    return _frame(
      body: [
        const Mascot(size: 120, prop: MascotProp.key),
        const SizedBox(height: 16),
        Text('Lock it like a diary.', style: context.type.headline),
        const SizedBox(height: 8),
        Text(
          Platform.isIOS
              ? 'Face ID or your passcode opens the vault. Nobody else gets in, not even us.'
              : 'Your fingerprint or PIN opens the vault. Nobody else gets in, not even us.',
          style: context.type.bodySoft,
        ),
      ],
      actions: [
        VButton(
          label: Platform.isIOS ? 'Use Face ID' : 'Use fingerprint',
          icon: Platform.isIOS ? G.faceId : G.fingerprint,
          onPressed: () async {
            final toast = toaster(context);
            if (!await AuthService.isAvailable()) {
              toast('Set up a screen lock on your phone first', icon: G.lock);
              return;
            }
            final ok = await AuthService.authenticate('Turn on Vaulty app lock');
            if (!mounted || !ok) return;
            HapticFeedback.mediumImpact();
            _lock = true;
            _next();
          },
        ),
        const SizedBox(height: 8),
        VButton(
          label: 'Maybe later',
          kind: ButtonStyleKind.ghost,
          height: 44,
          onPressed: () {
            _lock = false;
            _next();
          },
        ),
      ],
    );
  }

  Widget _notifyStep() {
    return _frame(
      body: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'A nudge before\nit’s '),
              TextSpan(text: 'too late.', style: context.type.accent),
            ],
          ),
          style: context.type.headline.copyWith(fontSize: 34),
        ),
        const SizedBox(height: 10),
        Text('Reminders are scheduled on your phone. No servers involved.', style: context.type.bodySoft),
        const SizedBox(height: 26),
        const NotificationPreview(),
      ],
      actions: [
        VButton(
          label: 'Turn on reminders',
          icon: G.bell,
          onPressed: () async {
            await AuthService.guardExternal(NotificationService.requestPermission);
            if (mounted) _next();
          },
        ),
        const SizedBox(height: 8),
        VButton(label: 'Not now', kind: ButtonStyleKind.ghost, height: 44, onPressed: _next),
      ],
    );
  }
}
