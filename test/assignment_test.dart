import 'package:flutter_test/flutter_test.dart';
import 'package:sharap/features/assignments/domain/assignment.dart';

Assignment _make({
  required DateTime dueDate,
  bool dateOnly = false,
  String url = 'https://etl.snu.ac.kr/courses/123/assignments/456',
}) =>
    Assignment(
      etlId: 'test-id',
      title: 'Test Assignment',
      courseName: 'Test Course',
      dueDate: dueDate,
      dateOnly: dateOnly,
      url: url,
    );

void main() {
  group('Assignment.isOverdue', () {
    test('returns true when past due (non-dateOnly)', () {
      final a = _make(dueDate: DateTime.now().subtract(const Duration(hours: 1)));
      expect(a.isOverdue, isTrue);
    });

    test('returns false when not yet due (non-dateOnly)', () {
      final a = _make(dueDate: DateTime.now().add(const Duration(hours: 1)));
      expect(a.isOverdue, isFalse);
    });

    test('dateOnly: returns false on same day before midnight', () {
      final today = DateTime.now();
      final a = _make(
        dueDate: DateTime(today.year, today.month, today.day),
        dateOnly: true,
      );
      expect(a.isOverdue, isFalse);
    });

    test('dateOnly: returns true the day after', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final a = _make(
        dueDate: DateTime(yesterday.year, yesterday.month, yesterday.day),
        dateOnly: true,
      );
      expect(a.isOverdue, isTrue);
    });
  });

  group('Assignment.isUrgent', () {
    test('returns true when due within 24 hours and not overdue', () {
      final a = _make(dueDate: DateTime.now().add(const Duration(hours: 12)));
      expect(a.isUrgent, isTrue);
    });

    test('returns false when due in more than 24 hours', () {
      final a = _make(dueDate: DateTime.now().add(const Duration(hours: 25)));
      expect(a.isUrgent, isFalse);
    });

    test('returns false when already overdue', () {
      final a = _make(dueDate: DateTime.now().subtract(const Duration(hours: 1)));
      expect(a.isUrgent, isFalse);
    });
  });

  group('Assignment.dDayNumber', () {
    test('returns positive days for future assignments', () {
      final a = _make(dueDate: DateTime.now().add(const Duration(days: 3)));
      expect(a.dDayNumber, greaterThanOrEqualTo(2));
    });

    test('returns negative days for past assignments', () {
      final a = _make(dueDate: DateTime.now().subtract(const Duration(days: 2)));
      expect(a.dDayNumber, lessThan(0));
    });
  });

  group('Assignment.effectiveCourseId / effectiveAssignmentId', () {
    test('extracts ids from URL when not provided explicitly', () {
      final a = _make(
        dueDate: DateTime.now().add(const Duration(days: 1)),
        url: 'https://etl.snu.ac.kr/courses/999/assignments/888',
      );
      expect(a.effectiveCourseId, '999');
      expect(a.effectiveAssignmentId, '888');
    });

    test('prefers explicit ids over URL extraction', () {
      final a = Assignment(
        etlId: 'id',
        title: 'T',
        courseName: 'C',
        dueDate: DateTime.now().add(const Duration(days: 1)),
        dateOnly: false,
        url: 'https://etl.snu.ac.kr/courses/999/assignments/888',
        courseId: 'explicit-course',
        assignmentId: 'explicit-assignment',
      );
      expect(a.effectiveCourseId, 'explicit-course');
      expect(a.effectiveAssignmentId, 'explicit-assignment');
    });

    test('returns null for URL with no ids', () {
      final a = _make(
        dueDate: DateTime.now().add(const Duration(days: 1)),
        url: 'https://etl.snu.ac.kr',
      );
      expect(a.effectiveCourseId, isNull);
      expect(a.effectiveAssignmentId, isNull);
    });

    test('hasDetail is false when ids cannot be resolved', () {
      final a = _make(
        dueDate: DateTime.now().add(const Duration(days: 1)),
        url: 'https://etl.snu.ac.kr',
      );
      expect(a.hasDetail, isFalse);
    });
  });

  group('Assignment.fromJson', () {
    test('parses valid json correctly', () {
      final a = Assignment.fromJson({
        'etlId': 'e1',
        'title': 'HW1',
        'courseName': 'Physics',
        'dueDate': '2030-01-15T23:59:00.000Z',
        'dateOnly': false,
        'url': 'https://etl.snu.ac.kr/courses/1/assignments/2',
      });
      expect(a.etlId, 'e1');
      expect(a.title, 'HW1');
      expect(a.courseName, 'Physics');
      expect(a.dateOnly, isFalse);
    });

    test('uses defaults for missing optional fields', () {
      final a = Assignment.fromJson({
        'etlId': 'e2',
        'title': 'HW2',
        'dueDate': '2030-01-15T23:59:00.000Z',
      });
      expect(a.courseName, '');
      expect(a.url, '');
      expect(a.dateOnly, isFalse);
    });
  });
}
