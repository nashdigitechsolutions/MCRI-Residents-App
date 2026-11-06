/// A fault report on a catalogue item, handled by maintenance.
///
/// open → in_progress → resolved
class EquipmentReport {
  final int eqReportsId;
  final int equipmentId;
  final String issueDescription;
  final String status;
  final DateTime createdAt;
  final String? equipmentName;
  final String? reporterName;
  final String? resolutionNote;

  EquipmentReport({
    required this.eqReportsId,
    required this.equipmentId,
    required this.issueDescription,
    required this.status,
    required this.createdAt,
    this.equipmentName,
    this.reporterName,
    this.resolutionNote,
  });

  static int? _int(dynamic v) =>
      v is int ? v : (v is String ? int.tryParse(v) : null);

  factory EquipmentReport.fromJson(Map<String, dynamic> json) {
    return EquipmentReport(
      eqReportsId: _int(json['eq_reports_id'])!,
      equipmentId: _int(json['equipment_id']) ?? 0,
      issueDescription: json['issue_description'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      equipmentName: json['equipment_name'] as String?,
      reporterName: json['reporter_name'] as String?,
      resolutionNote: json['resolution_note'] as String?,
    );
  }
}
