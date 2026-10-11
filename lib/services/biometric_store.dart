import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Biometric sign-in credentials, kept in their own secure store.
///
/// IMPORTANT: the storage options and key names below are identical to the
/// ones in login_screen.dart, so both read and write the same data. If you
/// change one, change the other.
class BiometricStore {
  BiometricStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      sharedPreferencesName: 'mcri_biometric_store',
      preferencesKeyPrefix: 'mcri_bio_',
    ),
    iOptions: IOSOptions(accountName: 'mcri_biometric_store'),
  );
  static final _auth = LocalAuthentication();

  static const _kEnabled = 'bio_enabled';
  static const _kDeclined = 'bio_declined';
  static const _kEmail = 'bio_email';
  static const _kPassword = 'bio_password';

  /// The device supports biometrics and has some enrolled.
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (e) {
      debugPrint('[bio] isAvailable failed: $e');
      return false;
    }
  }

  static Future<bool> isEnabled() async =>
      (await _storage.read(key: _kEnabled)) == 'true';

  static Future<String?> savedEmail() => _storage.read(key: _kEmail);

  static Future<bool> isDeclined() async =>
      (await _storage.read(key: _kDeclined)) == 'true';

  static Future<void> setDeclined() =>
      _storage.write(key: _kDeclined, value: 'true');

  /// Asks the user for a fingerprint / face scan.
  static Future<bool> confirm(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
      debugPrint('[bio] confirm result=$ok');
      return ok;
    } catch (e) {
      debugPrint('[bio] confirm failed: $e');
      return false;
    }
  }

  /// Stores (or replaces) the credentials and turns biometric sign-in on.
  static Future<void> save(String email, String password) async {
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kPassword, value: password);
    await _storage.write(key: _kEnabled, value: 'true');
    debugPrint('[bio] credentials saved (store)');
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kEmail);
    await _storage.delete(key: _kPassword);
    await _storage.write(key: _kEnabled, value: 'false');
  }
}
