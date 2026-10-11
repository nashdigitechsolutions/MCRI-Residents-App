class User {
  final int userId;
  final String email;
  final String username;
  final int? roleId;

  User({
    required this.userId,
    required this.email,
    required this.username,
    this.roleId,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['user_id'] is String
          ? int.parse(json['user_id'])
          : json['user_id'] as int,
      email: json['email'] as String? ?? '',
      username: json['username'] as String? ?? '',
      roleId: json['role_id'] == null
          ? null
          : (json['role_id'] is String
                ? int.parse(json['role_id'])
                : json['role_id'] as int),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'email': email,
      'username': username,
      'role_id': roleId,
    };
  }
}
