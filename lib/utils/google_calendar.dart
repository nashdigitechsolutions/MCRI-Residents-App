import 'package:url_launcher/url_launcher.dart';

/// Builds a Google Calendar "quick add" link and opens it in the browser.
/// Google's template action needs UTC timestamps in the compact
/// yyyyMMddTHHmmssZ format — no separators, no library needed to build it.
String _googleDate(DateTime dt) {
  final utc = dt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

Future<void> addToGoogleCalendar({
  required String title,
  required DateTime start,
  required DateTime end,
  String? location,
  String? description,
}) async {
  final params = {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${_googleDate(start)}/${_googleDate(end)}',
    if (location != null && location.isNotEmpty) 'location': location,
    if (description != null && description.isNotEmpty) 'details': description,
  };

  final uri = Uri.https('www.google.com', '/calendar/render', params);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
