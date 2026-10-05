import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/settings.dart';
import '../state/vault_state.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/mascot.dart';
import '../widgets/splash_intro.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Don't raise the biometric prompt over the launch intro; wait for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(splashDoneProvider)) _unlock();
    });
    ref.listenManual(splashDoneProvider, (prev, done) {
      if (done && prev != true && mounted) _unlock();
    });
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await AuthService.authenticate('Unlock Vaulty');
    if (!mounted) return;
    if (ok) {
      Haptics.success();
      ref.read(unlockedProvider.notifier).set(true);
    } else {
      Haptics.error();
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final name = ref.watch(settingsProvider.select((s) => s.name.trim()));
    final ios = context.isCupertino;
    final biometric = ref.watch(biometricProvider).value ?? Biometric.faceId;
    return Material(
      color: c.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, 16, Space.page, Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Wordmark(),
              const Spacer(flex: 2),
              Mascot(
                size: 150,
                mood: _failed ? MascotMood.wow : MascotMood.sleepy,
                prop: _failed ? MascotProp.none : MascotProp.key,
              ),
              const SizedBox(height: 28),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: _failed ? 'Still ' : (name.isEmpty ? 'Welcome ' : 'Welcome back,\n')),
                    TextSpan(
                      text: _failed ? 'locked.' : (name.isEmpty ? 'back.' : '$name.'),
                      style: context.type.accent,
                    ),
                  ],
                ),
                style: context.type.display,
              ),
              const SizedBox(height: 10),
              Text(
                _failed
                    ? 'Only you can open this vault. Try again when you’re ready.'
                    : 'Your vault is locked and encrypted.',
                style: context.type.bodySoft,
              ),
              const Spacer(flex: 3),
              VButton(
                label: ios ? 'Unlock with ${biometric.label}' : 'Unlock',
                icon: ios ? biometric.glyph : G.fingerprint,
                busy: _busy,
                onPressed: _unlock,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
