import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../state/vault_state.dart';
import 'auth_service.dart';
import 'settings.dart';

/// Vaulty's App Store id: App Store Connect → App Information → Apple ID.
/// Until it's filled in, iOS learns it from the update check once the app is
/// live, and the "Rate Vaulty" row waits for that.
const appStoreId = '';

/// Asking for a rating. Vaulty only ever shows the system's own prompt, and
/// never asks "Do you like it?" first: both stores forbid steering only happy
/// people to the review page.
abstract final class ReviewService {
  /// The app needs a few days and a handful of memories to earn an opinion.
  static const minAge = Duration(days: 4);
  static const minMemories = 5;

  /// Vaulty itself asks at most every four months. The OS limits it further:
  /// iOS shows the prompt at most three times a year, and Play keeps a quota.
  static const gap = Duration(days: 120);

  static bool shouldAsk({
    required DateTime? firstOpened,
    required DateTime? lastAsked,
    required int memories,
    required DateTime now,
  }) {
    if (firstOpened == null || now.isBefore(firstOpened.add(minAge))) return false;
    if (memories < minMemories) return false;
    return lastAsked == null || !now.isBefore(lastAsked.add(gap));
  }

  /// Call right after something went well: a save, a renewal, a backup.
  /// Almost always does nothing.
  static void maybeAsk(WidgetRef ref) {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final settings = ref.read(settingsProvider);
    final now = DateTime.now();
    final memories = ref.read(vaultProvider).value?.length ?? 0;
    if (!shouldAsk(
      firstOpened: settings.firstOpened,
      lastAsked: settings.reviewAskedAt,
      memories: memories,
      now: now,
    )) {
      return;
    }
    unawaited(_ask(ref.read(settingsProvider.notifier), now));
  }

  static Future<void> _ask(SettingsNotifier settings, DateTime now) async {
    try {
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      // Counted up front, so a prompt the OS decides not to show still counts.
      await settings.change((s) => s.copyWith(reviewAskedAt: now));
      // Let the sheet or toast that marked the moment settle first.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await AuthService.guardExternal(review.requestReview);
    } catch (e) {
      debugPrint('review prompt failed: $e');
    }
  }

  /// The "Rate Vaulty" row: straight to the store's review page. Returns
  /// false on iOS while the App Store id isn't known yet.
  static Future<bool> openStorePage({required String learnedAppStoreId}) async {
    final id = appStoreId.isNotEmpty ? appStoreId : learnedAppStoreId;
    if (Platform.isIOS && id.isEmpty) return false;
    try {
      await InAppReview.instance.openStoreListing(appStoreId: id.isEmpty ? null : id);
      return true;
    } catch (e) {
      debugPrint('store listing failed: $e');
      return false;
    }
  }
}
