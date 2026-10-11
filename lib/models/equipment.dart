enum EquipmentStatus { available, inUse, reserved, maintenance, retired }

extension EquipmentStatusJson on EquipmentStatus {
  static EquipmentStatus fromJson(String value) {
    switch (value) {
      case 'available':
        return EquipmentStatus.available;
      case 'in_use':
        return EquipmentStatus.inUse;
      case 'reserved':
        return EquipmentStatus.reserved;
      case 'maintenance':
        return EquipmentStatus.maintenance;
      case 'retired':
        return EquipmentStatus.retired;
      default:
        return EquipmentStatus.available;
    }
  }

  String get label {
    switch (this) {
      case EquipmentStatus.available:
        return 'Available';
      case EquipmentStatus.inUse:
        return 'In use';
      case EquipmentStatus.reserved:
        return 'Reserved';
      case EquipmentStatus.maintenance:
        return 'Maintenance';
      case EquipmentStatus.retired:
        return 'Retired';
    }
  }
}

class Equipment {
  final int equipmentId;
  final String equipmentName;
  final String? category;
  final EquipmentStatus status;

  Equipment({
    required this.equipmentId,
    required this.equipmentName,
    this.category,
    required this.status,
  });

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      equipmentId: json['equipment_id'] is String
          ? int.parse(json['equipment_id'])
          : json['equipment_id'] as int,
      equipmentName: json['equipment_name'] as String,
      category: json['category'] as String?,
      status: EquipmentStatusJson.fromJson(json['status'] as String),
    );
  }
}
