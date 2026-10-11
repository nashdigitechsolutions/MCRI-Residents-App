class Announcement {
  final int announcementId;
  final String title;
  final String message;
  final String? creatorName;
  final DateTime createdAt;
  final String? userReaction;

  Announcement({
    required this.announcementId,
    required this.title,
    required this.message,
    this.creatorName,
    required this.createdAt,
    this.userReaction,
  });

  Announcement copyWith({String? userReaction}) {
    return Announcement(
      announcementId: announcementId,
      title: title,
      message: message,
      creatorName: creatorName,
      createdAt: createdAt,
      userReaction: userReaction,
    );
  }

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      announcementId: json['announcement_id'] is String
          ? int.parse(json['announcement_id'])
          : json['announcement_id'] as int,
      title: json['title'] as String,
      message: json['message'] as String,
      creatorName: json['creator_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      userReaction: json['user_reaction'] as String?,
    );
  }
}
