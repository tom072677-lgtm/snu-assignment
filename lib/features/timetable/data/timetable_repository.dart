import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../../../shared/providers/settings_provider.dart';
import '../domain/timetable_models.dart';
import 'ical_session_parser.dart';

/// iCal / Canvas API 직접 호출 전용 Dio (base URL 없음)
final _externalDio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 20),
));

const _etlBase = 'https://myetl.snu.ac.kr';

class TimetableRepository {
  Future<TimetableData> fetch({
    required String icalUrl,
    String? canvasToken,
  }) async {
    // ① 서버에서 Canvas 과목 목록 + 서버 파싱 세션 가져오기
    List<TimetableCourse> courses = [];
    List<ClassSession> serverSessions = [];
    try {
      final res = await DioClient.instance.post(
        '/api/timetable',
        data: {
          'icalUrl': icalUrl,
          if (canvasToken != null && canvasToken.isNotEmpty)
            'canvasToken': canvasToken,
        },
      );
      final data = res.data as Map<String, dynamic>;
      courses = (data['courses'] as List? ?? [])
          .map((e) => TimetableCourse.fromJson(e as Map<String, dynamic>))
          .toList();
      // 서버가 세션을 파싱해서 돌려주면 우선 사용 (Flutter web/CORS 환경 대비)
      serverSessions = (data['sessions'] as List? ?? [])
          .map((e) => ClassSession.fromJson(e as Map<String, dynamic>))
          .toList();
      debugPrint('[Timetable] 서버 sessions=${serverSessions.length}');
    } catch (e) {
      debugPrint('[Timetable] 서버 courses 오류: $e');
    }

    // ② 개인 iCal 직접 파싱 시도
    List<ClassSession> sessions = await _parseIcalDirect(icalUrl);
    debugPrint('[Timetable] iCal 직접 파싱 sessions=${sessions.length}');

    // ③ [신규] 과목별 iCal 피드 파싱 (course.calendar.ics) — 가장 유력한 경로
    if (sessions.isEmpty && canvasToken != null && canvasToken.isNotEmpty) {
      debugPrint('[Timetable] 과목별 ICS 시도...');
      sessions = await _fetchCourseIcsSessions(canvasToken);
      debugPrint('[Timetable] 과목별 ICS sessions=${sessions.length}');
    }

    // ④ [신규] Canvas Planner API
    if (sessions.isEmpty && canvasToken != null && canvasToken.isNotEmpty) {
      debugPrint('[Timetable] Planner API 시도...');
      sessions = await _fetchPlannerSessions(canvasToken);
      debugPrint('[Timetable] Planner API sessions=${sessions.length}');
    }

    // ⑤ Canvas REST calendar_events API
    if (sessions.isEmpty &&
        canvasToken != null &&
        canvasToken.isNotEmpty &&
        courses.isNotEmpty) {
      debugPrint('[Timetable] Canvas calendar_events API 시도...');
      sessions = await _fetchCanvasCalendarSessions(
          canvasToken, courses.map((c) => c.id).toList());
      debugPrint('[Timetable] Canvas calendar_events sessions=${sessions.length}');
    }

    // ⑥ course sections API 시도
    if (sessions.isEmpty &&
        canvasToken != null &&
        canvasToken.isNotEmpty &&
        courses.isNotEmpty) {
      debugPrint('[Timetable] Canvas sections API 시도...');
      sessions = await _fetchCourseSections(canvasToken, courses);
      debugPrint('[Timetable] Canvas sections sessions=${sessions.length}');
    }

    // 클라이언트 파싱 실패 시 서버 세션으로 폴백
    if (sessions.isEmpty && serverSessions.isNotEmpty) {
      debugPrint('[Timetable] 서버 sessions 폴백 사용: ${serverSessions.length}개');
      sessions = serverSessions;
    }

    return TimetableData(courses: courses, sessions: sessions);
  }

  // ── iCal 직접 파싱 ────────────────────────────────────────────────

