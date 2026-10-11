import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();

  static const String tokenKey = 'mcri_token';

  static Future<String?> getToken() async {
    return _storage.read(key: tokenKey);
  }

  static Future<void> setToken(String token) async {
    await _storage.write(key: tokenKey, value: token);
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: tokenKey);
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  static Future<void> setItem(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  static Future<String?> getItem(String key) async {
    return _storage.read(key: key);
  }
}
