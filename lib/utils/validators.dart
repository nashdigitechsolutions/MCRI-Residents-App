import 'dart:convert';

/// Client-side validators. Each returns an error message, or null if valid.
class Validators {
  static final _emailRegex = RegExp(r'^[^\s@]+@([^\s@.,]+\.)+[^\s@.,]{2,}$');

  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// For signing in: only checks that something was typed.
  static String? requiredPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    return null;
  }

  /// For creating / resetting a password (matches the API: 8-72 chars).
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must be at least 8 characters';
    if (v.length > 72) return 'Password must be 72 characters or fewer';
    return null;
  }

  static String? confirmPassword(String? password, String? confirm) {
    if (confirm == null || confirm.isEmpty) return 'Confirm your password';
    if (password != confirm) return 'Passwords do not match';
    return null;
  }

  static String? username(String? value) {
    final v = (value ?? '').trim();
    if (v.length < 3 || v.length > 50) {
      return 'Username must be 3\u201350 characters';
    }
    return null;
  }
}

/// Turns a raw API error message into something a person can read.
///
/// APIs using zod often return the whole validation payload as the error
/// text, e.g. `[{"code":"invalid_format","path":["email"],"message":"..."}]`.
/// This digs out the first human message from that (or from similar shapes:
/// `{error: ...}`, `{errors: ...}`, `{issues: [...]}`, `{fieldErrors: {...}}`).
/// Plain text messages pass through unchanged.
String friendlyError(
  String? raw, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (raw == null || raw.trim().isEmpty) return fallback;

  var text = raw.trim();
  if (text.startsWith('Exception: ')) text = text.substring(11);

  // The JSON may follow some prefix text ("Validation failed: [...]").
  final start = text.indexOf(RegExp(r'[\[{]'));
  final candidate = start >= 0 ? text.substring(start) : text;

  final extracted = _extract(candidate);
  if (extracted == null || extracted.isEmpty) {
    // Looked like JSON but nothing readable inside: don't show raw JSON.
    return start >= 0 ? fallback : text;
  }
  return extracted;
}

String? _extract(dynamic data) {
  if (data is String) {
    final s = data.trim();
    if (s.startsWith('{') || s.startsWith('[')) {
      try {
        return _extract(jsonDecode(s));
      } catch (_) {
        return null; // malformed JSON: let the caller use its fallback
      }
    }
    return s.isEmpty ? null : s;
  }

  if (data is List) {
    for (final item in data) {
      final r = _extract(item);
      if (r != null) return r;
    }
    return null;
  }

  if (data is Map) {
    // A single zod issue object.
    final msg = data['message'];
    if (msg is String && (data.containsKey('code') || data['path'] != null)) {
      return _issueMessage(msg, data['path']);
    }

    for (final key in const [
      'issues',
      'errors',
      'error',
      'details',
      'fieldErrors',
      'formErrors',
      'message',
    ]) {
      if (data.containsKey(key)) {
        final r = _extract(data[key]);
        if (r != null) return r;
      }
    }

    // Map of field -> messages.
    for (final v in data.values) {
      final r = _extract(v);
      if (r != null) return r;
    }
  }
  return null;
}

String _issueMessage(String message, dynamic path) {
  final field = (path is List && path.isNotEmpty)
      ? path.last.toString().toLowerCase()
      : '';
  final lower = message.toLowerCase();

  if (field.contains('email')) return 'Enter a valid email address';
  if (field.contains('password') &&
      (lower.contains('character') ||
          lower.contains('too small') ||
          lower.contains('too big') ||
          lower.contains('at least') ||
          lower.contains('at most'))) {
    return 'Password must be between 8 and 72 characters';
  }
  return message;
}
