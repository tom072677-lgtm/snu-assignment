import 'package:flutter_test/flutter_test.dart';
import 'package:sharap/features/opportunities/data/opportunity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FixtureOpportunityRepository parses injected json', () async {
    final repo = FixtureOpportunityRepository(
      loadAsset: (_) async =>
          '[{"id":"a","category":"contest","title":"t","organization":"o","url":"u","source":"s"}]',
    );
    final list = await repo.fetchAll();
    expect(list, hasLength(1));
    expect(list.first.id, 'a');
  });

  test('real asset fixture loads and is valid (catches pubspec/json errors)',
      () async {
    final repo = FixtureOpportunityRepository();
    final list = await repo.fetchAll();
    expect(list.length, greaterThanOrEqualTo(5));
    // 모든 항목이 필수 필드를 갖는지 가볍게 확인
    for (final o in list) {
      expect(o.id, isNotEmpty);
      expect(o.title, isNotEmpty);
    }
  });
}
