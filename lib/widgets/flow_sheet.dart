import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Opens a self-contained task (capture, scan, edit).
///
/// Android pushes it as a page. iOS presents it the way iOS presents a
/// compose or edit screen: a sheet that pushes the current page back into a
/// stacked card and can be swiped down to dismiss. The sheet has its own
/// navigator, so a step can replace itself inside it (scan, then edit).
///
/// Leave a flow with [closeFlow], never `Navigator.pop`, so the whole sheet
/// closes on iOS and not just the current step.
Future<T?> presentFlow<T>(BuildContext context, WidgetBuilder page) {
  if (!context.isCupertino) return Navigator.of(context).push<T>(MaterialPageRoute(builder: page));
  final locked = ValueNotifier(false);
  return Navigator.of(context, rootNavigator: true).push<T>(
    _FlowSheetRoute<T>(
      locked: locked,
      scrollableBuilder: (context, scroll) => _FlowNavigator(page: page, locked: locked, scroll: scroll),
    ),
  );
}

/// Ends the flow that [context] is in, from any step.
void closeFlow<T>(BuildContext context, [T? result]) {
  final scope = context.getInheritedWidgetOfExactType<_FlowScope>();
  if (scope == null) {
    Navigator.of(context).pop(result);
  } else {
    scope.route.navigator?.pop(result);
  }
}

/// Stops an iOS flow sheet from being swiped away while [locked], the way
/// iOS holds a sheet that has unsaved changes. The page's own close button
/// asks before discarding. Does nothing outside a flow sheet.
class DismissGuard extends StatefulWidget {
  const DismissGuard({super.key, required this.locked, required this.child});

  final bool locked;
  final Widget child;

  @override
  State<DismissGuard> createState() => _DismissGuardState();
}

class _DismissGuardState extends State<DismissGuard> {
  ValueNotifier<bool>? _lock;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lock = context.getInheritedWidgetOfExactType<_FlowScope>()?.locked;
    _sync();
  }

  @override
  void didUpdateWidget(DismissGuard old) {
    super.didUpdateWidget(old);
    if (old.locked != widget.locked) _sync();
  }

  // Flipping the lock rebuilds the sheet above us, so not mid-build.
  void _sync() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _lock?.value = widget.locked;
  });

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FlowSheetRoute<T> extends CupertinoSheetRoute<T> {
  _FlowSheetRoute({required this.locked, required super.scrollableBuilder}) {
    // The drag handler reads this when the route builds, so rebuild on change.
    locked.addListener(changedInternalState);
  }

  final ValueNotifier<bool> locked;

  @override
  bool get enableDrag => !locked.value;
}

class _FlowScope extends InheritedWidget {
  const _FlowScope({required this.route, required this.locked, required super.child});

  final ModalRoute<Object?> route;
  final ValueNotifier<bool> locked;

  @override
  bool updateShouldNotify(_FlowScope old) => false;
}

class _FlowNavigator extends StatefulWidget {
  const _FlowNavigator({required this.page, required this.locked, required this.scroll});

  final WidgetBuilder page;
  final ValueNotifier<bool> locked;

  /// The sheet's controller: a list using it hands a pull-down at its top to
  /// the sheet, so dragging the content down dismisses like on iOS.
  final ScrollController scroll;

  @override
  State<_FlowNavigator> createState() => _FlowNavigatorState();
}

class _FlowNavigatorState extends State<_FlowNavigator> {
  /// Stands in for the sheet's controller while the flow is locked, since a
  /// scroll-linked pull would otherwise dismiss it anyway.
  final _detached = ScrollController();

  @override
  void dispose() {
    _detached.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FlowScope(
      route: ModalRoute.of(context)!,
      locked: widget.locked,
      child: Navigator(
        onGenerateInitialRoutes: (_, _) => [
          MaterialPageRoute<void>(
            // Only the first page links its list to the sheet. A step that
            // replaces it keeps its own controller (two lists on the sheet's
            // controller would fight over the drag), and is dismissed from
            // its bar instead.
            builder: (context) => ValueListenableBuilder<bool>(
              valueListenable: widget.locked,
              builder: (context, locked, child) =>
                  PrimaryScrollController(controller: locked ? _detached : widget.scroll, child: child!),
              child: Builder(builder: widget.page),
            ),
          ),
        ],
      ),
    );
  }
}
