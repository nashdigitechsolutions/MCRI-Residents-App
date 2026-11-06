import 'dart:convert';

class AppNotification {
  final int userNotificationId;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  /// Where tapping it should go ({screen, poll_id, conversation_id, …}).
  final Map<String, dynamic>? route;

  AppNotification({
    required this.userNotificationId,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.route,
  });

  static Map<String, dynamic>? _parseRoute(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final id = json['user_notification_id'];
    return AppNotification(
      userNotificationId: id is String ? int.parse(id) : id as int,
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      isRead: json['is_read'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      route: _parseRoute(json['data'] ?? json['route']),
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      userNotificationId: userNotificationId,
      title: title,
      message: message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      route: route,
    );
  }
}
