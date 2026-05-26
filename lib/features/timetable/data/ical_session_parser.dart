// ical_session_parser.dart — Flutter-side iCal → ClassSession 파서
//
// SNU eTL(Canvas) 개인 iCal 피드는 수업 일정을 RRULE 없이
// 매주 개별 VEVENT로 저장합니다.
// 이 파서는 두 가지 방식을 모두 처리합니다:
//  1) RRULE 방식 (BYDAY 추출)
//  2) 개별 VEVENT 그룹핑 (동일 summary·시간이 3회 이상 → 수업으로 추론)

import 'package:flutter/foundation.dart';
import '../domain/timetable_models.dart';

class IcalSessionParser {
  // ─── 공개 진입점 ────────────────────────────────────────────────

  /// raw iCal 텍스트 → ClassSession 목록 반환
  static List<ClassSession> parse(String icsText) {
    // RFC 5545 line folding 제거 (CRLF + SPACE/TAB → 연속으로 합침)
    final unfolded = icsText.replaceAll(RegExp(r'\r?\n[ \t]'), '');

    final blocks = _extractVEventBlocks(unfolded);
    debugPrint('[IcalParser] 총 VEVENT 수: ${blocks.length}');
    if (blocks.isEmpty) return [];

    // 이벤트 분류 통계
    int dateOnly = 0, withTime = 0, withRrule = 0;

    // 1차: RRULE 이벤트 파싱
    final sessions = <ClassSession>[];
    final nonRrule = <Map<String, _Prop>>[];

    for (final block in blocks) {
      final props = _parseProps(block);
      final dtProp = props['DTSTART'];
      final hasTime = dtProp != null && dtProp.value.contains('T');
      final isDateOnly = dtProp != null && !hasTime;
      if (isDateOnly) {
        dateOnly++;
      } else {
        withTime++;
      }
      if (props.containsKey('RRULE')) {
        withRrule++;
        final s = _sessionFromRRule(props);
        if (s != null) sessions.add(s);
      } else {
        nonRrule.add(props);
      }
    }
    debugPrint('[IcalParser] dateOnly=$dateOnly withTime=$withTime withRrule=$withRrule');

    // 2차: RRULE이 하나도 없으면 개별 VEVENT 그룹핑으로 추론
    if (sessions.isEmpty && nonRrule.isNotEmpty) {
      final inferred = _inferFromEvents(nonRrule);
      debugPrint('[IcalParser] 그룹핑 추론 세션=${inferred.length}');
      sessions.addAll(inferred);
    }

    return sessions;
  }

  // ─── VEVENT 블록 추출 ────────────────────────────────────────────

  static List<String> _extractVEventBlocks(String text) {
    final blocks = <String>[];
    final re = RegExp(r'BEGIN:VEVENT([\s\S]*?)END:VEVENT');
    for (final m in re.allMatches(text)) {
      blocks.add(m.group(1)!);
    }
    return blocks;
  }

  // ─── 프로퍼티 파싱 ───────────────────────────────────────────────

  static Map<String, _Prop> _parseProps(String block) {
    final props = <String, _Prop>{};
    for (final line in block.split(RegExp(r'\r?\n'))) {
      final ci = line.indexOf(':');
      if (ci < 0) continue;
      final keyPart = line.substring(0, ci); // e.g. "DTSTART;TZID=Asia/Seoul"
      final value = line.substring(ci + 1).trim();
      if (value.isEmpty) continue;
      final key = keyPart.split(';')[0].toUpperCase();
      // 첫 번째 값만 저장 (중복 프로퍼티는 무시)
      props.putIfAbsent(key, () => _Prop(value: value, raw: line));
    }
    return props;
  }

  // ─── RRULE 방식 파싱 ─────────────────────────────────────────────

  static ClassSession? _sessionFromRRule(Map<String, _Prop> props) {
    final rrule = props['RRULE']?.value;
    if (rrule == null) return null;

    final start = _parseDt(props, 'DTSTART');
    if (start == null) return null;

    List<String> weekdays;
    final bydayM = RegExp(r'BYDAY=([^;]+)').firstMatch(rrule);
    if (bydayM != null) {
      // "1MO" 같은 접두 숫자 제거 후 두 글자 코드만 추출
      weekdays = bydayM
          .group(1)!
          .split(',')
          .map((s) => s.trim().replaceAll(RegExp(r'^\d+'), '').toUpperCase())
          .where((s) => s.length == 2)
          .toList();
    } else {
      // BYDAY 없으면 DTSTART 요일로 폴백
      const names = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
      weekdays = [names[start.weekday % 7]];
    }

    if (weekdays.isEmpty) return null;

    final end = _parseDt(props, 'DTEND');
    final endTime = end != null
        ? _hm(end)
        : _hm(start.add(const Duration(hours: 1)));

    return ClassSession(
      uid: props['UID']?.value ?? '${props["SUMMARY"]?.value}-rrule',
      summary: _cleanSummary(props['SUMMARY']?.value ?? ''),
      location: props['LOCATION']?.value ?? '',
      startTime: _hm(start),
      endTime: endTime,
      weekdays: weekdays,
    );
  }

