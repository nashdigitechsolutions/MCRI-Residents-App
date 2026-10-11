class PollVoteRow {
  final int userId;
  final String residentName;
  final String? roomNumber;
  final String? lunchboxNumber;
  final String optionName;
  final DateTime? votedAt;

  PollVoteRow({
    required this.userId,
    required this.residentName,
    this.roomNumber,
    this.lunchboxNumber,
    required this.optionName,
    this.votedAt,
  });

  factory PollVoteRow.fromJson(Map<String, dynamic> json) {
    return PollVoteRow(
      userId: json['user_id'] is String
          ? int.parse(json['user_id'])
          : json['user_id'] as int,
      residentName: json['resident_name'] as String? ?? '',
      roomNumber: json['room_number'] as String?,
      lunchboxNumber: json['lunchbox_number'] as String?,
      optionName: json['option_name'] as String? ?? '',
      votedAt: json['voted_at'] == null
          ? null
          : DateTime.tryParse(json['voted_at'] as String),
    );
  }
}
