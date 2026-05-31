import 'package:flutter_test/flutter_test.dart';
import 'package:sharap/features/partner/domain/partner_restaurant.dart';

PartnerRestaurant _make({
  DateTime? expiresAt,
  List<String> colleges = const [],
  List<String> departments = const [],
}) =>
    PartnerRestaurant(
      id: 'test',
      name: '테스트 식당',
      address: '관악구',
      category: '음식점',
      benefit: '10% 할인',
      expiresAt: expiresAt,
      colleges: colleges,
      departments: departments,
    );

void main() {
  group('PartnerRestaurant.isExpired', () {
    test('returns false when expiresAt is null (permanent benefit)', () {
      expect(_make(expiresAt: null).isExpired, isFalse);
    });

    test('returns false when expiresAt is today (valid until end of day)', () {
      final today = DateTime.now();
      final r = _make(expiresAt: DateTime(today.year, today.month, today.day));
      expect(r.isExpired, isFalse);
    });

    test('returns true when expiresAt was yesterday', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final r = _make(
          expiresAt: DateTime(yesterday.year, yesterday.month, yesterday.day));
      expect(r.isExpired, isTrue);
    });

    test('returns false when expiresAt is tomorrow', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final r = _make(
          expiresAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day));
      expect(r.isExpired, isFalse);
    });
  });

  group('PartnerRestaurant.daysUntilExpiry', () {
    test('returns null when expiresAt is null', () {
      expect(_make(expiresAt: null).daysUntilExpiry, isNull);
    });

    test('returns 0 when expiresAt is today', () {
      final today = DateTime.now();
      final r = _make(expiresAt: DateTime(today.year, today.month, today.day));
      expect(r.daysUntilExpiry, 0);
    });

    test('returns 1 when expiresAt is tomorrow', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final r = _make(
          expiresAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day));
      expect(r.daysUntilExpiry, 1);
    });

    test('returns -1 when expiresAt was yesterday', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final r = _make(
          expiresAt: DateTime(yesterday.year, yesterday.month, yesterday.day));
      expect(r.daysUntilExpiry, -1);
    });
  });

  group('PartnerRestaurant.matchesUser', () {
    test('matches everyone when both lists are empty', () {
      final r = _make(colleges: [], departments: []);
      expect(r.matchesUser(collegeCode: null, deptCode: null), isTrue);
      expect(r.matchesUser(collegeCode: 'ENG', deptCode: 'CS'), isTrue);
    });

    test('matches by college code', () {
      final r = _make(colleges: ['ENG', 'SCI'], departments: []);
      expect(r.matchesUser(collegeCode: 'ENG', deptCode: null), isTrue);
      expect(r.matchesUser(collegeCode: 'LAW', deptCode: null), isFalse);
    });

    test('matches by department code', () {
      final r = _make(colleges: [], departments: ['CS', 'EE']);
      expect(r.matchesUser(collegeCode: null, deptCode: 'CS'), isTrue);
      expect(r.matchesUser(collegeCode: null, deptCode: 'MATH'), isFalse);
    });

    test('matches if either college or department matches', () {
      final r = _make(colleges: ['ENG'], departments: ['MATH']);
      expect(r.matchesUser(collegeCode: 'ENG', deptCode: 'MATH'), isTrue);
      expect(r.matchesUser(collegeCode: 'SCI', deptCode: 'MATH'), isTrue);
      expect(r.matchesUser(collegeCode: 'ENG', deptCode: 'CS'), isTrue);
    });

    test('does not match when both codes are null and lists are non-empty', () {
      final r = _make(colleges: ['ENG'], departments: ['CS']);
      expect(r.matchesUser(collegeCode: null, deptCode: null), isFalse);
    });

    test('does not match when neither code is in the lists', () {
      final r = _make(colleges: ['ENG'], departments: ['CS']);
      expect(r.matchesUser(collegeCode: 'LAW', deptCode: 'MATH'), isFalse);
    });
  });

  group('PartnerRestaurant.fromJson', () {
    test('parses full json correctly', () {
      final r = PartnerRestaurant.fromJson({
        'id': 'r1',
        'name': '맛집',
        'address': '서울시',
        'category': '카페',
        'benefit': '5% 할인',
        'colleges': ['ENG'],
        'departments': ['CS'],
        'expiresAt': '2030-12-31',
        'couponCode': 'ABC123',
      });
      expect(r.id, 'r1');
      expect(r.colleges, ['ENG']);
      expect(r.couponCode, 'ABC123');
      expect(r.expiresAt, isNotNull);
    });

    test('uses defaults for missing optional fields', () {
      final r = PartnerRestaurant.fromJson({
        'id': 'r2',
        'name': '식당',
      });
      expect(r.address, '');
      expect(r.category, '기타');
      expect(r.colleges, isEmpty);
      expect(r.expiresAt, isNull);
      expect(r.couponCode, isNull);
    });
  });
}
