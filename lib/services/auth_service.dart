import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// What the system unlock is called on this phone.
enum Biometric {
  faceId('Face ID'),
  touchId('Touch ID'),
  passcode('passcode');

  const Biometric(this.label);

  /// How iOS names it in sentences ("Unlock with Face ID").
  final String label;
}

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

  /// Face ID, Touch ID, or just the passcode when neither is set up. iOS
  /// reports exactly one kind; Android copy stays generic.
  static Future<Biometric> biometric() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return Biometric.faceId;
      if (types.contains(BiometricType.fingerprint)) return Biometric.touchId;
    } catch (_) {}
    return Biometric.passcode;
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
