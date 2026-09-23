import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../data/memory_repository.dart';
import '../models/memory.dart';

/// One reminder the OS should fire.
class PlannedReminder {
  const PlannedReminder(this.memory, this.occurrence, this.offsetDays, this.at);

  final Memory memory;

  /// The due date this reminder is about.
  final DateTime occurrence;
  final int offsetDays;

  /// Local wall-clock time to fire.
  final DateTime at;
}

/// Works out every reminder to schedule, soonest first. Pure, so it's tested
/// without a device. Repeating dates get their next two occurrences so a year
/// without opening the app still produces a birthday nudge.
List<PlannedReminder> planReminders(List<Memory> memories, ReminderDefaults defaults, DateTime now, {int limit = 60}) {
  final planned = <PlannedReminder>[];
  for (final m in memories) {
    if (!m.hasExpiry || m.isArchived) continue;
    final offsets = m.effectiveOffsets(defaults);
    if (offsets.isEmpty) continue;
    final minutes = m.effectiveMinutes(defaults);
    for (final occurrence in m.upcomingDates(m.isRecurring ? 2 : 1)) {
      for (final days in offsets) {
        final at = DateTime(occurrence.year, occurrence.month, occurrence.day - days, minutes ~/ 60, minutes % 60);
        if (at.isAfter(now)) planned.add(PlannedReminder(m, occurrence, days, at));
      }
    }
  }
  planned.sort((a, b) => a.at.compareTo(b.at));
  return planned.take(limit).toList();
}

/// Schedules reminders with the OS alarm/notification queue only.
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Memory ids from notifications the user tapped while the app was running.
  static final _taps = StreamController<String>.broadcast();
  static Stream<String> get taps => _taps.stream;

  /// The memory id whose notification launched the app, consumed once.
  static String? _launchPayload;
  static String? takeLaunchPayload() {
    final p = _launchPayload;
    _launchPayload = null;
    return p;
  }

  /// iOS keeps at most 64 pending local notifications per app.
  static const _maxPending = 60;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'expiry_radar',
      'Expiry radar',
      channelDescription: 'Heads-ups before your stuff expires',
      importance: Importance.high,
      priority: Priority.high,
      // White Vo silhouette; full-colour launcher icons render as a blank
      // square in the Android status bar.
      icon: 'ic_stat_vaulty',
      color: Color(0xFF7B5CFA),
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('timezone lookup failed, using UTC: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_vaulty'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) _taps.add(id);
      },
    );
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final id = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) && id != null && id.isNotEmpty) _launchPayload = id;
    } catch (e) {
      debugPrint('launch details unavailable: $e');
    }
    _ready = true;
  }

  static Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  /// Rebuilds the whole OS reminder queue from the vault: the soonest
  /// reminders win so iOS's 64-pending limit never drops an urgent one.
  static Future<void> rescheduleAll(List<Memory> memories, MemoryRepository repo, ReminderDefaults defaults) async {
    await init();
    final planned = planReminders(memories, defaults, DateTime.now(), limit: _maxPending);
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('cancelAll failed: $e');
    }
    final rnd = Random();
    final rows = <Reminder>[];
    for (final p in planned) {
      final (m, occurrence, days) = (p.memory, p.occurrence, p.offsetDays);
      final at = tz.TZDateTime.from(p.at, tz.local);
      final id = rnd.nextInt(1 << 30);
      final (title, body) = _copy(m, occurrence, days);
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: at,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: m.id,
        );
        rows.add(
          Reminder(id: const Uuid().v4(), memoryId: m.id, notificationId: '$id', scheduledFor: at, offsetDays: days),
        );
      } catch (e) {
        debugPrint('schedule failed for ${m.id}: $e');
      }
    }
    await repo.replaceAllReminders(rows);
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  static (String, String) _copy(Memory m, DateTime occurrence, int days) {
    final t = m.title;
    String inDays(String verb) => switch (days) {
      0 => '$verb today',
      1 => '$verb tomorrow',
      7 => '$verb in 1 week',
      _ => '$verb in $days days',
    };

    if (m.isOccasion) {
      final start = m.expiryDate!;
      final years = occurrence.year - start.year;
      final milestone = years > 0 && years < 130 ? ' ($years!)' : '';
      return switch (days) {
        0 => ('$t is today', 'Go celebrate$milestone.'),
        1 => ('$t is tomorrow', 'Gift sorted? Card written? You\'ve got this.'),
        7 => ('$t is in a week', 'Perfect time to plan something.'),
        _ => ('$t is in $days days', 'Early birds get the best gifts.'),
      };
    }
    if (m.isRecurring) {
      return (
        inDays('$t renews'),
        days == 0
            ? 'Renewing today. Still worth it? You\'re in control.'
            : 'Still using it? Now\'s the time to keep or cancel, zero regrets.',
      );
    }
    return switch (days) {
      0 => ('$t expires today', 'Last call. Sort it out today and future-you can relax.'),
      1 => ('$t expires tomorrow', 'A small nudge: tomorrow is the day.'),
      7 => ('$t expires in a week', 'One week to go. Future-you says thanks.'),
      30 => ('$t expires in 30 days', 'Plenty of time, zero late fees. Details are in your vault.'),
      _ => ('$t expires in $days days', 'Plenty of time, zero late fees. Details are in your vault.'),
    };
  }
}
