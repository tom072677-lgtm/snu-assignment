import 'package:flutter_test/flutter_test.dart';
import 'package:sharap/features/timetable/domain/semester.dart';

void main() {
  group('semesterKey', () {
    test('3~8월은 1학기', () {
      expect(semesterKey(DateTime(2026, 3, 1)), '2026-1');
      expect(semesterKey(DateTime(2026, 6, 10)), '2026-1');
      expect(semesterKey(DateTime(2026, 8, 31)), '2026-1');
    });

    test('9~12월은 2학기', () {
      expect(semesterKey(DateTime(2026, 9, 1)), '2026-2');
      expect(semesterKey(DateTime(2026, 12, 31)), '2026-2');
    });

    test('1~2월은 직전 연도 2학기', () {
      expect(semesterKey(DateTime(2027, 1, 15)), '2026-2');
      expect(semesterKey(DateTime(2027, 2, 28)), '2026-2');
    });

    test('연말/학기 경계 구분', () {
      expect(semesterKey(DateTime(2026, 8, 31)), '2026-1');
      expect(semesterKey(DateTime(2026, 9, 1)), '2026-2');
      expect(semesterKey(DateTime(2026, 12, 31)), '2026-2');
      expect(semesterKey(DateTime(2027, 1, 1)), '2026-2');
    });
  });

  group('isTimetableStale', () {
    final captured = DateTime(2026, 3, 5); // 2026-1학기에 캡처

    test('지난 학기 캡처면 stale', () {
      expect(
        isTimetableStale(
          hasSessions: true,
          capturedAt: captured,
          snoozedSemester: null,
          now: DateTime(2026, 9, 2), // 2026-2학기
        ),
        isTrue,
      );
    });

    test('같은 학기면 stale 아님', () {
      expect(
        isTimetableStale(
          hasSessions: true,
          capturedAt: captured,
          snoozedSemester: null,
          now: DateTime(2026, 6, 10), // 여전히 2026-1
        ),
        isFalse,
      );
    });

    test('capturedAt 없으면(기존 사용자) stale 아님', () {
      expect(
        isTimetableStale(
          hasSessions: true,
          capturedAt: null,
          snoozedSemester: null,
          now: DateTime(2026, 9, 2),
        ),
        isFalse,
      );
    });

    test('세션 없으면 stale 아님', () {
      expect(
        isTimetableStale(
          hasSessions: false,
          capturedAt: captured,
          snoozedSemester: null,
          now: DateTime(2026, 9, 2),
        ),
        isFalse,
      );
    });

    test('현재 학기를 스누즈했으면 stale 아님', () {
      expect(
        isTimetableStale(
          hasSessions: true,
          capturedAt: captured,
          snoozedSemester: '2026-2', // 새 학기를 스누즈
          now: DateTime(2026, 9, 2),
        ),
        isFalse,
      );
    });

    test('학기 경계: 8/31 캡처는 9/1에 stale', () {
      expect(
        isTimetableStale(
          hasSessions: true,
          capturedAt: DateTime(2026, 8, 31),
          snoozedSemester: null,
          now: DateTime(2026, 9, 1),
        ),
        isTrue,
      );
    });
  });
}
