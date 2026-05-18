class Assignment {
  final String etlId;
  final String title;
  final String courseName;
  final DateTime dueDate;
  final bool dateOnly;
  final String url;

  const Assignment({
    required this.etlId,
    required this.title,
    required this.courseName,
    required this.dueDate,
    required this.dateOnly,
    required this.url,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) => Assignment(
        etlId: json['etlId'] as String,
        title: json['title'] as String,
        courseName: json['courseName'] as String? ?? '',
        dueDate: DateTime.parse(json['dueDate'] as String),
        dateOnly: json['dateOnly'] as bool? ?? false,
        url: json['url'] as String? ?? '',
      );

  /// 남은 시간 (음수면 마감 지남)
  Duration get remaining => dueDate.difference(DateTime.now());

  int get dDayNumber {
    final days = dueDate.difference(DateTime.now()).inDays;
    return days;
  }

  bool get isUrgent => remaining.inHours < 24 && !isOverdue;

  bool get isOverdue {
    if (dateOnly) {
      // dateOnly 과제는 당일 23:59:59까지 유효
      final endOfDay = DateTime(dueDate.year, dueDate.month, dueDate.day, 23, 59, 59);
      return DateTime.now().isAfter(endOfDay);
    }
    return remaining.inSeconds < 0;
  }
}
