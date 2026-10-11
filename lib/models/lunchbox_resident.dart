class LunchboxResident {
  final int residentId;
  final int userId;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? roomNumber;
  final String? lunchboxNumber;

  LunchboxResident({
    required this.residentId,
    required this.userId,
    required this.username,
    this.firstName,
    this.lastName,
    this.roomNumber,
    this.lunchboxNumber,
  });

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : username;
  }

  factory LunchboxResident.fromJson(Map<String, dynamic> json) {
    return LunchboxResident(
      residentId: json['resident_id'] is String
          ? int.parse(json['resident_id'])
          : json['resident_id'] as int,
      userId: json['user_id'] is String
          ? int.parse(json['user_id'])
          : json['user_id'] as int,
      username: json['username'] as String? ?? '',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      roomNumber: json['room_number'] as String?,
      lunchboxNumber: json['lunchbox_number'] as String?,
    );
  }
}
