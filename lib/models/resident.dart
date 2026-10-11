class Resident {
  final int residentId;
  final int userId;
  final int? roomId;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? roomNumber;

  Resident({
    required this.residentId,
    required this.userId,
    this.roomId,
    required this.username,
    this.firstName,
    this.lastName,
    this.roomNumber,
  });

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : username;
  }

  factory Resident.fromJson(Map<String, dynamic> json) {
    return Resident(
      residentId: json['resident_id'] is String
          ? int.parse(json['resident_id'])
          : json['resident_id'] as int,
      userId: json['user_id'] is String
          ? int.parse(json['user_id'])
          : json['user_id'] as int,
      roomId: json['room_id'] == null
          ? null
          : (json['room_id'] is String
                ? int.parse(json['room_id'])
                : json['room_id'] as int),
      username: json['username'] as String? ?? '',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      roomNumber: json['room_number'] as String?,
    );
  }
}
