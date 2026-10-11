class EquipmentReport {
  final int eqReportsId;
  final int equipmentId;
  final String issueDescription;
  final String status;
  final DateTime createdAt;
  final String? equipmentName;

  EquipmentReport({
    required this.eqReportsId,
    required this.equipmentId,
    required this.issueDescription,
    required this.status,
    required this.createdAt,
    this.equipmentName,
  });

  factory EquipmentReport.fromJson(Map<String, dynamic> json) {
    return EquipmentReport(
      eqReportsId: json['eq_reports_id'] is String
          ? int.parse(json['eq_reports_id'])
          : json['eq_reports_id'] as int,
      equipmentId: json['equipment_id'] is String
          ? int.parse(json['equipment_id'])
          : json['equipment_id'] as int,
      issueDescription: json['issue_description'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      equipmentName: json['equipment_name'] as String?,
    );
  }
}
