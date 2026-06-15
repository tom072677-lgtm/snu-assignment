import 'package:flutter_test/flutter_test.dart';
import 'package:sharap/features/opportunities/domain/opportunity.dart';

void main() {
  test('fromJson maps core + extra fields', () {
    final o = Opportunity.fromJson({
      'id': 'x1',
      'category': 'scholarship',
      'title': '푸른등대 기부장학금',
      'organization': '한국장학재단',
      'url': 'https://kosaf.go.kr',
      'source': 'data.go.kr',
      'deadline': '2026-07-18',
      'region': '서울',
      'tags': ['생활비', '중복가능'],
      'extra': {'amount': '100~500만원', 'eligibility': '8구간 이하'},
    });
    expect(o.category, OppCategory.scholarship);
    expect(o.deadline, DateTime(2026, 7, 18));
    expect(o.extra['amount'], '100~500만원');
    expect(o.tags, contains('생활비'));
  });

  test('fromJson tolerates missing optional fields', () {
    final o = Opportunity.fromJson({
      'id': 'x2',
      'category': 'contest',
      'title': 't',
      'organization': 'org',
      'url': 'u',
      'source': 's',
    });
    expect(o.deadline, isNull);
    expect(o.region, isNull);
    expect(o.tags, isEmpty);
    expect(o.extra, isEmpty);
  });

  test('unknown category falls back to contest', () {
    final o = Opportunity.fromJson({
      'id': 'x3',
      'category': 'NONSENSE',
      'title': 't',
      'organization': 'o',
      'url': 'u',
      'source': 's',
    });
    expect(o.category, OppCategory.contest);
  });

  test('invalid deadline string becomes null (not crash)', () {
    final o = Opportunity.fromJson({
      'id': 'x4',
      'category': 'contest',
      'title': 't',
      'organization': 'o',
      'url': 'u',
      'source': 's',
      'deadline': 'not-a-date',
    });
    expect(o.deadline, isNull);
  });
}
