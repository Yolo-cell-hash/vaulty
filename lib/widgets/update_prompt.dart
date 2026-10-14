import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import 'adaptive.dart';
import 'common.dart';
import 'glyphs.dart';
import 'mascot.dart';

/// Looks for a newer version and offers it.
///
/// Android goes through Google Play's in-app updates, which the Play Store
/// runs, so the app itself still never touches the network. iOS asks the App
/// Store's lookup and sends people to the listing.
///
/// On launch this runs about once a day and respects "Later". From the You
/// tab ([manual]) it always runs and says when there's nothing new.
Future<void> checkForUpdate(BuildContext context, WidgetRef ref, {bool manual = false}) async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  final settings = ref.read(settingsProvider);
  final notifier = ref.read(settingsProvider.notifier);
  final now = DateTime.now();
  if (!manual && !UpdateService.checkDue(settings.updateCheckedAt, now)) return;
  final toast = toaster(context);
  await notifier.change((s) => s.copyWith(updateCheckedAt: now));
  if (Platform.isAndroid) return _viaPlay(toast, notifier, settings, manual: manual);
  if (context.mounted) return _viaAppStore(context, toast, notifier, settings, manual: manual);
}

Future<void> _viaPlay(Toast toast, SettingsNotifier notifier, AppSettings settings, {required bool manual}) async {
  void openPlay() => InAppReview.instance.openStoreListing();
  final AppUpdateInfo info;
  try {
    info = await InAppUpdate.checkForUpdate();
  } catch (e) {
    // Builds that didn't come from Google Play can't use Play's updater.
    debugPrint('update check failed: $e');
    if (manual) toast('Updates come through Google Play', icon: G.download, action: ToastAction('Open', openPlay));
    return;
  }
  if (info.installStatus == InstallStatus.downloaded) return _offerRestart(toast);
  if (info.updateAvailability != UpdateAvailability.updateAvailable) {
    if (manual) toast('You’re on the latest version', icon: G.check);
    return;
  }
  try {
    // Priority 4 or 5, set when releasing through the Play Developer API,
    // means the update can't wait: Play shows it full screen.
    if (info.updatePriority >= 4 && info.immediateUpdateAllowed) {
      await InAppUpdate.performImmediateUpdate();
      return;
    }
    final version = '${info.availableVersionCode ?? ''}';
    if (!manual &&
        !UpdateService.shouldOffer(
          version,
          skippedVersion: settings.updateSkippedVersion,
          skippedAt: settings.updateSkippedAt,
          now: DateTime.now(),
        )) {
      return;
    }
    if (!info.flexibleUpdateAllowed) {
      if (manual) toast('A new version is on Google Play', icon: G.download, action: ToastAction('Open', openPlay));
      return;
    }
    // Play asks, then downloads in the background; this returns once it's down.
    switch (await InAppUpdate.startFlexibleUpdate()) {
      case AppUpdateResult.success:
        _offerRestart(toast);
      case AppUpdateResult.userDeniedUpdate:
        await notifier.change((s) => s.copyWith(updateSkippedVersion: version, updateSkippedAt: DateTime.now()));
      case AppUpdateResult.inAppUpdateFailed:
        if (manual) toast('The update didn’t download. Try again later.', icon: G.warning);
    }
  } catch (e) {
    debugPrint('update failed: $e');
  }
}

void _offerRestart(Toast toast) => toast(
  'The new version is ready',
  icon: G.download,
  action: ToastAction('Restart', () => InAppUpdate.completeFlexibleUpdate().catchError((Object _) {})),
);

Future<void> _viaAppStore(
  BuildContext context,
  Toast toast,
  SettingsNotifier notifier,
  AppSettings settings, {
  required bool manual,
}) async {
  StoreRelease? release;
  PackageInfo? info;
  try {
    info = await PackageInfo.fromPlatform();
    release = await UpdateService.appStoreRelease(info.packageName);
  } catch (e) {
    debugPrint('update check failed: $e');
    if (manual) toast('Couldn’t reach the App Store', icon: G.warning);
    return;
  }
  if (release != null && release.storeId.isNotEmpty && release.storeId != settings.appStoreId) {
    await notifier.change((s) => s.copyWith(appStoreId: release!.storeId));
  }
  if (release == null ||
      !isNewerVersion(release.version, info.version) ||
      !UpdateService.osSupports(release.minimumOs)) {
    if (manual) toast('You’re on the latest version', icon: G.check);
    return;
  }
  if (!manual &&
      !UpdateService.shouldOffer(
        release.version,
        skippedVersion: settings.updateSkippedVersion,
        skippedAt: settings.updateSkippedAt,
        now: DateTime.now(),
      )) {
    return;
  }
  if (!context.mounted) return;
  final update = await showVSheet<bool>(context, (_) => _UpdateSheet(release: release!), isScrollControlled: true);
  if (update == true) {
    await launchUrl(release.url, mode: LaunchMode.externalApplication);
  } else {
    await notifier.change((s) => s.copyWith(updateSkippedVersion: release!.version, updateSkippedAt: DateTime.now()));
  }
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.release});

  final StoreRelease release;

  @override
  Widget build(BuildContext context) {
    final notes = release.notes.isEmpty ? 'Fixes and improvements.' : release.notes;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Mascot(size: 64, prop: MascotProp.sparkles, animate: false),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Something '),
                  TextSpan(text: 'new.', style: context.type.accent),
                ],
              ),
              style: context.type.headline,
            ),
            const SizedBox(height: 6),
            Text('Version ${release.version} is in the App Store.', style: context.type.bodySoft),
            const SizedBox(height: 16),
            Text(notes, style: context.type.body, maxLines: 8, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 24),
            VButton(label: 'Update', icon: G.download, onPressed: () => Navigator.pop(context, true)),
            const SizedBox(height: 8),
            VButton(
              label: 'Later',
              kind: ButtonStyleKind.ghost,
              height: 44,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
  }
}
