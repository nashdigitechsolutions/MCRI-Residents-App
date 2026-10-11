import 'attendance_status.dart';

class Event {
  final int eventId;
  final String title;
  final String? description;
  final String? location;
  final DateTime startDate;
  final DateTime endDate;
  final AttendanceStatus? myAttendanceStatus;

  Event({
    required this.eventId,
    required this.title,
    this.description,
    this.location,
    required this.startDate,
    required this.endDate,
    this.myAttendanceStatus,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      eventId: json['event_id'] is String
          ? int.parse(json['event_id'])
          : json['event_id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      location: json['location'] as String?,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      myAttendanceStatus: AttendanceStatusJson.fromJson(
        json['my_attendance_status'] as String?,
      ),
    );
  }
}
