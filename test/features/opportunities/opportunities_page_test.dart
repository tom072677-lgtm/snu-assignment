import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sharap/features/opportunities/data/opportunity_repository.dart';
import 'package:sharap/features/opportunities/presentation/opportunities_providers.dart';
import 'package:sharap/features/opportunities/presentation/opportunity_card.dart';
import 'package:sharap/features/opportunities/presentation/opportunities_page.dart';

const _json = '''
[
  {"id":"uth2","category":"contest","title":"제2회 유쓰 쇼츠 페스티벌","organization":"LG유플러스","url":"https://x","source":"s","deadline":"2999-07-31","tags":["영상/콘텐츠"],"extra":{"prize":"LA 연수"}},
  {"id":"sch","category":"scholarship","title":"푸른등대 장학금","organization":"한국장학재단","url":"https://y","source":"s","deadline":"2999-07-18","extra":{"amount":"500만원"}}
]
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders cards and toggles scrap via shared provider',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        opportunityRepositoryProvider.overrideWithValue(
            FixtureOpportunityRepository(loadAsset: (_) async => _json)),
      ],
      child: const MaterialApp(home: OpportunitiesPage()),
    ));
    await tester.pumpAndSettle();

    // 카드가 렌더된다
    expect(find.text('제2회 유쓰 쇼츠 페스티벌'), findsOneWidget);
    expect(find.byType(OpportunityCard), findsNWidgets(2));

    // 스크랩 토글 → 상태 provider 반영(별 아이콘이 채워짐)
    final star = find.descendant(
        of: find.byType(OpportunityCard).first,
        matching: find.byIcon(Icons.star_border));
    expect(star, findsOneWidget);
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(OpportunityCard).first,
            matching: find.byIcon(Icons.star)),
        findsOneWidget);
  });
}
