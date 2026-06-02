import 'package:flutter_test/flutter_test.dart';
import 'package:sharap/features/timetable/data/ical_session_parser.dart';

// Minimal valid iCal wrapper
String _ical(String vevent) => '''BEGIN:VCALENDAR
VERSION:2.0
$vevent
END:VCALENDAR''';

String _rruleEvent({
  required String summary,
  required String dtstart,
  required String dtend,
  required String byday,
  String uid = 'test-uid',
  String location = '301동 101호',
}) =>
    '''BEGIN:VEVENT
UID:$uid
SUMMARY:$summary
DTSTART;TZID=Asia/Seoul:$dtstart
DTEND;TZID=Asia/Seoul:$dtend
RRULE:FREQ=WEEKLY;BYDAY=$byday;UNTIL=20251220T150000Z
LOCATION:$location
END:VEVENT''';

// Generates N weekly occurrences starting from a Monday
List<String> _weeklyEvents({
  required String summary,
  required String startTime,
  required String endTime,
  int count = 4,
}) {
  final events = <String>[];
  // Start from 2025-03-03 (Monday)
  var date = DateTime(2025, 3, 3);
  for (var i = 0; i < count; i++) {
    final ds = '${date.year}${date.month.toString().padLeft(2,'0')}${date.day.toString().padLeft(2,'0')}T${startTime}00';
    final de = '${date.year}${date.month.toString().padLeft(2,'0')}${date.day.toString().padLeft(2,'0')}T${endTime}00';
    events.add('''BEGIN:VEVENT
UID:uid-$i
SUMMARY:$summary
DTSTART;TZID=Asia/Seoul:$ds
DTEND;TZID=Asia/Seoul:$de
LOCATION:302동
END:VEVENT''');
    date = date.add(const Duration(days: 7));
  }
  return events;
}

