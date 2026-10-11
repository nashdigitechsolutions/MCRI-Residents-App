import 'duty_status.dart';

class Duty {
  final int dutyId;
  final String title;
  final String? description;
  final int assignedTo;
  final DateTime assignedDate;
  final DutyStatus status;

  Duty({
    required this.dutyId,
    required this.title,
    this.description,
    required this.assignedTo,
    required this.assignedDate,
    required this.status,
  });

  factory Duty.fromJson(Map<String, dynamic> json) {
    return Duty(
      dutyId: json['duty_id'] is String
          ? int.parse(json['duty_id'])
          : json['duty_id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      assignedTo: json['assigned_to'] is String
          ? int.parse(json['assigned_to'])
          : json['assigned_to'] as int,
      assignedDate: DateTime.parse(json['assigned_date'] as String),
      status: DutyStatusJson.fromJson(json['status'] as String),
    );
  }

  Duty copyWith({DutyStatus? status}) {
    return Duty(
      dutyId: dutyId,
      title: title,
      description: description,
      assignedTo: assignedTo,
      assignedDate: assignedDate,
      status: status ?? this.status,
    );
  }
}
