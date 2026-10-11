import 'reaction.dart';

class ChatMessage {
  final int messageId;
  final int conversationId;
  final int senderId;
  final String? message; // null when soft-deleted
  final DateTime createdAt;
  final int? replyToMessageId;
  final String? replyMessage;
  final int? replySenderId;
  final DateTime? editedAt;
  final bool isDeleted;
  final bool isPinned;
  final List<Reaction> reactions;

  ChatMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    this.message,
    required this.createdAt,
    this.replyToMessageId,
    this.replyMessage,
    this.replySenderId,
    this.editedAt,
    this.isDeleted = false,
    this.isPinned = false,
    this.reactions = const [],
  });

  ChatMessage copyWith({
    String? message,
    bool? isDeleted,
    bool? isPinned,
    DateTime? editedAt,
    List<Reaction>? reactions,
  }) {
    return ChatMessage(
      messageId: messageId,
      conversationId: conversationId,
      senderId: senderId,
      message: isDeleted == true ? null : (message ?? this.message),
      createdAt: createdAt,
      replyToMessageId: replyToMessageId,
      replyMessage: replyMessage,
      replySenderId: replySenderId,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      isPinned: isPinned ?? this.isPinned,
      reactions: reactions ?? this.reactions,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      messageId: json['message_id'] is String
          ? int.parse(json['message_id'])
          : json['message_id'] as int,
      conversationId: json['conversation_id'] is String
          ? int.parse(json['conversation_id'])
          : json['conversation_id'] as int,
      senderId: json['sender_id'] is String
          ? int.parse(json['sender_id'])
          : json['sender_id'] as int,
      message: json['message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      replyToMessageId: json['reply_to_message_id'] == null
          ? null
          : (json['reply_to_message_id'] is String
                ? int.parse(json['reply_to_message_id'])
                : json['reply_to_message_id'] as int),
      replyMessage: json['reply_message'] as String?,
      replySenderId: json['reply_sender_id'] == null
          ? null
          : (json['reply_sender_id'] is String
                ? int.parse(json['reply_sender_id'])
                : json['reply_sender_id'] as int),
      editedAt: json['edited_at'] == null
          ? null
          : DateTime.tryParse(json['edited_at'] as String),
      isDeleted: json['is_deleted'] as bool? ?? false,
      isPinned: json['is_pinned'] as bool? ?? false,
      reactions: (json['reactions'] as List? ?? [])
          .map((r) => Reaction.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}
