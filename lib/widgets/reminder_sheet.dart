import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/memory.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'glyphs.dart';

/// What the reminder sheet returns. `null` offsets/minutes mean "use defaults".
class ReminderChoice {
  const ReminderChoice({required this.remind, this.offsets, this.minutes});

  final bool remind;
  final List<int>? offsets;
  final int? minutes;
}

/// Per-item reminders (or, with [forDefaults], the app-wide defaults).
Future<ReminderChoice?> showReminderSheet(
  BuildContext context, {
  required ReminderDefaults defaults,
  List<int>? offsets,
  int? minutes,
  bool remind = true,
  Recurrence recurrence = Recurrence.none,
  bool forDefaults = false,
}) {
  return showModalBottomSheet<ReminderChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReminderSheet(
      defaults: defaults,
      offsets: offsets,
      minutes: minutes,
      remind: remind,
      recurrence: recurrence,
      forDefaults: forDefaults,
    ),
  );
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({
    required this.defaults,
    required this.offsets,
    required this.minutes,
    required this.remind,
    required this.recurrence,
    required this.forDefaults,
  });

  final ReminderDefaults defaults;
  final List<int>? offsets;
  final int? minutes;
  final bool remind;
  final Recurrence recurrence;
  final bool forDefaults;

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late bool _remind = widget.remind;
  late bool _custom = widget.forDefaults || widget.offsets != null || widget.minutes != null;

  /// What applies when nothing custom is set: the cadence default for
  /// repeating dates, the app default otherwise.
  List<int> get _defaultList => widget.forDefaults || widget.recurrence == Recurrence.none
      ? widget.defaults.offsets
      : widget.recurrence.reminderOffsets;

  late Set<int> _offsets = {...(widget.offsets ?? _defaultList)};
  late int _minutes = widget.minutes ?? widget.defaults.minutes;

  List<int> get _sorted => _offsets.toList()..sort((a, b) => b.compareTo(a));

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _minutes ~/ 60, minute: _minutes % 60),
      helpText: 'Remind me at',
    );
    if (picked != null) {
      setState(() {
        _minutes = picked.hour * 60 + picked.minute;
        _custom = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final usingDefaults = !widget.forDefaults && !_custom;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SafeArea(
        // Scrolls when large text makes it taller than the sheet allows.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.forDefaults ? 'Default reminders' : 'Reminders',
                style: context.type.headline.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 6),
              Text(
                widget.forDefaults
                    ? 'Used for anything with a date, unless you set something else on it.'
                    : 'When should Vaulty nudge you about this one?',
                style: context.type.bodySoft,
              ),
              const SizedBox(height: 18),
              if (!widget.forDefaults) ...[
                VCard(
                  padding: EdgeInsets.zero,
                  child: ListRow(
                    title: 'Remind me',
                    glyph: G.bell,
                    chevron: false,
                    trailing: Switch.adaptive(
                      value: _remind,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _remind = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              AnimatedOpacity(
                opacity: _remind ? 1 : .35,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !_remind,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Eyebrow('Before it’s due'),
                          const SizedBox(width: 12),
                          if (usingDefaults)
                            Expanded(
                              child: Text(
                                widget.recurrence == Recurrence.none
                                    ? 'Using your defaults'
                                    : 'Using the repeat default',
                                textAlign: TextAlign.end,
                                style: context.type.caption,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d in ReminderDefaults.choices)
                            VChip(
                              label: offsetShort(d),
                              selected: (usingDefaults ? _defaultList : _offsets).contains(d),
                              onTap: () => setState(() {
                                if (usingDefaults) {
                                  _offsets = {..._defaultList};
                                  _custom = true;
                                }
                                _offsets.contains(d) ? _offsets.remove(d) : _offsets.add(d);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Eyebrow('At'),
                      const SizedBox(height: 10),
                      VCard(
                        onTap: _pickTime,
                        semanticLabel: 'Reminder time, ${timeLabel(_minutes)}. Change',
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Row(
                          children: [
                            VIcon(G.clock, size: 20, color: c.inkSoft),
                            const SizedBox(width: 14),
                            Expanded(child: Text(timeLabel(_minutes), style: context.type.mono(18))),
                            Text(
                              'Change',
                              style: context.type.caption.copyWith(color: c.brand, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  if (!widget.forDefaults && _custom)
                    Expanded(
                      child: VButton(
                        label: 'Use defaults',
                        kind: ButtonStyleKind.outline,
                        onPressed: () => Navigator.pop(context, ReminderChoice(remind: _remind)),
                      ),
                    ),
                  if (!widget.forDefaults && _custom) const SizedBox(width: 10),
                  Expanded(
                    child: VButton(
                      label: 'Save',
                      onPressed: widget.forDefaults && _offsets.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context,
                              ReminderChoice(
                                remind: _remind,
                                offsets: _custom ? _sorted : null,
                                minutes: _custom ? _minutes : null,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
