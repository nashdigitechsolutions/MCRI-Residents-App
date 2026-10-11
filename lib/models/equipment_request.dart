class EquipmentRequest {
  final int equipRequestId;
  final int equipmentId;
  final String status;
  final DateTime requestDate;
  final String? equipmentName;
  final String? username;

  EquipmentRequest({
    required this.equipRequestId,
    required this.equipmentId,
    required this.status,
    required this.requestDate,
    this.equipmentName,
    this.username,
  });

  factory EquipmentRequest.fromJson(Map<String, dynamic> json) {
    return EquipmentRequest(
      equipRequestId: json['equip_request_id'] is String
          ? int.parse(json['equip_request_id'])
          : json['equip_request_id'] as int,
      equipmentId: json['equipment_id'] is String
          ? int.parse(json['equipment_id'])
          : json['equipment_id'] as int,
      status: json['status'] as String? ?? 'pending',
      requestDate:
          DateTime.tryParse(json['request_date'] as String? ?? '') ??
          DateTime.now(),
      equipmentName: json['equipment_name'] as String?,
      username: json['username'] as String?,
    );
  }
}
