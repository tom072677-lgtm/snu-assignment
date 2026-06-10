import 'package:flutter_test/flutter_test.dart';
import 'package:sharap/features/clubs/domain/club.dart';

void main() {
  group('Club.fromJson', () {
    test('파싱: 모든 필드', () {
      final c = Club.fromJson({
        'id': 'central_009',
        'name': 'SNUDA',
        'tier': 'central',
        'category': '학술',
        'colleges': [],
        'activity': '영어 토론',
        'registration': '정',
      });
      expect(c.id, 'central_009');
      expect(c.name, 'SNUDA');
      expect(c.tier, kTierCentral);
      expect(c.category, '학술');
      expect(c.activity, '영어 토론');
      expect(c.registration, '정');
      expect(c.colleges, isEmpty);
    });

    test('알 수 없는 category → 기타 fallback', () {
      final c = Club.fromJson({
        'id': 'x',
        'name': 'X',
        'tier': 'college',
        'category': '존재하지않는분류',
        'colleges': ['engineering'],
      });
      expect(c.category, '기타');
    });

    test('registration 누락 → null, activity 누락 → 빈 문자열', () {
      final c = Club.fromJson({
        'id': 'y',
        'name': 'Y',
        'tier': 'college',
        'category': '운동',
        'colleges': ['business'],
      });
      expect(c.registration, isNull);
      expect(c.activity, '');
    });
  });

  group('eligibilityLabels', () {
    test('central → [중앙]', () {
      const c = Club(id: 'a', name: 'A', tier: kTierCentral, category: '학술');
      expect(c.eligibilityLabels, ['중앙']);
    });

    test('dorm → [기숙사]', () {
      const c = Club(id: 'b', name: 'B', tier: kTierDorm, category: '취미');
      expect(c.eligibilityLabels, ['기숙사']);
    });

    test('college → 단과대 한글 이름들 (다중 단과대 포함)', () {
      const c = Club(
        id: 'c',
        name: 'C',
        tier: kTierCollege,
        category: '음악·공연',
        colleges: ['nursing', 'medicine'],
      );
      expect(c.eligibilityLabels, ['간호대학', '의과대학']);
    });
  });

  test('collegeNameFromCode: 미지 코드는 그대로 반환', () {
    expect(collegeNameFromCode('engineering'), '공과대학');
    expect(collegeNameFromCode('unknown_code'), 'unknown_code');
  });
}
