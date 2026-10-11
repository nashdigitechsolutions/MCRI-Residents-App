import 'dart:async';

import 'package:app_links/app_links.dart';

/// Wraps the app_links package so the rest of the app only has to think
/// about "a token arrived", not the mechanics of listening for URIs.
class DeepLinkService {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// Call once, near app startup. `onToken` fires any time a
  /// mcriresidents://auth-callback?token=... link is opened — whether the
  /// app was already running in the background, or this link is what
  /// launched it fresh from a cold start.
  void listen(void Function(String token) onToken) {
    _subscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri, onToken);
    });

    // Also check whether the app was launched BY a link (cold start) —
    // uriLinkStream alone only catches links that arrive while already running.
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleUri(uri, onToken);
    });
  }

  void _handleUri(Uri uri, void Function(String token) onToken) {
    if (uri.scheme == 'mcriresidents' && uri.host == 'auth-callback') {
      final token = uri.queryParameters['token'];
      if (token != null) onToken(token);
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
