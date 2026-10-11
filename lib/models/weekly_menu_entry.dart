class WeeklyMenuEntry {
  final int menuId;
  final String dayOfWeek;
  final String breakfast;
  final String lunch;
  final String dinner;

  WeeklyMenuEntry({
    required this.menuId,
    required this.dayOfWeek,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
  });

  factory WeeklyMenuEntry.fromJson(Map<String, dynamic> json) {
    return WeeklyMenuEntry(
      menuId: json['menu_id'] is String
          ? int.parse(json['menu_id'])
          : json['menu_id'] as int,
      dayOfWeek: json['day_of_week'] as String,
      breakfast: json['breakfast'] as String,
      lunch: json['lunch'] as String,
      dinner: json['dinner'] as String,
    );
  }
}
