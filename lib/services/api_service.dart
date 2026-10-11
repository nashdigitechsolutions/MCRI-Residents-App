import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiService {
  static Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static dynamic _handleResponse(http.Response response) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw ApiException(
      response.statusCode,
      _extractMessage(decoded, response.statusCode),
    );
  }

  static String _extractMessage(dynamic decoded, int statusCode) {
    // Direct Zod array:
    // [
    //   {
    //     "message": "Invalid email address"
    //   }
    // ]
    if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;

      if (first is Map && first['message'] is String) {
        return first['message'] as String;
      }
    }

    if (decoded is! Map) {
      return 'Something went wrong';
    }

    // Direct message:
    // { "message": "Invalid email address" }
    if (decoded['message'] is String) {
      return decoded['message'] as String;
    }

    final error = decoded['error'];

    // error is already a message
    if (error is String) {
      // Sometimes the backend puts the Zod JSON inside the error string.
      try {
        final parsedError = jsonDecode(error);

        if (parsedError is List && parsedError.isNotEmpty) {
          final first = parsedError.first;

          if (first is Map && first['message'] is String) {
            return first['message'] as String;
          }
        }

        if (parsedError is Map) {
          if (parsedError['message'] is String) {
            return parsedError['message'] as String;
          }

          final issues = parsedError['issues'];

          if (issues is List && issues.isNotEmpty) {
            final first = issues.first;

            if (first is Map && first['message'] is String) {
              return first['message'] as String;
            }
          }
        }
      } catch (_) {
        // It wasn't JSON, so use the string directly.
      }

      return error;
    }

    // error is an object
    if (error is Map) {
      if (error['message'] is String) {
        return error['message'] as String;
      }

      final issues = error['issues'];

      if (issues is List && issues.isNotEmpty) {
        final first = issues.first;

        if (first is Map && first['message'] is String) {
          return first['message'] as String;
        }
      }
    }

    // Top-level Zod issues
    final issues = decoded['issues'];

    if (issues is List && issues.isNotEmpty) {
      final first = issues.first;

      if (first is Map && first['message'] is String) {
        return first['message'] as String;
      }
    }

    return 'Something went wrong';
  }

  static Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final response = await http.patch(
      uri,
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  static Future<dynamic> get(String path) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final response = await http.get(uri, headers: await _headers());
    return _handleResponse(response);
  }

  static Future<dynamic> delete(String path) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final response = await http.delete(uri, headers: await _headers());
    return _handleResponse(response);
  }

  static Future<dynamic> post(String path, dynamic body) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final response = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }
}
