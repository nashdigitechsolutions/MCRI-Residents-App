import '../models/poll_vote_row.dart';

enum ExportScope { all, names, lunchbox }

/// Builds a plain-text export, matching the web app's .txt branch exactly
/// (CSV/download were dropped per product decision — WhatsApp text sharing
/// only needs a readable string, not a file).
String buildPollExportText(List<PollVoteRow> rows, ExportScope scope) {
  if (scope == ExportScope.names) {
    final seen = <int, String>{};
    for (final r in rows) {
      seen.putIfAbsent(r.userId, () => r.residentName);
    }
    final names = seen.values.toList();
    return names
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');
  }

  if (scope == ExportScope.lunchbox) {
    final seen = <int, ({String name, String box})>{};
    for (final r in rows) {
      seen.putIfAbsent(
        r.userId,
        () => (name: r.residentName, box: r.lunchboxNumber ?? 'unassigned'),
      );
    }
    final entries = seen.values.toList();
    return entries
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value.name} — Box ${e.value.box}')
        .join('\n');
  }

  // scope == all — grouped by option, each with a numbered voter list.
  final byOption = <String, List<PollVoteRow>>{};
  for (final r in rows) {
    byOption.putIfAbsent(r.optionName, () => []).add(r);
  }
  final optionNames = byOption.keys.toList()..sort();

  final buffer = StringBuffer();
  for (var i = 0; i < optionNames.length; i++) {
    final opt = optionNames[i];
    final voters = byOption[opt]!;
    if (i > 0) buffer.writeln();
    buffer.writeln('$opt  (${voters.length})');
    for (var j = 0; j < voters.length; j++) {
      final v = voters[j];
      final parts = [
        if (v.roomNumber != null) 'Room ${v.roomNumber}',
        if (v.lunchboxNumber != null) 'Box ${v.lunchboxNumber}',
      ];
      final details = parts.isEmpty ? '' : ' — ${parts.join(', ')}';
      buffer.writeln('  ${j + 1}. ${v.residentName}$details');
    }
  }
  return buffer.toString().trimRight();
}
