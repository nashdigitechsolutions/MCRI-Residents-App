/// A resident's request for the lodge manager to BUY an item.
///
/// pending → approved (manager will buy) → purchased (bought, collect it)
///        ↘ rejected
/// `returned` only appears on legacy borrow-style requests.
class EquipmentRequest {
  final int equipRequestId;

  /// Catalogue item this is "another one of", or null for a new item.
  final int? equipmentId;
  final String status;
  final DateTime requestDate;
  final String? equipmentName;
  final String? username;
  final String? itemName;
  final String? reason;
  final int quantity;
  final String? managerNote;

  EquipmentRequest({
    required this.equipRequestId,
    required this.equipmentId,
    required this.status,
    required this.requestDate,
    this.equipmentName,
    this.username,
    this.itemName,
    this.reason,
    this.quantity = 1,
    this.managerNote,
  });

  static int? _int(dynamic v) =>
      v is int ? v : (v is String ? int.tryParse(v) : null);

  /// What's being asked for, whichever field the API filled.
  String get displayName => equipmentName ?? itemName ?? 'Equipment';

  factory EquipmentRequest.fromJson(Map<String, dynamic> json) {
    return EquipmentRequest(
      equipRequestId: _int(json['equip_request_id'])!,
      equipmentId: _int(json['equipment_id']),
      status: json['status'] as String? ?? 'pending',
      requestDate:
          DateTime.tryParse(json['request_date'] as String? ?? '') ??
          DateTime.now(),
      equipmentName: json['equipment_name'] as String?,
      username: json['username'] as String?,
      itemName: json['item_name'] as String?,
      reason: json['reason'] as String?,
      quantity: _int(json['quantity']) ?? 1,
      managerNote: json['manager_note'] as String?,
    );
  }
}
