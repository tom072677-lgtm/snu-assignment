import 'dart:convert';

class TimetableCourse {
  final String id;
  final String name;
  final String courseCode;

  const TimetableCourse({
    required this.id,
    required this.name,
    required this.courseCode,
  });

  factory TimetableCourse.fromJson(Map<String, dynamic> j) => TimetableCourse(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        courseCode: j['courseCode'] as String? ?? '',
      );
}

// 요일 코드: MO TU WE TH FR SA SU
class ClassSession {
  final String uid;
  final String summary;
  final String location;
  final String startTime; // HH:mm
  final String endTime;   // HH:mm
  final List<String> weekdays; // ['MO', 'WE']

  const ClassSession({
    required this.uid,
    required this.summary,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.weekdays,
  });

  factory ClassSession.fromJson(Map<String, dynamic> j) => ClassSession(
        uid: j['uid'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        location: j['location'] as String? ?? '',
        startTime: j['startTime'] as String? ?? '',
        endTime: j['endTime'] as String? ?? '',
        weekdays: List<String>.from(j['weekdays'] as List? ?? []),
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'summary': summary,
        'location': location,
        'startTime': startTime,
        'endTime': endTime,
        'weekdays': weekdays,
      };

  static const _dayOrder = {
    'MO': 0, 'TU': 1, 'WE': 2, 'TH': 3, 'FR': 4, 'SA': 5, 'SU': 6
  };
  bool get isToday {
    final today = _dayOrder.keys.toList()[DateTime.now().weekday - 1];
    return weekdays.contains(today);
  }
}

class TimetableData {
  final List<TimetableCourse> courses;
  final List<ClassSession> sessions;

  const TimetableData({required this.courses, required this.sessions});

  factory TimetableData.fromJson(Map<String, dynamic> j) => TimetableData(
        courses: (j['courses'] as List? ?? [])
            .map((e) => TimetableCourse.fromJson(e as Map<String, dynamic>))
            .toList(),
        sessions: (j['sessions'] as List? ?? [])
            .map((e) => ClassSession.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  List<ClassSession> get todaySessions =>
      sessions.where((s) => s.isToday).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  bool get hasSchedule => sessions.isNotEmpty;
}

// ── 커스텀 일정 (학원, 과외 등) ────────────────────────────────────
class CustomEvent {
  final String id;
  final String title;
  final String location;       // 빈 문자열 = 없음
  final List<String> weekdays; // ['MO', 'TH']
  final String startTime;      // 'HH:mm'
  final String endTime;        // 'HH:mm'
  final int colorIndex;        // 0~7

  const CustomEvent({
    required this.id,
    required this.title,
    this.location = '',
    required this.weekdays,
    required this.startTime,
    required this.endTime,
    this.colorIndex = 0,
  });

  factory CustomEvent.fromJson(Map<String, dynamic> j) => CustomEvent(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        location: j['location'] as String? ?? '',
        weekdays: List<String>.from(j['weekdays'] as List? ?? []),
        startTime: j['startTime'] as String? ?? '',
        endTime: j['endTime'] as String? ?? '',
        colorIndex: (j['colorIndex'] as num? ?? 0).toInt().clamp(0, 7),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'location': location,
        'weekdays': weekdays,
        'startTime': startTime,
        'endTime': endTime,
        'colorIndex': colorIndex,
      };

  // JSON List 직렬화 헬퍼
  static String encodeList(List<CustomEvent> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<CustomEvent> decodeList(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => CustomEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
