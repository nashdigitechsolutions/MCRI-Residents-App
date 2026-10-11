import 'package:url_launcher/url_launcher.dart';

/// Tries the WhatsApp app deep link first (opens the app directly, message
/// pre-filled); falls back to the universal wa.me web link if the app isn't
/// installed or the deep link can't be launched.
Future<bool> shareToWhatsApp(String text) async {
  final encoded = Uri.encodeComponent(text);

  final appUri = Uri.parse('whatsapp://send?text=$encoded');
  if (await canLaunchUrl(appUri)) {
    return launchUrl(appUri);
  }

  final webUri = Uri.parse('https://wa.me/?text=$encoded');
  return launchUrl(webUri, mode: LaunchMode.externalApplication);
}
