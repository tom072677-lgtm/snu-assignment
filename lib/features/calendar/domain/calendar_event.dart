class CalendarEvent {
  final String id;
  final String title;
  final DateTime dateTime;
  final String source; // 'user' | 'assignment' | 'holiday' | 'academic'

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.dateTime,
    this.source = 'user',
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'] as String,
        title: json['title'] as String,
        dateTime: DateTime.parse(json['dateTime'] as String),
        source: json['source'] as String? ?? 'user',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dateTime': dateTime.toIso8601String(),
        'source': source,
      };

  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? dateTime,
    String? source,
  }) =>
      CalendarEvent(
        id: id ?? this.id,
        title: title ?? this.title,
        dateTime: dateTime ?? this.dateTime,
        source: source ?? this.source,
      );
}

// 공휴일 (하드코딩, 매년 업데이트)
const List<({String title, String date})> holidays2026 = [
  (title: '신정', date: '2026-01-01'),
  (title: '설날 연휴', date: '2026-02-15'),
  (title: '설날', date: '2026-02-17'),
  (title: '설날 연휴', date: '2026-02-18'),
  (title: '대체공휴일(설날)', date: '2026-02-19'),
  (title: '삼일절', date: '2026-03-01'),
  (title: '대체공휴일(삼일절)', date: '2026-03-02'),
  (title: '어린이날', date: '2026-05-05'),
  (title: '부처님오신날', date: '2026-05-24'),
  (title: '현충일', date: '2026-06-06'),
  (title: '대체공휴일(현충일)', date: '2026-06-08'),
  (title: '광복절', date: '2026-08-15'),
  (title: '대체공휴일(광복절)', date: '2026-08-17'),
  (title: '추석 연휴', date: '2026-09-23'),
  (title: '추석 연휴', date: '2026-09-24'),
  (title: '추석', date: '2026-09-25'),
  (title: '대체공휴일(추석)', date: '2026-09-28'),
  (title: '개천절', date: '2026-10-03'),
  (title: '대체공휴일(개천절)', date: '2026-10-05'),
  (title: '한글날', date: '2026-10-09'),
  (title: '성탄절', date: '2026-12-25'),
];
