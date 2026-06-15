import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sharap/features/opportunities/data/prefs_store.dart';
import 'package:sharap/features/opportunities/domain/user_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save and load prefs', () async {
    final store = OppPrefsStore();
    await store.save(const OppUserPrefs(interests: {'디자인', 'IT/개발'}, region: '서울'));
    final p = await store.load();
    expect(p.interests, containsAll({'디자인', 'IT/개발'}));
    expect(p.region, '서울');
  });

  test('default is empty', () async {
    final p = await OppPrefsStore().load();
    expect(p.interests, isEmpty);
    expect(p.region, isNull);
  });

  test('clearing region removes it', () async {
    final store = OppPrefsStore();
    await store.save(const OppUserPrefs(interests: {'기획'}, region: '부산'));
    await store.save(const OppUserPrefs(interests: {'기획'}, region: null));
    expect((await store.load()).region, isNull);
  });
}
