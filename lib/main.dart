import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/secure_keys.dart';
import 'services/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _OrientationLock.instance.apply();
  WidgetsBinding.instance.addObserver(_OrientationLock.instance);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SecureKeys.ensureFreshInstallConsistency();
  initialSettings = await AppSettings.load();
  runApp(const ProviderScope(child: VaultyApp()));
}

/// Phones stay in portrait. Tablets, unfolded foldables and ChromeOS turn
/// freely, the way Android 16 runs them anyway at SDK 36, and the layout keeps
/// to its page column there (see DESIGN.md). It goes by the display rather
/// than the window, so split screen doesn't change it, and checks again when
/// the display changes, so folding back to the outer screen locks it again.
class _OrientationLock with WidgetsBindingObserver {
  _OrientationLock._();

  static final instance = _OrientationLock._();

  /// Android's large-screen line: a smallest width of 600dp.
  static const _largeScreen = 600.0;

  bool? _portrait;

  Future<void> apply() async {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final display = dispatcher.displays.firstOrNull;
    final view = dispatcher.implicitView;
    final size = display != null
        ? display.size / display.devicePixelRatio
        : (view != null ? view.physicalSize / view.devicePixelRatio : Size.zero);
    final portrait = size.shortestSide < _largeScreen;
    if (portrait == _portrait) return;
    _portrait = portrait;
    await SystemChrome.setPreferredOrientations(portrait ? [DeviceOrientation.portraitUp] : const []);
  }

  @override
  void didChangeMetrics() => unawaited(apply());
}
