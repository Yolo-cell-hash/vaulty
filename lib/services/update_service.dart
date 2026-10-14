import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// This build's version and bundle id (null where the platform can't say,
/// as in tests).
final packageInfoProvider = FutureProvider<PackageInfo?>((ref) async {
  try {
    return await PackageInfo.fromPlatform();
  } catch (_) {
    return null;
  }
});

/// Vaulty's listing in the App Store, from Apple's public lookup.
class StoreRelease {
  const StoreRelease({
    required this.version,
    required this.url,
    this.storeId = '',
    this.notes = '',
    this.minimumOs = '',
  });

  factory StoreRelease.fromLookup(Map<String, Object?> r) => StoreRelease(
    version: '${r['version'] ?? ''}',
    url: Uri.parse('${r['trackViewUrl'] ?? ''}'),
    storeId: '${r['trackId'] ?? ''}',
    notes: '${r['releaseNotes'] ?? ''}'.trim(),
    minimumOs: '${r['minimumOsVersion'] ?? ''}',
  );

  final String version;
  final Uri url;

  /// The numeric App Store id, which the rating link needs.
  final String storeId;
  final String notes;
  final String minimumOs;
}

/// Whether [candidate] is a later version than [current]. "1.10.0" beats
/// "1.9.2", "1.2" equals "1.2.0", and build numbers ("+7") are ignored.
bool isNewerVersion(String candidate, String current) {
  List<int> parts(String v) => [
    for (final p in v.split('+').first.trim().split('.')) int.tryParse(RegExp(r'^\d+').stringMatch(p) ?? '') ?? 0,
  ];
  final a = parts(candidate), b = parts(current);
  for (var i = 0; i < max(a.length, b.length); i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

abstract final class UpdateService {
  /// Launch checks run about once a day. A little under 24 hours, so opening
  /// the app at roughly the same time each day still checks daily.
  static const checkEvery = Duration(hours: 20);

  /// "Later" holds a version back this long before it's offered again.
  static const snooze = Duration(days: 7);

  static bool checkDue(DateTime? lastCheck, DateTime now) =>
      lastCheck == null || !now.isBefore(lastCheck.add(checkEvery));

  /// Whether to offer [version] now, given the user may have said "Later".
  static bool shouldOffer(
    String version, {
    required String skippedVersion,
    DateTime? skippedAt,
    required DateTime now,
  }) => version != skippedVersion || skippedAt == null || !now.isBefore(skippedAt.add(snooze));

  /// iOS has no in-app update API, so this asks the App Store's public lookup
  /// for the listing. The request names only the app and the store country;
  /// nothing from the vault, and no identifier for the person.
  static Future<StoreRelease?> appStoreRelease(String bundleId) async {
    final country = PlatformDispatcher.instance.locale.countryCode;
    final uri = Uri.https('itunes.apple.com', '/lookup', {
      'bundleId': bundleId,
      if (country != null && country.isNotEmpty) 'country': country.toLowerCase(),
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final response = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      final results = (jsonDecode(body) as Map<String, Object?>)['results'];
      if (results is! List || results.isEmpty) return null;
      final release = StoreRelease.fromLookup(results.first as Map<String, Object?>);
      return release.version.isEmpty ? null : release;
    } finally {
      client.close(force: true);
    }
  }

  /// Whether this iPhone's iOS can run a release needing [minimum] ("16.0").
  static bool osSupports(String minimum) {
    if (minimum.isEmpty) return true;
    final running = RegExp(r'\d+(?:\.\d+)*').stringMatch(Platform.operatingSystemVersion);
    return running == null || !isNewerVersion(minimum, running);
  }
}
