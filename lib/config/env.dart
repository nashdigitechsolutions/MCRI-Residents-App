/// Single source of truth for every host the app talks to.
///
/// The app, website (mcriresidents.online) and API (api.mcriresidents.online)
/// must stay on the same hosts — the website's bundle uses
/// `https://api.mcriresidents.online/api`, so the app does too.
///
/// Override per build without touching code:
///   flutter build apk --dart-define=API_HOST=staging-api.mcriresidents.online
class AppConfig {
  AppConfig._();

  static const String apiHost = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'api.mcriresidents.online',
  );

  static const String webHost = String.fromEnvironment(
    'WEB_HOST',
    defaultValue: 'mcriresidents.online',
  );

  /// REST base, e.g. https://api.mcriresidents.online/api
  static const String apiBaseUrl = 'https://$apiHost/api';

  /// Realtime socket, e.g. wss://api.mcriresidents.online/api/ws
  static const String wsUrl = 'wss://$apiHost/api/ws';

  /// Google OAuth entry point (redirects back via mcriresidents://auth-callback).
  static const String googleAuthUrl = '$apiBaseUrl/auth/google';

  /// Custom URL scheme registered on Android + iOS for OAuth hand-back.
  static const String deepLinkScheme = 'mcriresidents';

  static const Duration requestTimeout = Duration(seconds: 20);
}
