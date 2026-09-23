import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory.dart';
import 'secure_keys.dart';

class AppSettings {
  const AppSettings({
    this.onboarded = false,
    this.name = '',
    this.goals = const [],
    this.lockEnabled = false,
    this.themeMode = ThemeMode.light,
    this.streak = 0,
    this.lastOpenDay = '',
    this.lastBackup,
    this.reminderMinutes = 9 * 60,
    this.reminderOffsets = ReminderDefaults.standardOffsets,
  });

  final bool onboarded;
  final String name;
  final List<String> goals;
  final bool lockEnabled;
  final ThemeMode themeMode;
  final int streak;
  final String lastOpenDay;
  final DateTime? lastBackup;

  /// Default reminder time of day (minutes after midnight).
  final int reminderMinutes;

  /// Default lead times (days before) for one-off dates.
  final List<int> reminderOffsets;

  ReminderDefaults get reminders => ReminderDefaults(offsets: reminderOffsets, minutes: reminderMinutes);

  String get displayName => name.trim().isEmpty ? 'friend' : name.trim();

  AppSettings copyWith({
    bool? onboarded,
    String? name,
    List<String>? goals,
    bool? lockEnabled,
    ThemeMode? themeMode,
    int? streak,
    String? lastOpenDay,
    DateTime? lastBackup,
    int? reminderMinutes,
    List<int>? reminderOffsets,
  }) => AppSettings(
    onboarded: onboarded ?? this.onboarded,
    name: name ?? this.name,
    goals: goals ?? this.goals,
    lockEnabled: lockEnabled ?? this.lockEnabled,
    themeMode: themeMode ?? this.themeMode,
    streak: streak ?? this.streak,
    lastOpenDay: lastOpenDay ?? this.lastOpenDay,
    lastBackup: lastBackup ?? this.lastBackup,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    reminderOffsets: reminderOffsets ?? this.reminderOffsets,
  );

  static Future<AppSettings> load() async {
    final all = await SecureKeys.readAll();
    return AppSettings(
      onboarded: all['pref_onboarded'] == '1',
      name: all['pref_name'] ?? '',
      goals: (all['pref_goals'] ?? '').split('|').where((g) => g.isNotEmpty).toList(),
      lockEnabled: all['pref_lock'] == '1',
      themeMode: ThemeMode.values.firstWhere((m) => m.name == all['pref_theme'], orElse: () => ThemeMode.light),
      streak: int.tryParse(all['pref_streak'] ?? '') ?? 0,
      lastOpenDay: all['pref_last_open'] ?? '',
      lastBackup: DateTime.tryParse(all['pref_last_backup'] ?? ''),
      reminderMinutes: int.tryParse(all['pref_reminder_minutes'] ?? '') ?? 9 * 60,
      reminderOffsets: _offsets(all['pref_reminder_offsets']) ?? ReminderDefaults.standardOffsets,
    );
  }

  Future<void> save() async {
    await SecureKeys.write('pref_onboarded', onboarded ? '1' : '0');
    await SecureKeys.write('pref_name', name);
    await SecureKeys.write('pref_goals', goals.join('|'));
    await SecureKeys.write('pref_lock', lockEnabled ? '1' : '0');
    await SecureKeys.write('pref_theme', themeMode.name);
    await SecureKeys.write('pref_streak', '$streak');
    await SecureKeys.write('pref_last_open', lastOpenDay);
    await SecureKeys.write('pref_last_backup', lastBackup?.toIso8601String() ?? '');
    await SecureKeys.write('pref_reminder_minutes', '$reminderMinutes');
    await SecureKeys.write('pref_reminder_offsets', reminderOffsets.join(','));
  }

  static List<int>? _offsets(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final list = raw.split(',').map(int.tryParse).whereType<int>().toList();
    return list.isEmpty ? null : list;
  }

  /// Bumps the daily-open streak shown in the header.
  AppSettings withStreakTick(DateTime now) {
    String key(DateTime d) => '${d.year}-${d.month}-${d.day}';
    final today = key(now);
    if (lastOpenDay == today) return this;
    final yesterday = key(now.subtract(const Duration(days: 1)));
    return copyWith(streak: lastOpenDay == yesterday ? streak + 1 : 1, lastOpenDay: today);
  }
}

/// Settings are loaded before `runApp` so the first frame knows where to route.
late AppSettings initialSettings;

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => initialSettings;

  Future<void> change(AppSettings Function(AppSettings s) edit) async {
    state = edit(state);
    await state.save();
  }
}
