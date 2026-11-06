import 'config/env.dart';

/// Kept for backwards compatibility — prefer [AppConfig] directly.
class ApiConstants {
  static const String baseUrl = AppConfig.apiBaseUrl;
  static const String wsUrl = AppConfig.wsUrl;
}
