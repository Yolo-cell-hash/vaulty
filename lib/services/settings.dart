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
    this.backupEveryDays = 30,
    this.backupSnoozedUntil,
    this.calendarSync = false,
    this.calendarId = '',
    this.firstOpened,
    this.reviewAskedAt,
    this.updateCheckedAt,
    this.updateSkippedVersion = '',
    this.updateSkippedAt,
    this.appStoreId = '',
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

  /// How often to nudge about a backup while there are unsaved changes, in
  /// days. 0 turns the nudges off.
  final int backupEveryDays;

  /// "Later" on the home screen's backup card hides it until then.
  final DateTime? backupSnoozedUntil;

  /// Whether dated items are mirrored into Vaulty's own calendar.
  final bool calendarSync;

  /// That calendar's id on this phone (empty until it's been made).
  final String calendarId;

  /// The first day the vault was opened, for the review prompt's timing.
  final DateTime? firstOpened;

  /// The last time Vaulty asked the system to show a rating prompt.
  final DateTime? reviewAskedAt;

  /// The last automatic store check for a newer version.
  final DateTime? updateCheckedAt;

  /// A version the user said "Later" to, and when, so it isn't offered daily.
  final String updateSkippedVersion;
  final DateTime? updateSkippedAt;

  /// The App Store's id for Vaulty, learned from the iOS update check.
  final String appStoreId;

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
    int? backupEveryDays,
    DateTime? backupSnoozedUntil,
    bool? calendarSync,
    String? calendarId,
    DateTime? firstOpened,
    DateTime? reviewAskedAt,
    DateTime? updateCheckedAt,
    String? updateSkippedVersion,
    DateTime? updateSkippedAt,
    String? appStoreId,
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
    backupEveryDays: backupEveryDays ?? this.backupEveryDays,
    backupSnoozedUntil: backupSnoozedUntil ?? this.backupSnoozedUntil,
    calendarSync: calendarSync ?? this.calendarSync,
    calendarId: calendarId ?? this.calendarId,
    firstOpened: firstOpened ?? this.firstOpened,
    reviewAskedAt: reviewAskedAt ?? this.reviewAskedAt,
    updateCheckedAt: updateCheckedAt ?? this.updateCheckedAt,
    updateSkippedVersion: updateSkippedVersion ?? this.updateSkippedVersion,
    updateSkippedAt: updateSkippedAt ?? this.updateSkippedAt,
    appStoreId: appStoreId ?? this.appStoreId,
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
      backupEveryDays: int.tryParse(all['pref_backup_every'] ?? '') ?? 30,
      backupSnoozedUntil: DateTime.tryParse(all['pref_backup_snooze'] ?? ''),
      calendarSync: all['pref_calendar_sync'] == '1',
      calendarId: all['pref_calendar_id'] ?? '',
      firstOpened: DateTime.tryParse(all['pref_first_opened'] ?? ''),
      reviewAskedAt: DateTime.tryParse(all['pref_review_asked'] ?? ''),
      updateCheckedAt: DateTime.tryParse(all['pref_update_checked'] ?? ''),
      updateSkippedVersion: all['pref_update_skipped'] ?? '',
      updateSkippedAt: DateTime.tryParse(all['pref_update_skipped_at'] ?? ''),
      appStoreId: all['pref_app_store_id'] ?? '',
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
    await SecureKeys.write('pref_backup_every', '$backupEveryDays');
    await SecureKeys.write('pref_backup_snooze', backupSnoozedUntil?.toIso8601String() ?? '');
    await SecureKeys.write('pref_calendar_sync', calendarSync ? '1' : '0');
    await SecureKeys.write('pref_calendar_id', calendarId);
    await SecureKeys.write('pref_first_opened', firstOpened?.toIso8601String() ?? '');
    await SecureKeys.write('pref_review_asked', reviewAskedAt?.toIso8601String() ?? '');
    await SecureKeys.write('pref_update_checked', updateCheckedAt?.toIso8601String() ?? '');
    await SecureKeys.write('pref_update_skipped', updateSkippedVersion);
    await SecureKeys.write('pref_update_skipped_at', updateSkippedAt?.toIso8601String() ?? '');
    await SecureKeys.write('pref_app_store_id', appStoreId);
  }

  static List<int>? _offsets(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final list = raw.split(',').map(int.tryParse).whereType<int>().toList();
    return list.isEmpty ? null : list;
  }

  /// Bumps the daily-open streak shown in the header, and remembers the
  /// first day the vault was opened.
  AppSettings withStreakTick(DateTime now) {
    String key(DateTime d) => '${d.year}-${d.month}-${d.day}';
    final today = key(now);
    if (lastOpenDay == today) return this;
    final yesterday = key(now.subtract(const Duration(days: 1)));
    return copyWith(
      streak: lastOpenDay == yesterday ? streak + 1 : 1,
      lastOpenDay: today,
      firstOpened: firstOpened ?? now,
    );
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
