import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'common.dart';
import 'glyphs.dart';

// Platform pieces. Android keeps its Material dialogs, sheets and pickers;
// iOS gets the system's own: alerts, action sheets, pull-down menus and
// wheels. What sits inside them (brand type, glyphs, colours) doesn't change.

/// Haptics in each platform's vocabulary. iOS has dedicated success and
/// error patterns; Android keeps the impacts it has always used.
abstract final class Haptics {
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  /// Something saved, unlocked or finished.
  static void success() => _ios ? HapticFeedback.successNotification() : HapticFeedback.mediumImpact();

  /// Something refused: a failed unlock, a wrong passphrase.
  static void error() => _ios ? HapticFeedback.errorNotification() : HapticFeedback.heavyImpact();
}

/// A bottom sheet for a short task. On iOS it takes the system grabber and
/// dim (see [AppTheme]) and is presented from the root, so one opened inside
/// a flow sheet covers the screen like a native stacked sheet.
Future<T?> showVSheet<T>(BuildContext context, WidgetBuilder builder, {bool isScrollControlled = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useRootNavigator: context.isCupertino,
    builder: builder,
  );
}

// ---------------------------------------------------------------- pickers --

/// Picks a day: the Material calendar on Android, the date wheel on iOS.
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
  required String title,
}) async {
  if (!context.isCupertino) {
    return showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last, helpText: title);
  }
  // The wheel asserts its start sits inside the range, to the second.
  final min = DateUtils.dateOnly(first), max = DateUtils.dateOnly(last);
  var value = DateUtils.dateOnly(initial);
  if (value.isBefore(min)) value = min;
  if (value.isAfter(max)) value = max;
  final done = await _showWheel(
    context,
    title: title,
    wheel: CupertinoDatePicker(
      mode: CupertinoDatePickerMode.date,
      initialDateTime: value,
      minimumDate: min,
      maximumDate: max,
      onDateTimeChanged: (d) => value = d,
    ),
  );
  return done ? DateUtils.dateOnly(value) : null;
}

/// Picks a time of day: the Material clock on Android, the time wheel on iOS.
Future<TimeOfDay?> pickTime(BuildContext context, {required TimeOfDay initial, required String title}) async {
  if (!context.isCupertino) return showTimePicker(context: context, initialTime: initial, helpText: title);
  var value = DateTime(2000, 1, 1, initial.hour, initial.minute);
  final done = await _showWheel(
    context,
    title: title,
    wheel: CupertinoDatePicker(
      mode: CupertinoDatePickerMode.time,
      initialDateTime: value,
      use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      onDateTimeChanged: (d) => value = d,
    ),
  );
  return done ? TimeOfDay.fromDateTime(value) : null;
}

/// The panel iOS slides up for a wheel: Cancel, a title, Done.
Future<bool> _showWheel(BuildContext context, {required String title, required Widget wheel}) async {
  final done = await showCupertinoModalPopup<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.vc;
      final text = CupertinoTheme.of(ctx).textTheme;
      return DefaultTextStyle(
        style: text.textStyle,
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.m)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      CupertinoButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.navTitleTextStyle,
                        ),
                      ),
                      CupertinoButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                const Hairline(),
                SizedBox(height: 216, child: wheel),
              ],
            ),
          ),
        ),
      );
    },
  );
  return done ?? false;
}

// ---------------------------------------------------------- iOS prompts --

/// iOS: one line of text in an alert, the way Photos renames an album.
/// Android screens use their own sheets for this.
Future<String?> showTextAlert(
  BuildContext context, {
  required String title,
  String? message,
  String initial = '',
  String placeholder = '',
  String confirm = 'Save',
  TextCapitalization capitalization = TextCapitalization.none,
  int? maxLength,
  bool allowEmpty = false,
}) {
  return showCupertinoDialog<String>(
    context: context,
    builder: (_) => _TextAlert(
      title: title,
      message: message,
      initial: initial,
      placeholder: placeholder,
      confirm: confirm,
      capitalization: capitalization,
      maxLength: maxLength,
      allowEmpty: allowEmpty,
    ),
  );
}

class _TextAlert extends StatefulWidget {
  const _TextAlert({
    required this.title,
    required this.message,
    required this.initial,
    required this.placeholder,
    required this.confirm,
    required this.capitalization,
    required this.maxLength,
    required this.allowEmpty,
  });

  final String title;
  final String? message;
  final String initial;
  final String placeholder;
  final String confirm;
  final TextCapitalization capitalization;
  final int? maxLength;
  final bool allowEmpty;

  @override
  State<_TextAlert> createState() => _TextAlertState();
}

class _TextAlertState extends State<_TextAlert> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => widget.allowEmpty || _text.text.trim().isNotEmpty;

  void _submit() {
    if (_valid) Navigator.pop(context, _text.text);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Column(
        children: [
          if (widget.message != null) ...[
            Text(widget.message!),
            const SizedBox(height: 12),
          ] else
            const SizedBox(height: 8),
          CupertinoTextField(
            controller: _text,
            autofocus: true,
            placeholder: widget.placeholder,
            textCapitalization: widget.capitalization,
            maxLength: widget.maxLength,
            clearButtonMode: OverlayVisibilityMode.editing,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        CupertinoDialogAction(isDefaultAction: true, onPressed: _valid ? _submit : null, child: Text(widget.confirm)),
      ],
    );
  }
}

/// iOS: a choice from an action sheet, with Cancel apart at the bottom.
/// Returns the chosen value, or null when cancelled.
Future<T?> showActionSheet<T>(BuildContext context, List<(String label, T value)> options, {String? title}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: title == null ? null : Text(title),
      actions: [
        for (final (label, value) in options)
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, value), child: Text(label)),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ),
  );
}

// ------------------------------------------------------------------- menus --

/// An entry in a [MenuButton].
class MenuAction {
  const MenuAction(this.label, this.glyph, this.onSelected, {this.destructive = false});

  final String label;
  final G glyph;
  final VoidCallback onSelected;
  final bool destructive;
}

/// The "more" button. iOS: a pull-down menu anchored to the button. Android:
/// a sheet of rows, and the chosen action runs once the sheet has gone.
class MenuButton extends StatelessWidget {
  const MenuButton({super.key, required this.actions, this.glyph = G.more, this.label = 'More'});

  final List<MenuAction> actions;
  final G glyph;
  final String label;

  Future<void> _sheet(BuildContext context) async {
    final i = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: ListGroup(
            children: [
              for (var i = 0; i < actions.length; i++)
                ListRow(
                  title: actions[i].label,
                  glyph: actions[i].glyph,
                  danger: actions[i].destructive,
                  chevron: false,
                  onTap: () => Navigator.pop(ctx, i),
                ),
            ],
          ),
        ),
      ),
    );
    if (i != null) actions[i].onSelected();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.isCupertino) return VIconButton(glyph, label: label, onTap: () => _sheet(context));
    return CupertinoMenuAnchor(
      menuChildren: [
        for (final a in actions)
          CupertinoMenuItem(
            // No colour: the menu tints it, red for destructive items.
            trailing: VIcon(a.glyph, size: 21),
            isDestructiveAction: a.destructive,
            onPressed: a.onSelected,
            child: Text(a.label),
          ),
      ],
      builder: (context, controller, _) =>
          VIconButton(glyph, label: label, onTap: () => controller.isOpen ? controller.close() : controller.open()),
    );
  }
}
