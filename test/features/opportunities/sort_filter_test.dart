import 'package:flutter_test/flutter_test.dart';
import 'package:sharap/features/opportunities/domain/opportunity.dart';
import 'package:sharap/features/opportunities/domain/opportunity_query.dart';

Opportunity _o(String id, OppCategory c, DateTime? d,
        {List<String> tags = const [], String? region}) =>
    Opportunity(
      id: id,
      category: c,
      title: id,
      organization: 'o',
      url: 'u',
      source: 's',
      deadline: d,
      tags: tags,
      region: region,
    );

void main() {
  final now = DateTime(2026, 7, 1);

  test('removes past deadlines and sorts by nearest deadline', () {
    final list = [
      _o('past', OppCategory.contest, DateTime(2026, 6, 1)),
      _o('soon', OppCategory.contest, DateTime(2026, 7, 5)),
      _o('later', OppCategory.contest, DateTime(2026, 8, 1)),
      _o('nodate', OppCategory.contest, null),
    ];
    final r = OpportunityQuery.process(list, now: now);
    expect(r.map((e) => e.id).toList(), ['soon', 'later', 'nodate']);
  });

  test('keeps today as D-day (not removed)', () {
    final list = [_o('today', OppCategory.contest, DateTime(2026, 7, 1))];
    final r = OpportunityQuery.process(list, now: now);
    expect(r.map((e) => e.id).toList(), ['today']);
  });

  test('category filter (single)', () {
    final list = [
      _o('c', OppCategory.contest, DateTime(2026, 7, 5)),
      _o('s', OppCategory.scholarship, DateTime(2026, 7, 6)),
    ];
    final r = OpportunityQuery.process(list,
        now: now, categories: {OppCategory.scholarship});
    expect(r.map((e) => e.id).toList(), ['s']);
  });

  test('category filter (multi) keeps any selected', () {
    final list = [
      _o('c', OppCategory.contest, DateTime(2026, 7, 5)),
      _o('s', OppCategory.scholarship, DateTime(2026, 7, 6)),
      _o('i', OppCategory.intern, DateTime(2026, 7, 7)),
    ];
    final r = OpportunityQuery.process(list,
        now: now, categories: {OppCategory.contest, OppCategory.intern});
    expect(r.map((e) => e.id).toSet(), {'c', 'i'});
  });

  test('empty categories = 전체', () {
    final list = [
      _o('c', OppCategory.contest, DateTime(2026, 7, 5)),
      _o('s', OppCategory.scholarship, DateTime(2026, 7, 6)),
    ];
    final r = OpportunityQuery.process(list, now: now);
    expect(r.map((e) => e.id).toSet(), {'c', 's'});
  });

  test('region filter keeps nationwide(null) and matching region', () {
    final list = [
      _o('seoul', OppCategory.scholarship, DateTime(2026, 7, 5), region: '서울'),
      _o('busan', OppCategory.scholarship, DateTime(2026, 7, 6), region: '부산'),
      _o('nation', OppCategory.scholarship, DateTime(2026, 7, 7)),
    ];
    final r = OpportunityQuery.process(list, now: now, region: '서울');
    expect(r.map((e) => e.id).toSet(), {'seoul', 'nation'});
  });

  test('interest tags rank matching items higher', () {
    final list = [
      _o('plain', OppCategory.contest, DateTime(2026, 7, 10)),
      _o('match', OppCategory.contest, DateTime(2026, 7, 20), tags: ['디자인']),
    ];
    final r = OpportunityQuery.process(list, now: now, interests: {'디자인'});
    expect(r.first.id, 'match');
  });

  test('search query matches title/org/tags', () {
    final list = [
      _o('a', OppCategory.contest, DateTime(2026, 7, 10), tags: ['디자인']),
      _o('b', OppCategory.contest, DateTime(2026, 7, 11), tags: ['마케팅']),
    ];
    final r = OpportunityQuery.process(list, now: now, query: '디자인');
    expect(r.map((e) => e.id).toList(), ['a']);
  });
}
