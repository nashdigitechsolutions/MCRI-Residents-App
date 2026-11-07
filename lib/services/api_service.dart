import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  /// 0 = never reached the server (offline, DNS, timeout).
  bool get isNetwork => statusCode == 0;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Thin JSON client for the MCRI API.
///
/// - One persistent [http.Client] → connections are kept alive and reused
///   (TLS handshake once instead of per request — the biggest speed win).
/// - Every request has a timeout, so a dead network never hangs a spinner.
/// - Idempotent GETs retry once on transient network failure.
/// - A 401 on an authenticated request fires [onUnauthorized] so the app can
///   sign the user out instead of showing a broken, half-logged-in state.
/// - Non-JSON error bodies (e.g. a Cloudflare 502 page) no longer crash.
class ApiService {
  ApiService._();

  static http.Client _client = http.Client();

  /// Set by AuthProvider: called when the server rejects our token.
  static VoidCallback? onUnauthorized;

  /// Test hook.
  @visibleForTesting
  static set client(http.Client c) => _client = c;

  /// Endpoints where a 401 means "wrong credentials", not "session expired".
  static const _publicPaths = {
    '/login',
    '/signup',
    '/forgot-password',
    '/reset-password',
    '/verify-email',
    '/resend-verification',
    '/change-password',
  };

  static Uri _uri(String path) {
    assert(path.startsWith('/'), 'API paths must start with "/"');
    return Uri.parse('${AppConfig.apiBaseUrl}$path');
  }

  static Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await StorageService.getToken();
    return {
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Client': 'mcri-app',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    bool retry = false,
  }) async {
    final hadToken = StorageService.cachedToken != null;
    http.Response response;
    try {
      response = await _attempt(method, path, body);
    } on ApiException catch (e) {
      if (!retry || !e.isNetwork) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      response = await _attempt(method, path, body);
    }

    if (response.statusCode == 401 &&
        hadToken &&
        !_publicPaths.contains(path.split('?').first)) {
      onUnauthorized?.call();
    }
    return _handleResponse(response);
  }

  static Future<http.Response> _attempt(
    String method,
    String path,
    Object? body,
  ) async {
    final request = http.Request(method, _uri(path))
      ..headers.addAll(await _headers(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    try {
      final streamed = await _client
          .send(request)
          .timeout(AppConfig.requestTimeout);
      return await http.Response.fromStream(streamed)
          .timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw ApiException(
        0,
        'The server took too long to respond. Please try again.',
      );
    } on SocketException {
      throw ApiException(
        0,
        'No internet connection. Check your network and try again.',
      );
    } on http.ClientException {
      throw ApiException(0, 'Could not reach the server. Please try again.');
    } on HandshakeException {
      throw ApiException(0, 'Secure connection failed.');
    }
  }

  static dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static dynamic _handleResponse(http.Response response) {
    final decoded = _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    throw ApiException(
      response.statusCode,
      _extractMessage(decoded, response.statusCode),
    );
  }

  /// Pulls a human message out of the many error shapes the API returns
  /// (plain {message}, {error: "..."} , Zod issue arrays, Zod JSON-in-a-string).
  static String _extractMessage(dynamic decoded, int statusCode) {
    String? firstMessage(dynamic v) {
      if (v is List &&
          v.isNotEmpty &&
          v.first is Map &&
          v.first['message'] is String) {
        return v.first['message'] as String;
      }
      if (v is Map) {
        if (v['message'] is String) return v['message'] as String;
        final issues = firstMessage(v['issues']);
        if (issues != null) return issues;
      }
      return null;
    }

    final direct = firstMessage(decoded);
    if (direct != null) return direct;

    if (decoded is Map) {
      final error = decoded['error'];
      if (error is String) {
        try {
          return firstMessage(jsonDecode(error)) ?? error;
        } on FormatException {
          return error;
        }
      }
      final nested = firstMessage(error);
      if (nested != null) return nested;
    }

    return switch (statusCode) {
      401 => 'Your session has expired. Please sign in again.',
      403 => "You don't have permission to do that.",
      404 => 'Not found.',
      429 => 'Too many attempts. Please wait a moment and try again.',
      >= 500 =>
        'The server is having trouble right now. Please try again shortly.',
      _ => 'Something went wrong',
    };
  }

  // ── Speed: share in-flight GETs and remember answers for a few seconds ──
  //
  // Home, the tabs and the screens you bounce between ask for the same lists
  // (/announcements, /events, /duties, /conversations …). Identical GETs in
  // flight share one request, and a just-fetched answer is reused for
  // [_cacheTtl]. Freshness is protected: every write (POST/PATCH/PUT/DELETE),
  // every live server event and every account change clears it.
  static const _cacheTtl = Duration(seconds: 8);
  static final Map<String, Future<dynamic>> _inflight = {};
  static final Map<String, ({DateTime at, dynamic data})> _cache = {};

  /// Forget everything cached (writes, live events, sign-in/out, resume).
  static void invalidateAll() {
    _cache.clear();
    _inflight.clear();
  }

  static Future<dynamic> get(String path, {bool fresh = false}) {
    final key = '${StorageService.cachedToken.hashCode}:$path';
    if (!fresh) {
      final hit = _cache[key];
      if (hit != null && DateTime.now().difference(hit.at) < _cacheTtl) {
        return Future.value(hit.data);
      }
      final pending = _inflight[key];
      if (pending != null) return pending;
    }
    final request = _send('GET', path, retry: true)
        .then((data) {
          _cache[key] = (at: DateTime.now(), data: data);
          return data;
        })
        .whenComplete(() {
          // Block body on purpose: `=> _inflight.remove(key)` would RETURN this
          // very Future, and whenComplete would then wait on itself forever.
          _inflight.remove(key);
        });
    _inflight[key] = request;
    return request;
  }

  static Future<dynamic> _write(String method, String path, [Object? body]) {
    invalidateAll();
    return _send(method, path, body: body).whenComplete(invalidateAll);
  }

  static Future<dynamic> post(String path, [dynamic body = const {}]) =>
      _write('POST', path, body);

  static Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _write('PATCH', path, body);

  static Future<dynamic> put(String path, Map<String, dynamic> body) =>
      _write('PUT', path, body);

  static Future<dynamic> delete(String path) => _write('DELETE', path);
}