  // ─── 개별 VEVENT 그룹핑으로 수업 추론 ──────────────────────────

  static List<ClassSession> _inferFromEvents(
      List<Map<String, _Prop>> allProps) {
    // 그룹 키: "SUMMARY|startHH:MM|endHH:MM"
    // 각 키에 등장한 날짜(DateTime) 목록 보관
    final groups = <String, _Group>{};

    for (final props in allProps) {
      final raw = props['SUMMARY']?.value ?? '';
      final summary = _cleanSummary(raw);
      if (summary.isEmpty) continue;

      final start = _parseDt(props, 'DTSTART');
      if (start == null) continue;

      final end = _parseDt(props, 'DTEND');
      final startHM = _hm(start);
      final endHM = end != null ? _hm(end) : '';

      // VALUE=DATE 이벤트(과제 마감 등)는 시간이 00:00:00인 경우가 많음
      // 시간 정보가 있는 이벤트만 처리
      if (end == null && startHM == '00:00') continue;

      final key = '$summary|$startHM|$endHM';
      groups.putIfAbsent(
        key,
        () => _Group(
          summary: summary,
          location: props['LOCATION']?.value ?? '',
          startTime: startHM,
          endTime: endHM,
        ),
      ).dates.add(start);
    }

    const weekdayNames = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
    const weekdays = {'MO', 'TU', 'WE', 'TH', 'FR'};

    final sessions = <ClassSession>[];

    debugPrint('[IcalParser] 그룹 수=${groups.length}');
    // 샘플 5개 출력
    var count = 0;
    for (final e in groups.entries) {
      if (count++ >= 5) break;
      debugPrint('[IcalParser]  그룹: "${e.value.summary}" '
          '${e.value.startTime}~${e.value.endTime} '
          '발생=${e.value.dates.length}회');
    }

    for (final entry in groups.entries) {
      final g = entry.value;
      // 3회 미만은 수업이 아닌 것으로 간주
      if (g.dates.length < 3) continue;

      final wds = g.dates
          .map((d) => weekdayNames[d.weekday % 7])
          .where(weekdays.contains)
          .toSet()
          .toList()
        ..sort();

      if (wds.isEmpty) continue; // 주말만 있는 이벤트 제외

      sessions.add(ClassSession(
        uid: entry.key,
        summary: g.summary,
        location: g.location,
        startTime: g.startTime,
        endTime: g.endTime,
        weekdays: wds,
      ));
    }

    return sessions;
  }

  // ─── 날짜시간 파싱 ───────────────────────────────────────────────

  /// DTSTART / DTEND 프로퍼티를 KST DateTime으로 파싱
  static DateTime? _parseDt(Map<String, _Prop> props, String key) {
    final prop = props[key];
    if (prop == null) return null;
    return _parseDtStr(prop.value, prop.raw);
  }

  static DateTime? _parseDtStr(String value, String raw) {
    // DATE only 이벤트 건너뜀 (VALUE=DATE 또는 T 없음)
    if (raw.contains('VALUE=DATE') || !value.contains('T')) return null;

    final m = RegExp(
            r'(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)')
        .firstMatch(value);
    if (m == null) return null;

    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final h = int.parse(m.group(4)!);
    final mi = int.parse(m.group(5)!);
    final s = int.parse(m.group(6)!);
    final isUtc = m.group(7) == 'Z';

    if (isUtc) {
      // UTC → KST (+9h)
      return DateTime.utc(y, mo, d, h, mi, s).add(const Duration(hours: 9));
    }
    // TZID=Asia/Seoul 또는 타임존 미지정 → KST로 취급
    return DateTime(y, mo, d, h, mi, s);
  }

  // ─── 유틸 ────────────────────────────────────────────────────────

  static String _hm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Canvas iCal SUMMARY에 붙는 "[CourseCode]" 접미사 제거
  static String _cleanSummary(String s) {
    return s.replaceAll(RegExp(r'\s*\[[^\]]*\]\s*$'), '').trim();
  }
}

// ─── 내부 헬퍼 클래스 ───────────────────────────────────────────────

class _Prop {
  final String value;
  final String raw;
  const _Prop({required this.value, required this.raw});
}

class _Group {
  final String summary;
  final String location;
  final String startTime;
  final String endTime;
  final List<DateTime> dates = [];

  _Group({
    required this.summary,
    required this.location,
    required this.startTime,
    required this.endTime,
  });
}
