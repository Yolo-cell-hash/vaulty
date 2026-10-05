import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/memory.dart';
import '../theme/app_theme.dart';
import 'adaptive.dart';
import 'common.dart';
import 'glyphs.dart';

/// A renewal period on the "Renewed it!" sheet.
class RenewOption {
  const RenewOption(this.label, {this.months = 0, this.years = 0});
  final String label;
  final int months;
  final int years;

  DateTime from(DateTime base) {
    final y = base.year + years + (base.month - 1 + months) ~/ 12;
    final m = (base.month - 1 + months) % 12 + 1;
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, base.day > last ? last : base.day);
  }
}

const renewOptions = [
  RenewOption('1 month', months: 1),
  RenewOption('6 months', months: 6),
  RenewOption('1 year', years: 1),
  RenewOption('2 years', years: 2),
  RenewOption('5 years', years: 5),
  RenewOption('10 years', years: 10),
];

/// Most renewals continue from the old expiry date (insurance, subscriptions),
/// but if that would still be in the past, count from today instead.
DateTime renewBase(DateTime oldExpiry, DateTime today) {
  final old = DateTime(oldExpiry.year, oldExpiry.month, oldExpiry.day);
  return old.isBefore(DateTime(today.year - 1, today.month, today.day)) ? today : old;
}

/// Guesses the usual renewal period from the title.
RenewOption suggestedRenewal(Memory m) {
  final t = '${m.title} ${m.rawContent}'.toLowerCase();
  if (RegExp(r'passport').hasMatch(t)) return renewOptions[5];
  if (RegExp(r'licen[cs]e|\bdl\b|id card|aadhaar|visa').hasMatch(t)) return renewOptions[4];
  if (m.category == MemoryCategory.subscription || RegExp(r'monthly|/mo\b').hasMatch(t)) return renewOptions[0];
  return renewOptions[2];
}

/// "Renewed it!": pick the new expiry with one tap. Returns the new date.
Future<DateTime?> showRenewSheet(BuildContext context, Memory memory) {
  return showVSheet<DateTime>(context, (_) => _RenewSheet(memory: memory), isScrollControlled: true);
}

class _RenewSheet extends StatefulWidget {
  const _RenewSheet({required this.memory});
  final Memory memory;

  @override
  State<_RenewSheet> createState() => _RenewSheetState();
}

class _RenewSheetState extends State<_RenewSheet> {
  late final DateTime _base = renewBase(widget.memory.expiryDate!, DateUtils.dateOnly(DateTime.now()));
  late RenewOption? _option = suggestedRenewal(widget.memory);
  DateTime? _custom;

  DateTime get _date {
    if (_custom != null) return _custom!;
    final today = DateUtils.dateOnly(DateTime.now());
    final d = _option!.from(_base);
    // A short period on a long-lapsed item would still be in the past.
    return d.isBefore(today) ? _option!.from(today) : d;
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await pickDate(
      context,
      initial: _date,
      first: now,
      last: DateTime(now.year + 50),
      title: 'New expiry date',
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _option = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    final fmt = DateFormat('EEEE, d MMMM yyyy');
    final days = DateUtils.dateOnly(_date).difference(DateUtils.dateOnly(DateTime.now())).inDays;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Renewed '),
                    TextSpan(text: widget.memory.title, style: context.type.accent),
                    const TextSpan(text: '?'),
                  ],
                ),
                style: context.type.headline.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 6),
              Text('Nice. How long is it good for now?', style: context.type.bodySoft),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in renewOptions)
                    VChip(
                      label: '+ ${o.label}',
                      selected: _option == o,
                      onTap: () => setState(() {
                        _option = o;
                        _custom = null;
                      }),
                    ),
                  VChip(label: 'Pick a date', icon: G.calendar, selected: _custom != null, onTap: _pick),
                ],
              ),
              const SizedBox(height: 20),
              VCard(
                child: Row(
                  children: [
                    VIcon(G.calendar, size: 20, color: c.inkSoft),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New expiry', style: context.type.caption),
                          const SizedBox(height: 2),
                          Text(fmt.format(_date), style: context.type.item),
                        ],
                      ),
                    ),
                    Text('$days days', style: context.type.mono(13, c.inkSoft)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              VButton(
                label: 'Save new date',
                icon: G.check,
                onPressed: days < 0
                    ? null
                    : () {
                        Haptics.success();
                        Navigator.pop(context, _date);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
