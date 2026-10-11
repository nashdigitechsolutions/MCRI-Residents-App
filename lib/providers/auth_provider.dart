import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  String? _token;
  bool _loading = true;

  User? get user => _user;
  String? get token => _token;
  bool get loading => _loading;
  bool get isLoggedIn => _user != null;

  Future<void> checkAuthStatus() async {
    final storedToken = await StorageService.getToken();
    if (storedToken == null) {
      _loading = false;
      notifyListeners();
      return;
    }

    final payload = _decodeJwtPayload(storedToken);
    if (payload == null) {
      await StorageService.deleteToken();
      _loading = false;
      notifyListeners();
      return;
    }

    _token = storedToken;
    _user = _userFromPayload(payload);
    _loading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await ApiService.post('/login', {
      'email': email,
      'password': password,
    });

    final newToken = data['token'] as String;
    final payload = _decodeJwtPayload(newToken);
    if (payload == null) {
      throw Exception('Received an invalid token from the server');
    }

    await StorageService.setToken(newToken);
    _token = newToken;
    _user = _userFromPayload(payload, fallbackEmail: email);
    notifyListeners();
  }

  Future<void> handleOAuthSuccess(String oauthToken) async {
    final payload = _decodeJwtPayload(oauthToken);
    if (payload == null) {
      throw Exception('Received an invalid token during OAuth verification');
    }

    await StorageService.setToken(oauthToken);
    _token = oauthToken;
    _user = _userFromPayload(payload);
    notifyListeners();
  }

  Future<void> signup(String email, String password, String username) async {
    await ApiService.post('/signup', {
      'email': email,
      'password': password,
      'username': username,
    });
    // Signup doesn't log the user in — same as the web app.
  }

  Future<void> logout() async {
    await StorageService.deleteToken();
    _token = null;
    _user = null;
    notifyListeners();
  }

  User _userFromPayload(Map<String, dynamic> payload, {String? fallbackEmail}) {
    return User(
      userId: payload['user_id'] is String
          ? int.parse(payload['user_id'])
          : payload['user_id'] as int,
      email: payload['email'] as String? ?? fallbackEmail ?? '',
      username: payload['username'] as String? ?? '',
      roleId: payload['role_id'] == null
          ? null
          : (payload['role_id'] is String
                ? int.parse(payload['role_id'])
                : payload['role_id'] as int),
    );
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payloadJson = utf8.decode(base64Url.decode(normalized));
      return jsonDecode(payloadJson) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}
