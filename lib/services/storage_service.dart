import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted on-device storage (Android Keystore / iOS Keychain).
///
/// The auth token is mirrored in memory so the API layer doesn't hit the
/// platform channel on every single request (that read costs several ms on
/// Android and was happening for every call).
class StorageService {
  StorageService._();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      // Never sync the session to iCloud or restore it onto another device.
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String tokenKey = 'mcri_token';

  static String? _tokenCache;
  static bool _tokenLoaded = false;

  static Future<String?> getToken() async {
    if (_tokenLoaded) return _tokenCache;
    _tokenCache = await _storage.read(key: tokenKey);
    _tokenLoaded = true;
    return _tokenCache;
  }

  /// Synchronous access for hot paths once the token has been loaded.
  static String? get cachedToken => _tokenCache;

  static Future<void> setToken(String token) async {
    _tokenCache = token;
    _tokenLoaded = true;
    await _storage.write(key: tokenKey, value: token);
  }

  static Future<void> deleteToken() async {
    _tokenCache = null;
    _tokenLoaded = true;
    await _storage.delete(key: tokenKey);
  }

  /// Wipes everything in the main store (the biometric store is separate).
  static Future<void> clearAll() async {
    _tokenCache = null;
    _tokenLoaded = true;
    await _storage.deleteAll();
  }

  static Future<void> setItem(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<String?> getItem(String key) => _storage.read(key: key);

  static Future<void> removeItem(String key) => _storage.delete(key: key);
}
