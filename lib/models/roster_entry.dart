class RosterEntry {
  final int rosterId;
  final int dayOfWeek; // 1=Monday..7=Sunday
  final String dayName;
  final int userId;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? gender;

  RosterEntry({
    required this.rosterId,
    required this.dayOfWeek,
    required this.dayName,
    required this.userId,
    required this.username,
    this.firstName,
    this.lastName,
    this.gender,
  });

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : username;
  }

  factory RosterEntry.fromJson(Map<String, dynamic> json) {
    return RosterEntry(
      rosterId: json['roster_id'] is String
          ? int.parse(json['roster_id'])
          : json['roster_id'] as int,
      dayOfWeek: json['day_of_week'] is String
          ? int.parse(json['day_of_week'])
          : json['day_of_week'] as int,
      dayName: json['day_name'] as String? ?? '',
      userId: json['user_id'] is String
          ? int.parse(json['user_id'])
          : json['user_id'] as int,
      username: json['username'] as String? ?? '',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      gender: json['gender'] as String?,
    );
  }
}
