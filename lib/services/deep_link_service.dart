import 'dart:async';

import 'package:app_links/app_links.dart';

import '../config/env.dart';

/// Wraps the app_links package so the rest of the app only has to think
/// about "a token arrived", not the mechanics of listening for URIs.
///
/// Security: only `mcriresidents://auth-callback?token=<jwt>` is accepted,
/// the token must look like a JWT, and the same link is never processed
/// twice (cold-start link + stream can both deliver it). The token is then
/// verified against the API by AuthProvider before it is trusted.
class DeepLinkService {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  final _seen = <String>{};

  static final _jwtShape = RegExp(
    r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
  );

  void listen(void Function(String token) onToken) {
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleUri(uri, onToken),
      onError: (_) {},
    );
    _appLinks
        .getInitialLink()
        .then((uri) {
          if (uri != null) _handleUri(uri, onToken);
        })
        .catchError((_) {});
  }

  void _handleUri(Uri uri, void Function(String token) onToken) {
    if (uri.scheme != AppConfig.deepLinkScheme || uri.host != 'auth-callback') {
      return;
    }
    final token = uri.queryParameters['token'];
    if (token == null || token.length > 4096 || !_jwtShape.hasMatch(token)) {
      return;
    }
    if (!_seen.add(token)) return;
    onToken(token);
  }

  void dispose() {
    _subscription?.cancel();
  }
}
