class Attendee {
  final int userId;
  final String attendanceStatus;
  final String username;
  final String? firstName;
  final String? lastName;

  Attendee({
    required this.userId,
    required this.attendanceStatus,
    required this.username,
    this.firstName,
    this.lastName,
  });

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : username;
  }

  factory Attendee.fromJson(Map<String, dynamic> json) {
    return Attendee(
      userId: json['user_id'] is String
          ? int.parse(json['user_id'])
          : json['user_id'] as int,
      attendanceStatus: json['attendance_status'] as String? ?? 'invited',
      username: json['username'] as String? ?? '',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
    );
  }
}
