import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/opportunity_repository.dart';
import '../data/scrap_store.dart';
import '../data/prefs_store.dart';
import '../domain/opportunity.dart';
import '../domain/scrap_entry.dart';
import '../domain/user_prefs.dart';

final opportunityRepositoryProvider =
    Provider<OpportunityRepository>((ref) => FixtureOpportunityRepository());

final scrapStoreProvider = Provider<ScrapStore>((ref) => ScrapStore());
final prefsStoreProvider = Provider<OppPrefsStore>((ref) => OppPrefsStore());

final allOpportunitiesProvider = FutureProvider<List<Opportunity>>(
    (ref) => ref.watch(opportunityRepositoryProvider).fetchAll());

final userPrefsProvider = FutureProvider<OppUserPrefs>(
    (ref) => ref.watch(prefsStoreProvider).load());

/// 카테고리 필터(null=전체) · 검색어.
final selectedCategoryProvider = StateProvider<OppCategory?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');

/// 스크랩 상태 단일 소스(Codex 리뷰 반영: 카드별 로컬 state 금지).
/// 목록·상세·내스크랩이 모두 이 provider를 구독해 즉시 동기화된다.
class ScrapsNotifier extends StateNotifier<List<ScrapEntry>> {
  final ScrapStore store;
  ScrapsNotifier(this.store) : super(const []) {
    _load();
  }

  Future<void> _load() async {
    state = await store.all();
  }

  bool isScrapped(String id) => state.any((e) => e.id == id);

  Future<void> add(ScrapEntry e) async {
    await store.add(e);
    state = await store.all();
  }

  Future<void> remove(String id) async {
    await store.remove(id);
    state = await store.all();
  }

  Future<void> setStatus(String id, ScrapStatus s) async {
    await store.setStatus(id, s);
    state = await store.all();
  }
}

final scrapsProvider =
    StateNotifierProvider<ScrapsNotifier, List<ScrapEntry>>(
        (ref) => ScrapsNotifier(ref.watch(scrapStoreProvider)));
