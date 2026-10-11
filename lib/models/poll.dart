class PollOption {
  final int id;
  final String optionName;
  final int voteCount;

  PollOption({required this.id, required this.optionName, this.voteCount = 0});

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      id: json['id'] is String ? int.parse(json['id']) : json['id'] as int,
      optionName: json['option_name'] as String,
      voteCount: json['vote_count'] as int? ?? 0,
    );
  }
}

class Poll {
  final int pollId;
  final String title;
  final DateTime endDate;
  final bool isActive;

  Poll({
    required this.pollId,
    required this.title,
    required this.endDate,
    required this.isActive,
  });

  factory Poll.fromJson(Map<String, dynamic> json) {
    return Poll(
      pollId: json['poll_id'] is String
          ? int.parse(json['poll_id'])
          : json['poll_id'] as int,
      title: json['title'] as String,
      endDate: DateTime.parse(json['end_date'] as String),
      isActive: json['is_active'] as bool? ?? false,
    );
  }
}
