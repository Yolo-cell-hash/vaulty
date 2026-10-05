import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaulty/theme/app_theme.dart';
import 'package:vaulty/widgets/adaptive.dart';
import 'package:vaulty/widgets/common.dart';
import 'package:vaulty/widgets/flow_sheet.dart';
import 'package:vaulty/widgets/glyphs.dart';
import 'package:vaulty/widgets/swipe_actions.dart';

/// Each platform gets its own system pieces: Material on Android, the iOS
/// equivalents on iOS. These pin which one appears and that both behave.
void main() {
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  /// Pumps a page with one button that runs [onTap] with a live context.
  Future<void> pumpButton(WidgetTester tester, void Function(BuildContext) onTap) async {
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

  group('confirmDialog', () {
    testWidgets('is an iOS alert with Cancel first', (tester) async {
      bool? result;
      await pumpButton(tester, (context) async {
        result = await confirmDialog(
          context,
          title: 'Erase?',
          message: 'Gone for good.',
          confirm: 'Erase',
          destructive: true,
        );
      });
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      final actions = tester.widgetList<CupertinoDialogAction>(find.byType(CupertinoDialogAction)).toList();
      expect(actions.first.isDefaultAction, isTrue, reason: 'Cancel is bold when the other choice destroys data');
      expect(actions.last.isDestructiveAction, isTrue);
      await tester.tap(find.text('Erase'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    }, variant: ios);

    testWidgets('stays a Material dialog on Android', (tester) async {
      bool? result;
      await pumpButton(tester, (context) async {
        result = await confirmDialog(context, title: 'Erase?', message: 'Gone for good.', confirm: 'Erase');
      });
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    }, variant: android);
  });

  group('pickDate', () {
    testWidgets('is a date wheel on iOS, starting inside the range', (tester) async {
      DateTime? picked;
      final now = DateTime.now();
      await pumpButton(tester, (context) async {
        // Starts before the range: the wheel would assert if not clamped.
        picked = await pickDate(
          context,
          initial: now.subtract(const Duration(days: 3)),
          first: now,
          last: DateTime(now.year + 5),
          title: 'New expiry date',
        );
      });
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.text('New expiry date'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(picked, DateUtils.dateOnly(now));
    }, variant: ios);

    testWidgets('returns nothing when cancelled', (tester) async {
      DateTime? picked = DateTime(2000);
      await pumpButton(tester, (context) async {
        picked = await pickDate(
          context,
          initial: DateTime(2030, 6, 1),
          first: DateTime(2020),
          last: DateTime(2040),
          title: 'Pick a date',
        );
      });
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(picked, isNull);
    }, variant: ios);

    testWidgets('is the Material calendar on Android', (tester) async {
      await pumpButton(tester, (context) {
        pickDate(context, initial: DateTime(2030, 6, 1), first: DateTime(2020), last: DateTime(2040), title: 'Pick');
      });
      expect(find.byType(CupertinoDatePicker), findsNothing);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    }, variant: android);
  });

  testWidgets('pickTime is a time wheel on iOS', (tester) async {
    TimeOfDay? picked;
    await pumpButton(tester, (context) async {
      picked = await pickTime(context, initial: const TimeOfDay(hour: 9, minute: 30), title: 'Remind me at');
    });
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 9, minute: 30));
  }, variant: ios);

  testWidgets('showTextAlert needs text unless empty is allowed', (tester) async {
    String? name = 'unchanged';
    await pumpButton(tester, (context) async {
      name = await showTextAlert(context, title: 'Rename tag', initial: 'car');
    });
    await tester.enterText(find.byType(CupertinoTextField), '');
    await tester.pump();
    final save = tester.widget<CupertinoDialogAction>(find.widgetWithText(CupertinoDialogAction, 'Save'));
    expect(save.onPressed, isNull);
    await tester.enterText(find.byType(CupertinoTextField), 'travel');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(name, 'travel');
  }, variant: ios);

  group('toasts', () {
    testWidgets('drop in from the top on iOS, with a working action', (tester) async {
      var undone = false;
      await pumpButton(tester, (context) {
        showToast(context, 'Deleted “Passport”', icon: G.trash, action: ToastAction('Undo', () => undone = true));
      });
      expect(find.byType(SnackBar), findsNothing);
      final toast = tester.getRect(find.text('Deleted “Passport”'));
      expect(toast.top, lessThan(100), reason: 'sits under the status bar, not above the nav');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, isTrue);
      expect(find.text('Deleted “Passport”'), findsNothing);
    }, variant: ios);

    testWidgets('leave by themselves', (tester) async {
      await pumpButton(tester, (context) => showToast(context, 'Copied'));
      expect(find.text('Copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Copied'), findsNothing);
    }, variant: ios);

    testWidgets('are snackbars on Android', (tester) async {
      await pumpButton(tester, (context) => showToast(context, 'Copied'));
      expect(find.byType(SnackBar), findsOneWidget);
    }, variant: android);
  });

  group('flows', () {
    Widget step(String label, {Widget? next}) => Builder(
      builder: (context) => Scaffold(
        body: Column(
          children: [
            Text(label),
            if (next != null)
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next)),
                child: const Text('next'),
              ),
            TextButton(onPressed: () => closeFlow(context), child: const Text('close')),
          ],
        ),
      ),
    );

    testWidgets('open as a sheet on iOS and close whole from a later step', (tester) async {
      await pumpButton(tester, (context) => presentFlow<void>(context, (_) => step('scan', next: step('edit'))));
      expect(find.byType(CupertinoSheetTransition), findsWidgets);
      await tester.tap(find.text('next'));
      await tester.pumpAndSettle();
      expect(find.text('edit'), findsOneWidget);
      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      expect(find.text('edit'), findsNothing);
      expect(find.text('go'), findsOneWidget);
    }, variant: ios);

    testWidgets('a guard holds the sheet against a swipe down', (tester) async {
      await pumpButton(
        tester,
        (context) => presentFlow<void>(
          context,
          (_) => const DismissGuard(
            locked: true,
            child: Scaffold(body: SizedBox.expand(child: Text('editing'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.fling(find.text('editing'), const Offset(0, 500), 2000);
      await tester.pumpAndSettle();
      expect(find.text('editing'), findsOneWidget);
    }, variant: ios);

    testWidgets('without a guard, a swipe down dismisses it', (tester) async {
      await pumpButton(
        tester,
        (context) => presentFlow<void>(context, (_) => const Scaffold(body: SizedBox.expand(child: Text('reading')))),
      );
      await tester.fling(find.text('reading'), const Offset(0, 500), 2000);
      await tester.pumpAndSettle();
      expect(find.text('reading'), findsNothing);
    }, variant: ios);

    testWidgets('are plain pages on Android', (tester) async {
      await pumpButton(tester, (context) => presentFlow<void>(context, (_) => step('scan', next: step('edit'))));
      expect(find.byType(CupertinoSheetTransition), findsNothing);
      await tester.tap(find.text('next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);
    }, variant: android);
  });

  group('SwipeActions', () {
    Future<List<String>> pumpRow(WidgetTester tester) async {
      final fired = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: ListView(
              children: [
                SwipeActions(
                  leading: SwipeAction(
                    label: 'Renewed',
                    glyph: G.repeat,
                    color: Colors.green,
                    onTrigger: () async => fired.add('renew'),
                  ),
                  trailing: SwipeAction(
                    label: 'Archive',
                    glyph: G.archive,
                    color: Colors.indigo,
                    removes: true,
                    onTrigger: () async => fired.add('archive'),
                  ),
                  child: const SizedBox(height: 64, child: Center(child: Text('Passport'))),
                ),
              ],
            ),
          ),
        ),
      );
      return fired;
    }

    testWidgets('a full swipe fires the action', (tester) async {
      final fired = await pumpRow(tester);
      await tester.drag(find.text('Passport'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(fired, ['archive']);
    });

    testWidgets('a partial swipe opens the button, which fires on tap', (tester) async {
      final fired = await pumpRow(tester);
      await tester.drag(find.text('Passport'), const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(fired, isEmpty);
      await tester.tap(find.text('Renewed'));
      await tester.pumpAndSettle();
      expect(fired, ['renew']);
    });

    testWidgets('a short swipe springs back', (tester) async {
      final fired = await pumpRow(tester);
      await tester.drag(find.text('Passport'), const Offset(-20, 0));
      await tester.pumpAndSettle();
      expect(fired, isEmpty);
      expect(find.text('Archive'), findsNothing);
    });
  });

  testWidgets('MenuButton is a pull-down menu on iOS', (tester) async {
    var archived = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              MenuButton(
                actions: [
                  MenuAction('Archive', G.archive, () => archived = true),
                  MenuAction('Delete', G.trash, () {}, destructive: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoMenuItem), findsNWidgets(2));
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(archived, isTrue);
  }, variant: ios);
}