  Future<List<ClassSession>> _parseIcalDirect(String icalUrl) async {
    try {
      final httpsUrl = icalUrl.replaceFirst(
          RegExp(r'^webcal://', caseSensitive: false), 'https://');
      final res = await _externalDio.get<String>(
        httpsUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final text = res.data;
      if (text == null || text.isEmpty) return [];
      return IcalSessionParser.parse(text);
    } catch (e) {
      debugPrint('[Timetable] iCal 직접 파싱 실패: $e');
      return [];
    }
  }

  // ── 과목별 iCal 피드 파싱 (course.calendar.ics) ──────────────────────

  Future<List<ClassSession>> _fetchCourseIcsSessions(String token) async {
    final sessions = <ClassSession>[];
    final seen = <String>{};

    try {
      // 1) 과목 목록 + calendar.ics URL 가져오기 (pagination 대응)
      final courseIcsUrls = <String>[];
      var nextUrl = '$_etlBase/api/v1/courses?enrollment_state=active&per_page=50';
      int pageLimit = 3;
      while (nextUrl.isNotEmpty && pageLimit-- > 0) {
        final res = await _externalDio.get<dynamic>(
          nextUrl,
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
            responseType: ResponseType.json,
          ),
        );
        final list = res.data as List<dynamic>? ?? [];
        debugPrint('[Timetable] courses page: ${list.length}개');
        for (final raw in list) {
          final c = raw as Map<String, dynamic>;
          final ics = (c['calendar'] as Map<String, dynamic>?)?['ics'] as String?;
          if (ics != null && ics.isNotEmpty) {
            courseIcsUrls.add(ics);
          }
        }
        // Link 헤더 next 페이지
        final linkHeader = res.headers.value('link') ?? '';
        final nextMatch = RegExp(r'<([^>]+)>;\s*rel="next"').firstMatch(linkHeader);
        nextUrl = nextMatch?.group(1) ?? '';
      }
      debugPrint('[Timetable] 과목별 ICS URL 수: ${courseIcsUrls.length}');

      // 2) 각 ICS 다운로드 및 파싱
      for (final icsUrl in courseIcsUrls) {
        try {
          final httpsUrl = icsUrl.replaceFirst(
              RegExp(r'^webcal://', caseSensitive: false), 'https://');
          final res = await _externalDio.get<String>(
            httpsUrl,
            options: Options(
              headers: {'Authorization': 'Bearer $token'},
              responseType: ResponseType.plain,
            ),
          );
          final text = res.data;
          if (text == null || text.isEmpty) continue;

          final parsed = IcalSessionParser.parse(text);
          for (final s in parsed) {
            // 중복 제거: uid 또는 summary+time 기준
            final dedupeKey = '${s.uid}|${s.summary}|${s.startTime}';
            if (seen.add(dedupeKey)) {
              sessions.add(s);
            }
          }
        } catch (e) {
          debugPrint('[Timetable] 과목별 ICS 오류: $e');
        }
      }
    } catch (e) {
      debugPrint('[Timetable] 과목별 ICS 전체 오류: $e');
    }
    return sessions;
  }

  // ── Canvas Planner API ────────────────────────────────────────────