void main() {
  group('IcalSessionParser - RRULE method', () {
    test('parses single RRULE event correctly', () {
      final ics = _ical(_rruleEvent(
        summary: '일반물리학 [PHYS101]',
        dtstart: '20250303T090000',
        dtend: '20250303T103000',
        byday: 'MO,WE',
        location: '500동 101호',
      ));

      final sessions = IcalSessionParser.parse(ics);
      expect(sessions.length, 1);
      expect(sessions[0].summary, '일반물리학');
      expect(sessions[0].weekdays, containsAll(['MO', 'WE']));
      expect(sessions[0].startTime, '09:00');
      expect(sessions[0].endTime, '10:30');
      expect(sessions[0].location, '500동 101호');
    });

    test('strips [CourseCode] suffix from summary', () {
      final ics = _ical(_rruleEvent(
        summary: '컴퓨터공학개론 [CSE001-01]',
        dtstart: '20250303T130000',
        dtend: '20250303T150000',
        byday: 'TU,TH',
      ));
      final sessions = IcalSessionParser.parse(ics);
      expect(sessions[0].summary, '컴퓨터공학개론');
    });

    test('falls back to DTSTART weekday when BYDAY is absent', () {
      final ics = _ical('''BEGIN:VEVENT
UID:no-byday
SUMMARY:체육 [PE001]
DTSTART;TZID=Asia/Seoul:20250305T100000
DTEND;TZID=Asia/Seoul:20250305T120000
RRULE:FREQ=WEEKLY;COUNT=15
END:VEVENT''');
      // 2025-03-05 is a Wednesday
      final sessions = IcalSessionParser.parse(ics);
      expect(sessions.length, 1);
      expect(sessions[0].weekdays, contains('WE'));
    });

    test('converts UTC time to KST (+9h)', () {
      final ics = _ical('''BEGIN:VEVENT
UID:utc-test
SUMMARY:수업 [T001]
DTSTART:20250303T000000Z
DTEND:20250303T013000Z
RRULE:FREQ=WEEKLY;BYDAY=MO
END:VEVENT''');
      final sessions = IcalSessionParser.parse(ics);
      expect(sessions.length, 1);
      expect(sessions[0].startTime, '09:00');
      expect(sessions[0].endTime, '10:30');
    });

    test('parses multiple RRULE events', () {
      final event1 = _rruleEvent(
        summary: '수업A [A01]',
        dtstart: '20250303T090000',
        dtend: '20250303T103000',
        byday: 'MO',
        uid: 'uid-a',
      );
      final event2 = _rruleEvent(
        summary: '수업B [B01]',
        dtstart: '20250304T140000',
        dtend: '20250304T153000',
        byday: 'TU,TH',
        uid: 'uid-b',
      );
      final ics = _ical('$event1\n$event2');
      final sessions = IcalSessionParser.parse(ics);
      expect(sessions.length, 2);
    });
  });

  group('IcalSessionParser - grouping method (no RRULE)', () {
    test('infers session from 4 weekly occurrences', () {
      final events = _weeklyEvents(
        summary: '데이터구조 [CS201]',
        startTime: '100000',
        endTime: '113000',
        count: 4,
      );
      final ics = _ical(events.join('\n'));
      final sessions = IcalSessionParser.parse(ics);
      expect(sessions.length, 1);
      expect(sessions[0].summary, '데이터구조');
      expect(sessions[0].weekdays, contains('MO'));
    });

    test('ignores events with fewer than 3 occurrences', () {
      final events = _weeklyEvents(
        summary: '특강 [SP001]',
        startTime: '140000',
        endTime: '153000',
        count: 2,
      );
      final ics = _ical(events.join('\n'));
      final sessions = IcalSessionParser.parse(ics);
      expect(sessions, isEmpty);
    });

    test('does not infer session from weekend-only events', () {
      final events = <String>[];
      var date = DateTime(2025, 3, 1); // Saturday
      for (var i = 0; i < 4; i++) {
        final y = date.year;
        final mo = date.month.toString().padLeft(2, '0');
        final d = date.day.toString().padLeft(2, '0');
        events.add('''BEGIN:VEVENT
UID:weekend-$i
SUMMARY:주말수업 [WE01]
DTSTART;TZID=Asia/Seoul:$y$mo${d}T100000
DTEND;TZID=Asia/Seoul:$y$mo${d}T113000
END:VEVENT''');
        date = date.add(const Duration(days: 7));
      }
      final ics = _ical(events.join('\n'));
      final sessions = IcalSessionParser.parse(ics);
      expect(sessions, isEmpty);
    });
  });

  group('IcalSessionParser - edge cases', () {
    test('returns empty list for empty iCal', () {
      final sessions = IcalSessionParser.parse('BEGIN:VCALENDAR\nEND:VCALENDAR');
      expect(sessions, isEmpty);
    });

    test('handles RFC 5545 line folding', () {
      // Long line folded with CRLF + SPACE
      const ics = 'BEGIN:VCALENDAR\nBEGIN:VEVENT\n'
          'SUMMARY:긴이름수업\r\n  연속 [CS999]\n'
          'DTSTART;TZID=Asia/Seoul:20250303T090000\n'
          'DTEND;TZID=Asia/Seoul:20250303T103000\n'
          'RRULE:FREQ=WEEKLY;BYDAY=MO\n'
          'UID:fold-test\n'
          'END:VEVENT\nEND:VCALENDAR';
      final sessions = IcalSessionParser.parse(ics);
      expect(sessions.length, 1);
    });

    test('skips DATE-only events (no time component)', () {
      final ics = _ical('''BEGIN:VEVENT
UID:dateonly
SUMMARY:과제마감 [HW01]
DTSTART;VALUE=DATE:20250310
DTEND;VALUE=DATE:20250311
END:VEVENT''');
      final sessions = IcalSessionParser.parse(ics);
      expect(sessions, isEmpty);
    });
  });
}
