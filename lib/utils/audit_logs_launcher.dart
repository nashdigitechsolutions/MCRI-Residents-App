import 'package:url_launcher/url_launcher.dart';

/// Hands off to the live website, already logged in, using the same
/// token -> /auth/callback mechanism Google OAuth uses to bridge sessions.
/// See README note: the website's AuthCallback needs a small addition to
/// honor `?redirect=` and land directly on /admin/audit-logs instead of '/'
/// — until then this logs the admin in and drops them one tap away.
Future<void> openAuditLogsInBrowser(String token) async {
  final uri = Uri.https('mcriresidents.online', '/auth/callback', {
    'token': token,
    'redirect': '/admin/audit-logs',
  });
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
