import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaulty/models/memory.dart';
import 'package:vaulty/screens/vault_home_screen.dart';
import 'package:vaulty/services/settings.dart';
import 'package:vaulty/state/vault_state.dart';
import 'package:vaulty/theme/app_theme.dart';

/// The home screen's backup card: there while a backup is due, gone after
/// "Later" or a fresh backup.
void main() {
  final now = DateTime.now();
  final items = [
    for (var i = 0; i < 3; i++)
      Memory(
        id: '$i',
        title: 'Memory $i',
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
  ];

  Future<_Settings> pump(WidgetTester tester, AppSettings initial) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late _Settings settings;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => settings = _Settings(initial)),
          vaultProvider.overrideWith(() => _Vault(items)),
          tagsProvider.overrideWith((ref) async => const []),
          archivedProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: VaultHomeScreen(onOpenRadar: () {}, onOpenSearch: () {}, onOpenMe: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return settings;
  }

  Future<void> settle(WidgetTester tester) async {
    // Vo's blink waits on a plain delay; let it lapse once he's gone.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('a vault never backed up asks for one, and "Later" hides it', (tester) async {
    final settings = await pump(tester, const AppSettings(onboarded: true));
    expect(find.text('Back up your vault'), findsOneWidget);
    expect(find.textContaining('3 memories live only on this phone'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(find.text('Back up your vault'), findsNothing);
    expect(settings.state.backupSnoozedUntil!.isAfter(now), isTrue);
    await settle(tester);
  });

  testWidgets('changes since an old backup bring it back', (tester) async {
    await pump(tester, AppSettings(onboarded: true, lastBackup: now.subtract(const Duration(days: 40))));
    expect(find.text('Time for a backup'), findsOneWidget);
    expect(find.textContaining('40 days ago'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('stays away after a recent backup, or with reminders off', (tester) async {
    await pump(tester, AppSettings(onboarded: true, lastBackup: now.subtract(const Duration(days: 3))));
    expect(find.text('Time for a backup'), findsNothing);
    await settle(tester);

    await pump(tester, const AppSettings(onboarded: true, backupEveryDays: 0));
    expect(find.text('Back up your vault'), findsNothing);
    await settle(tester);
  });
}

class _Settings extends SettingsNotifier {
  _Settings(this._initial);

  final AppSettings _initial;

  @override
  AppSettings build() => _initial;

  @override
  Future<void> change(AppSettings Function(AppSettings s) edit) async {
    state = edit(state);
  }
}

class _Vault extends VaultNotifier {
  _Vault(this._seed);

  final List<Memory> _seed;

  @override
  Future<List<Memory>> build() async => _seed;
}
