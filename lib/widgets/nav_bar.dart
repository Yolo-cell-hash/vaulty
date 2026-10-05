import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The bar on pushed pages. On iOS it also follows the scroll edge, the way a
/// navigation bar does there: a hairline appears once content slides under
/// it, and [largeTitle] (the serif title in the body) settles into the bar
/// once it has scrolled out of view.
PreferredSizeWidget vAppBar(
  BuildContext context, {
  Widget? leading,
  String? title,
  String? largeTitle,
  List<Widget>? actions,
}) {
  final ios = context.isCupertino;
  return AppBar(
    leading: leading,
    title: title != null ? Text(title) : (ios && largeTitle != null ? _InlineTitle(largeTitle) : null),
    actions: actions,
    bottom: ios ? const _EdgeLine() : null,
  );
}

/// Tracks how far the page under a Scaffold has scrolled.
mixin _FollowsScroll<T extends StatefulWidget> on State<T> {
  ScrollNotificationObserverState? _observer;

  void onOffset(double pixels);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_handle);
    _observer = ScrollNotificationObserver.maybeOf(context);
    _observer?.addListener(_handle);
  }

  @override
  void dispose() {
    _observer?.removeListener(_handle);
    super.dispose();
  }

  void _handle(ScrollNotification n) {
    // The page itself, not a photo strip or a text field inside it.
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) onOffset(n.metrics.pixels);
  }
}

class _InlineTitle extends StatefulWidget {
  const _InlineTitle(this.text);

  final String text;

  @override
  State<_InlineTitle> createState() => _InlineTitleState();
}

class _InlineTitleState extends State<_InlineTitle> with _FollowsScroll {
  bool _shown = false;

  @override
  void onOffset(double pixels) {
    // Roughly when the serif title has gone under the bar.
    final shown = pixels > 56;
    if (shown != _shown) setState(() => _shown = shown);
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _shown ? 1 : 0,
    duration: const Duration(milliseconds: 180),
    child: Text(widget.text, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

class _EdgeLine extends StatefulWidget implements PreferredSizeWidget {
  const _EdgeLine();

  @override
  Size get preferredSize => Size.zero;

  @override
  State<_EdgeLine> createState() => _EdgeLineState();
}

class _EdgeLineState extends State<_EdgeLine> with _FollowsScroll {
  bool _shown = false;

  @override
  void onOffset(double pixels) {
    final shown = pixels > 0;
    if (shown != _shown) setState(() => _shown = shown);
  }

  // Zero height, so the bar doesn't grow: the line hangs just below it.
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 0,
    child: OverflowBox(
      alignment: Alignment.topCenter,
      maxHeight: 1,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.vc.line, width: 0)),
          ),
        ),
      ),
    ),
  );
}

/// iOS root tabs: once the header scrolls away, a frosted bar with an inline
/// title settles under the status bar, like a collapsed large-title bar.
/// Elsewhere it's just [child].
class ScrollEdgeBar extends StatefulWidget {
  const ScrollEdgeBar({super.key, required this.title, required this.child, this.threshold = 56});

  final Widget title;
  final Widget child;

  /// Scroll offset at which the page's own header is out of sight.
  final double threshold;

  @override
  State<ScrollEdgeBar> createState() => _ScrollEdgeBarState();
}

class _ScrollEdgeBarState extends State<ScrollEdgeBar> {
  bool _shown = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      final shown = n.metrics.pixels > widget.threshold;
      if (shown != _shown) setState(() => _shown = shown);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!context.isCupertino) return widget.child;
    final c = context.vc;
    final top = MediaQuery.paddingOf(context).top;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top + 44,
            child: IgnorePointer(
              ignoring: !_shown,
              child: AnimatedOpacity(
                opacity: _shown ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.bg.withValues(alpha: .78),
                        border: Border(bottom: BorderSide(color: c.line, width: 0)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(top: top),
                        child: Center(
                          child: DefaultTextStyle(
                            style: context.type.item,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            child: widget.title,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
