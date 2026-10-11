class Conversation {
  final int conversationId;
  final String? conversationName;
  final bool isGroup;
  final String? otherMemberName;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastActivityType; // 'message' | 'reaction'
  final DateTime? lastActivityAt;
  final bool lastActivityByMe;
  final String? lastReactionEmoji;
  final String? lastActivityUserName;
  final int? createdBy;
  final DateTime? myLastReadAt;

  Conversation({
    required this.conversationId,
    this.conversationName,
    required this.isGroup,
    this.otherMemberName,
    this.lastMessage,
    this.lastMessageAt,
    this.lastActivityType,
    this.lastActivityAt,
    this.lastActivityByMe = false,
    this.lastReactionEmoji,
    this.lastActivityUserName,
    this.createdBy,
    this.myLastReadAt,
  });

  String get displayName {
    if (conversationName != null && conversationName!.isNotEmpty) {
      return conversationName!;
    }
    if (!isGroup && otherMemberName != null && otherMemberName!.isNotEmpty) {
      return otherMemberName!;
    }
    return isGroup ? 'Group chat' : 'Direct message';
  }

  String get activityPreview {
    if (lastActivityType == null) return 'No messages yet';
    final who = lastActivityByMe
        ? 'You'
        : (isGroup ? (lastActivityUserName ?? 'Someone') : null);
    if (lastActivityType == 'reaction') {
      final emoji = lastReactionEmoji ?? '👍';
      return who != null ? '$who reacted $emoji' : 'Reacted $emoji';
    }
    final text = lastMessage ?? '';
    return who != null ? '$who: $text' : text;
  }

  bool get isUnread {
    if (lastActivityByMe) return false;
    final at = lastActivityAt ?? lastMessageAt;
    if (at == null) return false;
    if (myLastReadAt == null) return true;
    return at.isAfter(myLastReadAt!);
  }

  Conversation copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastActivityType,
    DateTime? lastActivityAt,
    bool? lastActivityByMe,
    DateTime? myLastReadAt,
  }) {
    return Conversation(
      conversationId: conversationId,
      conversationName: conversationName,
      isGroup: isGroup,
      otherMemberName: otherMemberName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastActivityType: lastActivityType ?? this.lastActivityType,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      lastActivityByMe: lastActivityByMe ?? this.lastActivityByMe,
      lastReactionEmoji: lastReactionEmoji,
      lastActivityUserName: lastActivityUserName,
      createdBy: createdBy,
      myLastReadAt: myLastReadAt ?? this.myLastReadAt,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      conversationId: json['conversation_id'] is String
          ? int.parse(json['conversation_id'])
          : json['conversation_id'] as int,
      conversationName: json['conversation_name'] as String?,
      isGroup: json['is_group'] as bool? ?? false,
      otherMemberName: json['other_member_name'] as String?,
      lastMessage: json['last_message'] as String?,
      lastMessageAt: json['last_message_at'] == null
          ? null
          : DateTime.tryParse(json['last_message_at'] as String),
      lastActivityType: json['last_activity_type'] as String?,
      lastActivityAt: json['last_activity_at'] == null
          ? null
          : DateTime.tryParse(json['last_activity_at'] as String),
      lastActivityByMe: json['last_activity_by_me'] as bool? ?? false,
      lastReactionEmoji: json['last_reaction_emoji'] as String?,
      lastActivityUserName: json['last_activity_user_name'] as String?,
      createdBy: json['created_by'] == null
          ? null
          : (json['created_by'] is String
                ? int.parse(json['created_by'])
                : json['created_by'] as int),
      myLastReadAt: json['my_last_read_at'] == null
          ? null
          : DateTime.tryParse(json['my_last_read_at'] as String),
    );
  }
}
