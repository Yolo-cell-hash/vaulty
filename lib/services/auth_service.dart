import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Face ID / Touch ID / fingerprint with device PIN fallback.
class AuthService {
  AuthService._();

  static final _auth = LocalAuthentication();

  /// True while a system sheet (biometric prompt, camera, photo picker) is up.
  /// The app-lock observer ignores the pause/resume those sheets cause.
  static bool externalFlowActive = false;

  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasBiometrics() async {
    try {
      final list = await _auth.getAvailableBiometrics();
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    if (!await isAvailable()) return true; // No secure lock screen to defer to.
    externalFlowActive = true;
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: false, persistAcrossBackgrounding: true);
    } catch (e) {
      debugPrint('auth failed: $e');
      return false;
    } finally {
      externalFlowActive = false;
    }
  }

  /// Runs [action] (camera, picker…) without tripping the auto-lock.
  static Future<T> guardExternal<T>(Future<T> Function() action) async {
    externalFlowActive = true;
    try {
      return await action();
    } finally {
      externalFlowActive = false;
    }
  }
}
