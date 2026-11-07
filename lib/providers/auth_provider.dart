import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/device_registration_service.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    ApiService.onUnauthorized = _onServerRejectedToken;
  }

  /// Where the admin's own session waits while "Logged in as…" someone.
  static const _adminTokenKey = 'mcri_admin_token';

  User? _user;
  String? _token;
  Map<String, dynamic>? _claims;
  bool _loading = true;
  bool _sessionExpired = false;
  Timer? _expiryTimer;

  User? get user => _user;
  String? get token => _token;
  bool get loading => _loading;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.roleId == 1;

  /// True while an admin is using "Log in as…".
  bool get isImpersonating => _claims?['impersonated_by'] != null;
  String get impersonatorName =>
      _claims?['impersonator_name'] as String? ?? 'Admin';
  DateTime? get impersonationEndsAt =>
      _claims == null ? null : _expiry(_claims!);

  /// True right after an automatic sign-out, so the login screen can explain
  /// why. Cleared by [consumeSessionExpired].
  bool get sessionExpired => _sessionExpired;
  bool consumeSessionExpired() {
    final v = _sessionExpired;
    _sessionExpired = false;
    return v;
  }

  Future<void> checkAuthStatus() async {
    final storedToken = await StorageService.getToken();
    final payload = storedToken == null ? null : _decodeJwtPayload(storedToken);

    if (storedToken == null || payload == null || _isExpired(payload)) {
      // An expired "Log in as…" session falls back to the admin's own one.
      if (payload?['impersonated_by'] != null && await endImpersonation()) {
        _loading = false;
        notifyListeners();
        return;
      }
      if (storedToken != null) await StorageService.deleteToken();
      _loading = false;
      notifyListeners();
      return;
    }

    _setSession(storedToken, payload);
    _loading = false;
    notifyListeners();
    // App restarted mid-impersonation and that token has since expired:
    // the expiry timer above fires immediately and returns to the admin.
  }

  Future<void> login(String email, String password) async {
    final data = await ApiService.post('/login', {
      'email': email,
      'password': password,
    });

    final newToken = data is Map ? data['token'] : null;
    if (newToken is! String) {
      throw ApiException(500, 'Received an invalid response from the server');
    }
    final payload = _decodeJwtPayload(newToken);
    if (payload == null || _isExpired(payload)) {
      throw ApiException(500, 'Received an invalid token from the server');
    }

    await StorageService.setToken(newToken);
    _setSession(newToken, payload, fallbackEmail: email);
    notifyListeners();
  }

  /// Called from a mcriresidents://auth-callback deep link. Any app on the
  /// device can fire that link, so the token is only accepted after the API
  /// confirms it is genuine (GET /profile with it succeeds).
  Future<void> handleOAuthSuccess(String oauthToken) async {
    final payload = _decodeJwtPayload(oauthToken);
    if (payload == null || _isExpired(payload)) {
      throw ApiException(401, 'Sign-in link is invalid or has expired');
    }

    final previous = StorageService.cachedToken;
    await StorageService.setToken(oauthToken);
    try {
      await ApiService.get('/profile');
    } catch (_) {
      if (previous != null) {
        await StorageService.setToken(previous);
      } else {
        await StorageService.deleteToken();
      }
      rethrow;
    }

    _setSession(oauthToken, payload);
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

  /// [serverReachable] is false when the token is already known to be dead
  /// (expired / rejected), so we skip the push-unregister call.
  Future<void> logout({bool serverReachable = true}) async {
    if (isImpersonating && await endImpersonation()) return;
    _expiryTimer?.cancel();
    if (serverReachable && _token != null) {
      await DeviceRegistrationService.unregister();
    }
    await StorageService.clearAll();
    _token = null;
    _user = null;
    _claims = null;
    notifyListeners();
  }

  void _onServerRejectedToken() {
    if (!isLoggedIn) return;
    if (isImpersonating) {
      endImpersonation().then((ok) {
        if (!ok) {
          _sessionExpired = true;
          logout(serverReachable: false);
        }
      });
      return;
    }
    _sessionExpired = true;
    logout(serverReachable: false);
  }

  // ── "Log in as…" (admin impersonation) ────────────────────────────────

  /// Swap to [user]'s account using the short-lived token from
  /// POST /admin/impersonate. The admin session is parked in secure storage.
  Future<void> startImpersonation(String impersonationToken) async {
    final payload = _decodeJwtPayload(impersonationToken);
    if (payload == null ||
        payload['impersonated_by'] == null ||
        _isExpired(payload)) {
      throw ApiException(500, 'Received an invalid impersonation token');
    }
    if (isImpersonating) await endImpersonation();
    final adminToken = _token;
    if (adminToken == null) {
      throw ApiException(401, 'Sign in as an admin first');
    }
    await StorageService.setItem(_adminTokenKey, adminToken);
    await StorageService.setToken(impersonationToken);
    _setSession(impersonationToken, payload);
    notifyListeners();
  }

  /// Back to the admin's own account. Returns false if that session has
  /// also expired (the caller then signs out completely).
  Future<bool> endImpersonation() async {
    final adminToken = await StorageService.getItem(_adminTokenKey);
    await StorageService.removeItem(_adminTokenKey);
    final payload = adminToken == null ? null : _decodeJwtPayload(adminToken);
    if (adminToken == null || payload == null || _isExpired(payload)) {
      return false;
    }
    await StorageService.setToken(adminToken);
    _setSession(adminToken, payload);
    notifyListeners();
    return true;
  }

  void _setSession(
    String token,
    Map<String, dynamic> payload, {
    String? fallbackEmail,
  }) {
    _token = token;
    _claims = payload;
    _user = _userFromPayload(payload, fallbackEmail: fallbackEmail);
    _scheduleExpiry(payload);
  }

  /// Signs out automatically the moment the JWT expires.
  void _scheduleExpiry(Map<String, dynamic> payload) {
    _expiryTimer?.cancel();
    final exp = _expiry(payload);
    if (exp == null) return;
    final remaining = exp.difference(DateTime.now());
    // Timer max is ~24 days; long-lived tokens are caught by the 401 handler.
    if (remaining > const Duration(days: 20)) return;
    _expiryTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (isImpersonating) {
        _onServerRejectedToken();
        return;
      }
      _sessionExpired = true;
      logout(serverReachable: false);
    });
  }

  DateTime? _expiry(Map<String, dynamic> payload) {
    final exp = payload['exp'];
    final seconds = exp is int
        ? exp
        : (exp is String ? int.tryParse(exp) : null);
    return seconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  bool _isExpired(Map<String, dynamic> payload) {
    final exp = _expiry(payload);
    // 30s leeway for device clock skew.
    return exp != null &&
        DateTime.now().isAfter(exp.subtract(const Duration(seconds: 30)));
  }

  static int? _asInt(dynamic v) =>
      v is int ? v : (v is String ? int.tryParse(v) : null);

  User _userFromPayload(Map<String, dynamic> payload, {String? fallbackEmail}) {
    return User(
      userId: _asInt(payload['user_id']) ?? 0,
      email: payload['email'] as String? ?? fallbackEmail ?? '',
      username: payload['username'] as String? ?? '',
      roleId: _asInt(payload['role_id']),
    );
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payloadJson = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map<String, dynamic> ||
          _asInt(decoded['user_id']) == null) {
        return null;
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    if (ApiService.onUnauthorized == _onServerRejectedToken) {
      ApiService.onUnauthorized = null;
    }
    super.dispose();
  }
}
