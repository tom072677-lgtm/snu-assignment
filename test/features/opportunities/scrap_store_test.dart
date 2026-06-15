import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sharap/features/opportunities/data/scrap_store.dart';
import 'package:sharap/features/opportunities/domain/scrap_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add, read, update status, remove', () async {
    final store = ScrapStore();
    await store.add(ScrapEntry(
        id: 'a',
        title: 't',
        deadline: DateTime(2026, 7, 20),
        status: ScrapStatus.interested));
    expect((await store.all()).map((e) => e.id), ['a']);

    await store.setStatus('a', ScrapStatus.applied);
    expect((await store.all()).first.status, ScrapStatus.applied);

    await store.remove('a');
    expect(await store.all(), isEmpty);
  });

  test('no duplicate on re-add', () async {
    final store = ScrapStore();
    const e = ScrapEntry(
        id: 'x', title: 't', deadline: null, status: ScrapStatus.interested);
    await store.add(e);
    await store.add(e);
    expect((await store.all()).length, 1);
  });

  test('survives reload (persisted json)', () async {
    await ScrapStore().add(const ScrapEntry(
        id: 'x', title: 't', deadline: null, status: ScrapStatus.interested));
    final reloaded = await ScrapStore().all();
    expect(reloaded.single.id, 'x');
  });
}
