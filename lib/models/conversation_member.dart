class ConversationMember {
  final int userId;
  final String? firstName;
  final String? lastName;
  final String? username;
  final String? phone;
  final bool? isAvailable;
  final int? roleId;

  ConversationMember({
    required this.userId,
    this.firstName,
    this.lastName,
    this.username,
    this.phone,
    this.isAvailable,
    this.roleId,
  });

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    if (username != null && username!.isNotEmpty) return username!;
    return 'User $userId';
  }

  String get initials {
    final f = (firstName ?? '').trim();
    final l = (lastName ?? '').trim();
    if (f.isNotEmpty || l.isNotEmpty) {
      final a = f.isNotEmpty ? f[0] : '';
      final b = l.isNotEmpty ? l[0] : (f.length > 1 ? f[1] : '');
      final r = (a + b).toUpperCase();
      return r.isNotEmpty ? r : '?';
    }
    if (username != null && username!.isNotEmpty) {
      return username!
          .substring(0, username!.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return 'U';
  }

  factory ConversationMember.fromJson(Map<String, dynamic> json) {
    return ConversationMember(
      userId: json['user_id'] is String
          ? int.parse(json['user_id'])
          : json['user_id'] as int,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      username: json['username'] as String?,
      phone: json['phone'] as String?,
      isAvailable: json['is_available'] as bool?,
      roleId: json['role_id'] == null
          ? null
          : (json['role_id'] is String
                ? int.parse(json['role_id'])
                : json['role_id'] as int),
    );
  }
}
