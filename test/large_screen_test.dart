import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaulty/models/memory.dart';
import 'package:vaulty/screens/home_shell.dart';
import 'package:vaulty/services/auth_service.dart';
import 'package:vaulty/services/settings.dart';
import 'package:vaulty/state/vault_state.dart';
import 'package:vaulty/theme/app_theme.dart';
import 'package:vaulty/widgets/adaptive.dart';
import 'package:vaulty/widgets/common.dart';
import 'package:vaulty/widgets/memory_cards.dart';

/// Android 16 runs the app at any size and orientation on tablets, unfolded
/// foldables and ChromeOS. The phone layout keeps to a centred column there,
/// and nothing overflows in landscape or split screen.
void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  const phone = Size(412, 915);
  const tabletLandscape = Size(1280, 800);
  const windows = {
    'a phone': phone,
    'a tablet in landscape': tabletLandscape,
    'a tablet in portrait': Size(800, 1280),
    'an unfolded foldable in landscape': Size(841, 701),
    'an unfolded foldable in portrait': Size(701, 841),
    'half a tablet in split screen': Size(636, 800),
    'a short split-screen window': Size(800, 560),
  };

  void setWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Left edge and width of the page column in a window [width] wide.
  (double, double) column(double width) =>
      width > Space.column ? ((width - Space.column) / 2, Space.column) : (0, width);

  group('PageScrollView', () {
    Future<void> pump(WidgetTester tester, Size size) async {
      setWindow(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: const Scaffold(
            body: PageScrollView(
              slivers: [SliverToBoxAdapter(child: SizedBox(key: Key('content'), height: 3000))],
            ),
          ),
        ),
      );
    }

    for (final MapEntry(key: name, value: size) in {'a phone': phone, 'a wide window': tabletLandscape}.entries) {
      testWidgets('keeps its slivers to the page column on $name', (tester) async {
        await pump(tester, size);
        final rect = tester.getRect(find.byKey(const Key('content')));
        final (left, width) = column(size.width);
        expect(rect.left, left);
        expect(rect.width, width);
      });
    }

    testWidgets('still scrolls from the margin beside the column', (tester) async {
      await pump(tester, tabletLandscape);
      await tester.dragFrom(const Offset(40, 600), const Offset(0, -300));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const Key('content'))).dy, lessThan(0));
    });
  });

  group('on a wide window', () {
    Future<void> pumpButton(WidgetTester tester, void Function(BuildContext) onTap) async {
      setWindow(tester, tabletLandscape);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(onPressed: () => onTap(context), child: const Text('go')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('bottom sheets keep to the page column', (tester) async {
      await pumpButton(
        tester,
        (context) =>
            showVSheet<void>(context, (_) => const SizedBox(key: Key('sheet'), width: double.infinity, height: 200)),
      );
      final rect = tester.getRect(find.byKey(const Key('sheet')));
      expect(rect.width, Space.column);
      expect(rect.center.dx, tabletLandscape.width / 2);
    }, variant: android);

    testWidgets('snackbars keep to the page column', (tester) async {
      await pumpButton(tester, (context) => showToast(context, 'Saved'));
      // The snackbar's surface; the widget itself spans the window to centre it.
      final rect = tester.getRect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first);
      expect(rect.width, Space.column - 2 * Space.l);
      expect(rect.center.dx, tabletLandscape.width / 2);
    }, variant: android);
  });

  group('home', () {
    final now = DateTime.now();
    const mom = Tag(id: 'mom', name: 'Mom', kind: TagKind.person, uses: 2);
    const car = Tag(id: 'car', name: 'car', kind: TagKind.tag, uses: 1);
    Memory memory(
      String id,
      String title, {
      MemoryCategory category = MemoryCategory.staticFact,
      int? days,
      List<MetaEntry> metadata = const [],
      List<Tag> tags = const [],
    }) => Memory(
      id: id,
      title: title,
      category: category,
      expiryDate: days == null ? null : now.add(Duration(days: days)),
      createdAt: now,
      updatedAt: now,
      metadata: metadata,
      tags: tags,
    );
    final items = [
      memory('1', 'Passport', category: MemoryCategory.expiryDoc, days: 12),
      memory('2', 'Car insurance', category: MemoryCategory.expiryDoc, days: 45, tags: [car]),
      memory('3', 'Streaming', category: MemoryCategory.subscription, days: 3),
      memory('4', 'Gym membership', category: MemoryCategory.subscription, days: 90),
      memory('5', 'Driving licence', category: MemoryCategory.expiryDoc, days: -2),
      memory(
        '6',
        'Mom’s shoe size',
        category: MemoryCategory.measurement,
        metadata: const [MetaEntry(id: 'm1', key: 'Size', value: '7 US')],
        tags: [mom],
      ),
      memory(
        '7',
        'Wi-Fi password',
        metadata: const [MetaEntry(id: 'm2', key: 'Code', value: 'paper-ink-42')],
      ),
      memory(
        '8',
        'Hallway paint',
        metadata: const [MetaEntry(id: 'm3', key: 'Colour', value: 'Farrow 2005')],
      ),
    ];

    Future<void> pump(WidgetTester tester, Size size) async {
      setWindow(tester, size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            vaultProvider.overrideWith(() => _Vault(items)),
            tagsProvider.overrideWith((ref) async => const [mom, car]),
            archivedProvider.overrideWith((ref) async => const []),
            biometricProvider.overrideWith((ref) async => Biometric.faceId),
          ],
          child: MaterialApp(theme: AppTheme.build(Brightness.light), home: const HomeShell()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Finder tab(String label) => find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

    for (final MapEntry(key: name, value: size) in windows.entries) {
      testWidgets('fits $name, every tab', (tester) async {
        await pump(tester, size);
        final (left, width) = column(size.width);

        // Content and the nav capsule share the column and its 16-20pt gutters.
        final hero = tester.getRect(find.byType(HeroCard));
        expect(hero.left, left + Space.l);
        expect(hero.right, left + width - Space.l);
        expect(tester.getRect(tab('Vault')).left, greaterThanOrEqualTo(left + Space.page));
        expect(tester.getRect(tab('Add a memory')).right, left + width - Space.page);

        // Overflows fail the test on their own.
        for (final label in ['Radar', 'Search', 'You', 'Vault']) {
          await tester.tap(tab(label));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        }

        // Vo's blink waits on a plain delay; let it lapse once he's gone.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      }, variant: android);
    }
  });
}

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(onboarded: true, name: 'Sam');

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
