class Reaction {
  final int userId;
  final String emoji;
  final String? username;
  final String? firstName;
  final String? lastName;

  Reaction({
    required this.userId,
    required this.emoji,
    this.username,
    this.firstName,
    this.lastName,
  });

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : (username ?? 'User $userId');
  }

  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      userId: json['user_id'] is String
          ? int.parse(json['user_id'])
          : json['user_id'] as int,
      emoji: json['emoji'] as String,
      username: json['username'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
    );
  }
}
