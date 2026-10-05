import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_shell.dart';
import 'screens/lock_screen.dart';
import 'screens/memory_detail_screen.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'services/attachment_store.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/settings.dart';
import 'state/vault_state.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';
import 'widgets/splash_intro.dart';

class VaultyApp extends ConsumerStatefulWidget {
  const VaultyApp({super.key});

  @override
  ConsumerState<VaultyApp> createState() => _VaultyAppState();
}

/// Lets services (notification taps) navigate without a BuildContext.
final rootNavigatorKey = GlobalKey<NavigatorState>();

class _VaultyAppState extends ConsumerState<VaultyApp> {
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<String>? _taps;
  bool _obscured = false;
  DateTime? _hiddenAt;

  /// How long the app may sit in the background before it re-locks.
  static const _grace = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    // Tapping a reminder opens the memory it's about, whether the app was
    // running (stream) or launched by the tap (launch payload).
    _taps = NotificationService.taps.listen(_openMemory);
    unawaited(_openLaunchNotification());
  }

  Future<void> _openLaunchNotification() async {
    try {
      await NotificationService.init();
      final id = NotificationService.takeLaunchPayload();
      if (id != null) _openMemory(id);
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  @override
  void dispose() {
    _taps?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _openMemory(String id) {
    if (!ref.read(settingsProvider).onboarded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      // Back from the item lands on home, not on whatever was open before.
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(builder: (_) => MemoryDetailScreen(memoryId: id)));
    });
  }

  void _onLifecycle(AppLifecycleState s) {
    final settings = ref.read(settingsProvider);
    if (!settings.lockEnabled || AuthService.externalFlowActive) {
      if (_obscured) setState(() => _obscured = false);
      return;
    }
    switch (s) {
      case AppLifecycleState.inactive:
        setState(() => _obscured = true);
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _hiddenAt ??= DateTime.now();
        setState(() => _obscured = true);
      case AppLifecycleState.resumed:
        // Face ID may have been set up in Settings while we were away.
        ref.invalidate(biometricProvider);
        final away = _hiddenAt == null ? Duration.zero : DateTime.now().difference(_hiddenAt!);
        _hiddenAt = null;
        if (away >= _grace) {
          ref.read(unlockedProvider.notifier).set(false);
          AttachmentStore.clearCache();
        }
        setState(() => _obscured = false);
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final unlocked = ref.watch(unlockedProvider);
    final locked = settings.onboarded && settings.lockEnabled && !unlocked;
    final introDone = ref.watch(splashDoneProvider);

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Vaulty',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      themeMode: settings.themeMode,
      scrollBehavior: const _ScrollBehavior(),
      home: const _RootGate(),
      // Honour the system text size up to 2x; past that the serif display
      // lines stop fitting on a phone. Dense widgets clamp lower themselves.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        // Status bar text follows the app's theme, not the system's, on pages
        // without an app bar to set it (the tabs, the lock screen). Only the
        // status bar: the navigation bar keeps its own settings.
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: context.isDark ? Brightness.dark : Brightness.light,
          statusBarIconBrightness: context.isDark ? Brightness.light : Brightness.dark,
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 2,
          child: Stack(
            children: [
              ?child,
              if (locked) const Positioned.fill(child: LockScreen()),
              if (_obscured && !locked) const Positioned.fill(child: _PrivacyCover()),
              // Launch intro sits above everything and hands off from the native splash.
              if (!introDone)
                Positioned.fill(child: SplashIntro(onDone: () => ref.read(splashDoneProvider.notifier).finish())),
            ],
          ),
        ),
      ),
    );
  }
}

class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(settingsProvider.select((s) => s.onboarded));
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(anim), child: child),
      ),
      child: onboarded ? const HomeShell() : const OnboardingFlow(),
    );
  }
}

/// iOS shows a scroll indicator while a page moves; Android keeps none.
class _ScrollBehavior extends MaterialScrollBehavior {
  const _ScrollBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    if (getPlatform(context) == TargetPlatform.iOS && axisDirectionToAxis(details.direction) == Axis.vertical) {
      return CupertinoScrollbar(controller: details.controller, child: child);
    }
    return super.buildScrollbar(context, child, details);
  }
}

/// Hides vault contents in the OS app switcher.
class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      // Material (not ColoredBox) so the wordmark gets default text styling;
      // this overlay sits above the Navigator.
      child: Material(
        color: c.bg.withValues(alpha: .9),
        child: const Center(child: Wordmark(size: 40)),
      ),
    );
  }
}
