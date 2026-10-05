import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'glyphs.dart';

/// An action revealed by swiping a row.
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.glyph,
    required this.color,
    required this.onTrigger,
    this.removes = false,
  });

  final String label;
  final G glyph;

  /// The button's fill. Its glyph and label are drawn in paper (obsidian in
  /// dark mode), so pick a saturated colour.
  final Color color;
  final Future<void> Function() onTrigger;

  /// The action takes the row out of the list (archive), so it slides away
  /// instead of springing back.
  final bool removes;
}

/// iOS table-row swipe actions: swipe partway to reveal a button and tap it,
/// or swipe all the way to fire it, with a tap of haptics as you cross the
/// line. Opening one row closes any other, and scrolling closes it.
class SwipeActions extends StatefulWidget {
  const SwipeActions({super.key, required this.child, this.leading, this.trailing});

  final Widget child;

  /// Revealed by swiping right.
  final SwipeAction? leading;

  /// Revealed by swiping left.
  final SwipeAction? trailing;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions> with TickerProviderStateMixin {
  static const _button = 84.0;

  /// The row that is open, so opening another one closes it.
  static final _open = ValueNotifier<_SwipeActionsState?>(null);

  /// Row offset in pixels: positive shows [SwipeActions.leading].
  late final _x = AnimationController.unbounded(vsync: this);

  /// Past the full-swipe line: releasing fires the action.
  bool _isArmed = false;

  /// Animates the label from the screen edge to the row's edge when armed.
  late final _armed = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
  ScrollPosition? _scroll;
  double _width = 0;

  double get _fullSwipe => math.max(_button * 1.6, _width * .5);

  @override
  void initState() {
    super.initState();
    _open.addListener(_onOpenChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroll?.removeListener(_onScroll);
    _scroll = Scrollable.maybeOf(context)?.position;
    _scroll?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _open.removeListener(_onOpenChanged);
    if (_open.value == this) _open.value = null;
    _scroll?.removeListener(_onScroll);
    _x.dispose();
    _armed.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    if (_open.value != this && _x.value != 0) _settle(0);
  }

  void _onScroll() {
    if (_x.value != 0 && !_x.isAnimating) _settle(0);
  }

  void _arm(bool armed, {bool haptic = true}) {
    if (armed == _isArmed) return;
    _isArmed = armed;
    if (armed && haptic) HapticFeedback.mediumImpact();
    armed ? _armed.forward() : _armed.reverse();
  }

  void _settle(double to) {
    if (to == 0 && _open.value == this) _open.value = null;
    _arm(false);
    _x.animateTo(to, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _dragStart(DragStartDetails _) {
    _x.stop();
    _open.value = this;
  }

  void _dragUpdate(DragUpdateDetails d) {
    var x = _x.value + d.delta.dx;
    if (widget.leading == null) x = math.min(x, 0);
    if (widget.trailing == null) x = math.max(x, 0);
    _x.value = x.clamp(-_width, _width);
    _arm(_x.value.abs() >= _fullSwipe);
  }

  void _dragEnd(DragEndDetails d) {
    final x = _x.value;
    final action = x > 0 ? widget.leading : widget.trailing;
    if (action == null || x == 0) return _settle(0);
    if (_isArmed) {
      _fire(action);
      return;
    }
    // Positive when the fling carries the row further open.
    final outward = (d.primaryVelocity ?? 0) * x.sign;
    final open = outward > 400 || (outward > -400 && x.abs() > _button / 2);
    _settle(open ? x.sign * _button : 0);
  }

  Future<void> _fire(SwipeAction action) async {
    final sign = identical(action, widget.leading) ? 1.0 : -1.0;
    if (_open.value == this) _open.value = null;
    if (!action.removes) {
      _settle(0);
      await action.onTrigger();
      return;
    }
    _arm(true, haptic: false);
    await _x.animateTo(sign * _width, duration: const Duration(milliseconds: 220), curve: Curves.easeIn);
    await action.onTrigger();
    // The list drops the row on its next frame; if it's still here, the
    // action didn't take it, so bring it back.
    await SchedulerBinding.instance.endOfFrame;
    if (mounted) _settle(0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        return Semantics(
          // VoiceOver lists swipe actions under "Actions", as for a table row.
          customSemanticsActions: {
            if (widget.leading case final a?) CustomSemanticsAction(label: a.label): () => _fire(a),
            if (widget.trailing case final a?) CustomSemanticsAction(label: a.label): () => _fire(a),
          },
          child: GestureDetector(
            onHorizontalDragStart: _dragStart,
            onHorizontalDragUpdate: _dragUpdate,
            onHorizontalDragEnd: _dragEnd,
            child: AnimatedBuilder(
              animation: Listenable.merge([_x, _armed]),
              builder: (context, child) {
                final x = _x.value;
                final action = x > 0 ? widget.leading : (x < 0 ? widget.trailing : null);
                return Stack(
                  children: [
                    if (action != null)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: x > 0 ? 0 : null,
                        right: x < 0 ? 0 : null,
                        width: x.abs(),
                        child: _pane(action, x),
                      ),
                    Transform.translate(offset: Offset(x, 0), child: child),
                    // While open, a tap on the row closes it instead of opening it.
                    if (x != 0)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: math.max(x, 0),
                        right: math.max(-x, 0),
                        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _settle(0)),
                      ),
                  ],
                );
              },
              child: widget.child,
            ),
          ),
        );
      },
    );
  }

  Widget _pane(SwipeAction a, double x) {
    final w = x.abs();
    final fg = context.vc.onInk;
    // At rest the label waits at the screen edge; armed, it rides the row.
    final outer = x > 0 ? 0.0 : w - _button;
    final inner = x > 0 ? w - _button : 0.0;
    return GestureDetector(
      onTap: () => _fire(a),
      child: ClipRect(
        child: ColoredBox(
          color: a.color,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                bottom: 0,
                width: _button,
                left: lerpDouble(outer, inner, Curves.easeOut.transform(_armed.value)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    VIcon(a.glyph, size: 20, color: fg, stroke: 1.9),
                    const SizedBox(height: 4),
                    Text(
                      a.label,
                      maxLines: 1,
                      style: context.type.caption.copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