  Future<List<ClassSession>> _fetchPlannerSessions(String token) async {
    final sessions = <ClassSession>[];
    try {
      // 현재 학기 기간 (동적 계산)
      final now = DateTime.now();
      final semStart = now.month <= 6
          ? DateTime(now.year, 1, 1)
          : DateTime(now.year, 7, 1);
      final semEnd = now.month <= 6
          ? DateTime(now.year, 6, 30)
          : DateTime(now.year, 12, 31);

      final rawEvents = <Map<String, dynamic>>[];
      var nextUrl =
          '$_etlBase/api/v1/planner/items'
          '?start_date=${semStart.toIso8601String().substring(0, 10)}'
          '&end_date=${semEnd.toIso8601String().substring(0, 10)}'
          '&per_page=100';
      int pageLimit = 5;
      while (nextUrl.isNotEmpty && pageLimit-- > 0) {
        final res = await _externalDio.get<dynamic>(
          nextUrl,
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
            responseType: ResponseType.json,
          ),
        );
        final list = res.data as List<dynamic>? ?? [];
        debugPrint('[Timetable] Planner page: ${list.length}개');
        for (final raw in list) {
          rawEvents.add(raw as Map<String, dynamic>);
        }
        final linkHeader = res.headers.value('link') ?? '';
        final nextMatch = RegExp(r'<([^>]+)>;\s*rel="next"').firstMatch(linkHeader);
        nextUrl = nextMatch?.group(1) ?? '';
      }

      debugPrint('[Timetable] Planner 총 ${rawEvents.length}개 항목');
      // 샘플 5개 로그 (개인정보 마스킹: plannable_type, context_name, date만)
      for (int i = 0; i < rawEvents.length && i < 5; i++) {
        final e = rawEvents[i];
        debugPrint('[Timetable] planner[$i] type=${e['plannable_type']} '
            'context=${e['context_name']} date=${e['plannable_date']}');
      }

      // "calendar_event" 타입만 필터링해서 수업 패턴 추론
      final calEvents = rawEvents
          .where((e) => e['plannable_type'] == 'calendar_event')
          .toList();
      debugPrint('[Timetable] Planner calendar_event 수: ${calEvents.length}');

      if (calEvents.isNotEmpty) {
        // Canvas calendar_events 파싱 로직 재사용
        final adapted = calEvents.map((e) {
          final plannable = e['plannable'] as Map<String, dynamic>? ?? {};
          return <String, dynamic>{
            'title': plannable['title'] ?? e['context_name'] ?? '',
            'start_at': plannable['start_at'] ?? e['plannable_date'],
            'end_at': plannable['end_at'],
            'location_name': plannable['location_name'] ?? '',
            'rrule': plannable['rrule'],
            'id': plannable['id'],
            'context_code': e['context_type'] == 'Course'
                ? 'course_${e['course_id']}'
                : '',
          };
        }).toList();
        sessions.addAll(_parseCanvasEvents(adapted));
      }
    } catch (e) {
      debugPrint('[Timetable] Planner API 오류: $e');
    }
    return sessions;
  }

  // ── Canvas REST API calendar_events 파싱 ──────────────────────────

  Future<List<ClassSession>> _fetchCanvasCalendarSessions(
      String token, List<String> courseIds) async {
    final sessions = <ClassSession>[];
    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 1, 1);
      final endDate = DateTime(now.year, now.month + 2, 28);

      final res = await _externalDio.get<dynamic>(
        '$_etlBase/api/v1/calendar_events',
        queryParameters: {
          'type': 'event',
          'all_events': '1',
          'per_page': '200',
          'start_date': startDate.toIso8601String().substring(0, 10),
          'end_date': endDate.toIso8601String().substring(0, 10),
          'context_codes[]': courseIds.map((id) => 'course_$id').toList(),
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.json,
        ),
      );

      final events = res.data as List<dynamic>? ?? [];
      debugPrint('[Timetable] Canvas calendar events 총 ${events.length}개');
      sessions.addAll(_parseCanvasEvents(events));
    } catch (e) {
      debugPrint('[Timetable] Canvas calendar_events 오류: $e');
    }
    return sessions;
  }

  List<ClassSession> _parseCanvasEvents(List<dynamic> events) {
    for (int i = 0; i < events.length && i < 5; i++) {
      final e = events[i] as Map<String, dynamic>;
      debugPrint('[Timetable] 이벤트[$i] title="${e['title']}" '
          'start=${e['start_at']} rrule=${e['rrule']}');
    }

    final sessions = <ClassSession>[];
    const dayNames = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
    const weekdays = {'MO', 'TU', 'WE', 'TH', 'FR'};

    for (final raw in events) {
      final e = raw as Map<String, dynamic>;
      final rrule = e['rrule'] as String?;
      if (rrule != null && rrule.isNotEmpty) {
        final s = _canvasEventToSession(e, rrule);
        if (s != null) sessions.add(s);
      }
    }

    if (sessions.isNotEmpty) return sessions;

    final groups = <String, _CanvasGroup>{};
    for (final raw in events) {
      final e = raw as Map<String, dynamic>;
      final title = (e['title'] as String? ?? '').trim();
      if (title.isEmpty) continue;
      final startStr = e['start_at'] as String?;
      final endStr = e['end_at'] as String?;
      if (startStr == null) continue;

      final start = DateTime.tryParse(startStr)?.toLocal();
      final end = endStr != null ? DateTime.tryParse(endStr)?.toLocal() : null;
      if (start == null) continue;

      String pad(int n) => n.toString().padLeft(2, '0');
      final startHM = '${pad(start.hour)}:${pad(start.minute)}';
      final endHM = end != null ? '${pad(end.hour)}:${pad(end.minute)}' : '';

      final key = '$title|$startHM|$endHM';
      groups.putIfAbsent(
        key,
        () => _CanvasGroup(
          title: title,
          location: e['location_name'] as String? ?? '',
          startTime: startHM,
          endTime: endHM,
          contextCode: e['context_code'] as String? ?? '',
        ),
      ).dates.add(start);
    }

    for (final entry in groups.entries) {
      final g = entry.value;
      if (g.dates.length < 3) continue;

      final wds = g.dates
          .map((d) => dayNames[d.weekday % 7])
          .where(weekdays.contains)
          .toSet()
          .toList()
        ..sort();

      if (wds.isEmpty) continue;

      sessions.add(ClassSession(
        uid: entry.key,
        summary: g.title,
        location: g.location,
        startTime: g.startTime,
        endTime: g.endTime,
        weekdays: wds,
      ));
    }

    return sessions;
  }

  ClassSession? _canvasEventToSession(Map<String, dynamic> e, String rrule) {
    final title = (e['title'] as String? ?? '').trim();
    if (title.isEmpty) return null;

    List<String> weekdays;
    final bydayM = RegExp(r'BYDAY=([^;]+)').firstMatch(rrule);
    if (bydayM != null) {
      weekdays = bydayM
          .group(1)!
          .split(',')
          .map((s) => s.trim().replaceAll(RegExp(r'^\d+'), '').toUpperCase())
          .where((s) => s.length == 2)
          .toList();
    } else {
      final startStr = e['start_at'] as String?;
      if (startStr == null) return null;
      final start = DateTime.tryParse(startStr)?.toLocal();
      if (start == null) return null;
      const names = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
      weekdays = [names[start.weekday % 7]];
    }

    final startStr = e['start_at'] as String?;
    final endStr = e['end_at'] as String?;
    if (startStr == null) return null;
    final start = DateTime.tryParse(startStr)?.toLocal();
    final end = endStr != null ? DateTime.tryParse(endStr)?.toLocal() : null;
    if (start == null) return null;

    String pad(int n) => n.toString().padLeft(2, '0');
    return ClassSession(
      uid: e['id']?.toString() ?? title,
      summary: title,
      location: e['location_name'] as String? ?? '',
      startTime: '${pad(start.hour)}:${pad(start.minute)}',
      endTime: end != null
          ? '${pad(end.hour)}:${pad(end.minute)}'
          : '${pad((start.hour + 1) % 24)}:${pad(start.minute)}',
      weekdays: weekdays,
    );
  }

  // ── Canvas sections → 수업 세션 ────────────────────────────────────

  Future<List<ClassSession>> _fetchCourseSections(
      String token, List<TimetableCourse> courses) async {
    final sessions = <ClassSession>[];

    for (final course in courses.take(15)) {
      try {
        final res = await _externalDio.get<dynamic>(
          '$_etlBase/api/v1/courses/${course.id}/sections',
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
          ),
        );
        final list = res.data as List<dynamic>? ?? [];
        for (int i = 0; i < list.length && i < 3; i++) {
          final s = list[i] as Map<String, dynamic>;
          debugPrint('[Timetable] section[${course.name}]: name="${s['name']}" '
              'start=${s['start_at']} end=${s['end_at']}');
        }
        for (final raw in list) {
          final s = raw as Map<String, dynamic>;
          final parsed = _sectionToSession(s, course);
          if (parsed != null) sessions.add(parsed);
        }
      } catch (e) {
        debugPrint('[Timetable] sections 오류 (${course.id}): $e');
      }
    }

    return sessions;
  }

  ClassSession? _sectionToSession(
      Map<String, dynamic> section, TimetableCourse course) {
    final name = (section['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;

    // 한국어 요일+시간 패턴: "화목 10:30-12:00" 또는 "월수금 09:00~10:00"
    final m = RegExp(
            r'([월화수목금]{1,5})\s+(\d{1,2}:\d{2})\s*[~\-]\s*(\d{1,2}:\d{2})')
        .firstMatch(name);
    if (m == null) return null;

    final weekdays = _parseKoreanDays(m.group(1)!);
    if (weekdays.isEmpty) return null;

    return ClassSession(
      uid: '${course.id}_section_${section['id']}',
      summary: course.name,
      location: section['location'] as String? ?? '',
      startTime: m.group(2)!,
      endTime: m.group(3)!,
      weekdays: weekdays,
    );
  }

  static const Map<String, String> _korDayMap = {
    '월': 'MO', '화': 'TU', '수': 'WE', '목': 'TH', '금': 'FR',
  };

  List<String> _parseKoreanDays(String str) {
    return str.split('').map((c) => _korDayMap[c]).whereType<String>().toList();
  }
}

class _CanvasGroup {
  final String title;
  final String location;
  final String startTime;
  final String endTime;
  final String contextCode;
  final List<DateTime> dates = [];

  _CanvasGroup({
    required this.title,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.contextCode,
  });
}

final timetableRepositoryProvider =
    Provider((_) => TimetableRepository());

final timetableProvider =
    FutureProvider.autoDispose<TimetableData>((ref) async {
  final icalUrl     = ref.watch(icalUrlProvider);
  final canvasToken = ref.watch(canvasTokenProvider);
  final mySNUSessions = ref.watch(mySNUSessionsProvider);

  // mySNU 세션이 있으면 Canvas API를 건너뛰고 즉시 반환
  if (mySNUSessions.isNotEmpty) {
    debugPrint('[Timetable] mySNU 세션 사용: ${mySNUSessions.length}개');
    // 과목 목록은 서버에서 가져오되 실패해도 OK
    List<TimetableCourse> courses = [];
    try {
      if (icalUrl != null && icalUrl.isNotEmpty) {
        final res = await DioClient.instance.post(
          '/api/timetable',
          data: {
            'icalUrl': icalUrl,
            if (canvasToken != null && canvasToken.isNotEmpty) 'canvasToken': canvasToken,
          },
        );
        final data = res.data as Map<String, dynamic>;
        courses = (data['courses'] as List? ?? [])
            .map((e) => TimetableCourse.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return TimetableData(courses: courses, sessions: mySNUSessions);
  }

  final urlPreview = icalUrl == null
      ? 'null'
      : icalUrl.substring(0, icalUrl.length.clamp(0, 40));
  debugPrint('[Timetable] icalUrl=$urlPreview '
      'hasToken=${canvasToken != null && canvasToken.isNotEmpty}');

  if (icalUrl == null || icalUrl.isEmpty) {
    debugPrint('[Timetable] icalUrl 없음 → 빈 데이터 반환');
    return const TimetableData(courses: [], sessions: []);
  }

  final result = await ref.read(timetableRepositoryProvider).fetch(
        icalUrl: icalUrl,
        canvasToken: canvasToken,
      );
  debugPrint('[Timetable] 최종 sessions=${result.sessions.length} '
      'courses=${result.courses.length}');
  return result;
});
