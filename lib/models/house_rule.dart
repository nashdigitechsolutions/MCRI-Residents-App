class HouseRule {
  final int ruleId;
  final String title;
  final String? description;

  HouseRule({required this.ruleId, required this.title, this.description});

  factory HouseRule.fromJson(Map<String, dynamic> json) {
    return HouseRule(
      ruleId: json['rule_id'] is String
          ? int.parse(json['rule_id'])
          : json['rule_id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
    );
  }
}
