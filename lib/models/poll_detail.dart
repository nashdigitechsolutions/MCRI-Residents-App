import 'poll.dart';

class PollDetail {
  final int pollId;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
  final List<PollOption> options;
  final List<int> myOptionIds;

  /// 'none', 'daily' or 'weekly'.
  final String recurrence;

  PollDetail({
    required this.pollId,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.options,
    required this.myOptionIds,
    this.recurrence = 'none',
  });

  factory PollDetail.fromJson(Map<String, dynamic> json) {
    return PollDetail(
      pollId: json['poll_id'] is String
          ? int.parse(json['poll_id'])
          : json['poll_id'] as int,
      title: json['title'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      isActive: json['is_active'] as bool? ?? false,
      options: (json['options'] as List? ?? [])
          .map((o) => PollOption.fromJson(o as Map<String, dynamic>))
          .toList(),
      myOptionIds: (json['my_option_ids'] as List? ?? [])
          .map((id) => id is String ? int.parse(id) : id as int)
          .toList(),
      recurrence: json['recurrence'] as String? ?? 'none',
    );
  }

  int get totalVotes => options.fold(0, (sum, o) => sum + o.voteCount);

  /// Opens in the future (only admins can see these).
  bool get isScheduled => isActive && startDate.isAfter(DateTime.now());

  bool get isOpen =>
      isActive &&
      !startDate.isAfter(DateTime.now()) &&
      endDate.isAfter(DateTime.now());

  bool get repeats => recurrence == 'daily' || recurrence == 'weekly';
}
