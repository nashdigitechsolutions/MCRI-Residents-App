/// Finds links in chat text: web addresses, emails and phone numbers.
///
/// Returns the text as ordered segments; link segments carry the [Uri] to
/// open (https / mailto / tel). Trailing punctuation is left out of a link
/// ("see https://x.com." links only https://x.com).
class TextSegment {
  final String text;
  final Uri? uri;
  const TextSegment(this.text, [this.uri]);
  bool get isLink => uri != null;

  @override
  String toString() => isLink ? '[$text → $uri]' : text;
}

final _linkPattern = RegExp(
  r'((?:https?://|www\.)[^\s<>"]+)' // web
  r'|([A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})' // email
  r'|((?:\+\d|\b0)[\d\s-]{6,}\d\b)', // phone: starts with + or 0, 8+ digits
  caseSensitive: false,
);

const _trailingPunctuation = '.,!?;:)]}\'"';

List<TextSegment> linkify(String text) {
  final out = <TextSegment>[];
  var cursor = 0;
  for (final m in _linkPattern.allMatches(text)) {
    var raw = m.group(0)!;
    // Trim trailing punctuation that is almost never part of the link.
    while (raw.isNotEmpty &&
        _trailingPunctuation.contains(raw[raw.length - 1])) {
      // keep a closing ")" if the link itself opened one, e.g. wikipedia (x)
      if (raw.endsWith(')') && raw.contains('(')) break;
      raw = raw.substring(0, raw.length - 1);
    }
    if (raw.isEmpty) continue;

    Uri? uri;
    if (m.group(1) != null) {
      uri = Uri.tryParse(
        raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw,
      );
      if (uri == null || uri.host.isEmpty) uri = null;
    } else if (m.group(2) != null) {
      uri = Uri(scheme: 'mailto', path: raw);
    } else {
      final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
      uri = digits.replaceAll('+', '').length >= 8
          ? Uri(scheme: 'tel', path: digits)
          : null;
    }
    if (uri == null) continue;

    if (m.start > cursor) out.add(TextSegment(text.substring(cursor, m.start)));
    out.add(TextSegment(raw, uri));
    cursor = m.start + raw.length;
  }
  if (cursor < text.length) out.add(TextSegment(text.substring(cursor)));
  return out;
}
