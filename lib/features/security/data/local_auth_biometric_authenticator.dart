import 'package:bkdash_sanitary_ware/features/security/data/biometric_authenticator.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// [BiometricAuthenticator] backed by the `local_auth` plugin.
final class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false; // cancelled, timed out, no biometrics, ...
    } on PlatformException {
      return false;
    }
  }
}
