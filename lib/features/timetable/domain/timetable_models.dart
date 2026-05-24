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

  static const _dayOrder = {'MO': 0, 'TU': 1, 'WE': 2, 'TH': 3, 'FR': 4, 'SA': 5, 'SU': 6};
  bool get isToday {
    final today = _dayOrder.keys.toList()[DateTime.now().weekday - 1]; // Mon=0
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
