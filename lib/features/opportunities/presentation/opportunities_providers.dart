import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/notification_service.dart';
import '../data/opportunity_repository.dart';
import '../data/server_opportunity_repository.dart';
import '../data/contest_scraper.dart';
import '../data/scrap_store.dart';
import '../data/prefs_store.dart';
import '../domain/opportunity.dart';
import '../domain/scrap_entry.dart';
import '../domain/user_prefs.dart';

// 실데이터: 서버 집계 API. (테스트는 이 provider를 Fixture로 override)
final opportunityRepositoryProvider =
    Provider<OpportunityRepository>((ref) => ServerOpportunityRepository());

final scrapStoreProvider = Provider<ScrapStore>((ref) => ScrapStore());
final prefsStoreProvider = Provider<OppPrefsStore>((ref) => OppPrefsStore());

// 공모전은 위비티가 클라우드 IP를 막아 서버에선 못 긁음 → 온디바이스(폰 IP)로 스크랩.
final contestScraperProvider = Provider<ContestScraper>((ref) => ContestScraper());

// 서버(장학·교육) + 온디바이스(공모전) 병합. 공모전 실패해도 서버 데이터는 그대로.
final allOpportunitiesProvider = FutureProvider<List<Opportunity>>((ref) async {
  final repo = ref.watch(opportunityRepositoryProvider);
  final scraper = ref.watch(contestScraperProvider);
  final results = await Future.wait<List<Opportunity>>([
    repo.fetchAll(),
    scraper.fetch().catchError((Object e) {
      debugPrint('[opportunities] 공모전 스크랩 실패: $e');
      return <Opportunity>[];
    }),
  ]);
  return [...results[0], ...results[1]];
});

final userPrefsProvider = FutureProvider<OppUserPrefs>(
    (ref) => ref.watch(prefsStoreProvider).load());

/// 카테고리 필터(null=전체) · 검색어.
final selectedCategoryProvider = StateProvider<OppCategory?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');

/// 지역 필터(null=전체). 사용자가 앱에서 직접 고르는 단일 권위 소스.
/// 전국(region=null) 항목은 OpportunityQuery에서 항상 노출됨.
final selectedRegionProvider = StateProvider<String?>((ref) => null);

/// 지역 선택 어휘 — 서버 regionFromZipCd가 내는 시·도 문자열과 정확히 일치해야 함.
const List<String> kRegionOptions = [
  '서울', '부산', '대구', '인천', '광주', '대전', '울산', '세종',
  '경기', '강원', '충북', '충남', '전북', '전남', '경북', '경남', '제주',
];

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

/// 스크랩 토글 + 마감 로컬 알림 예약/취소를 한 곳에서 처리(목록·상세 공용).
/// 알림은 기존 NotificationService 재사용. 알림 호출은 서비스 내부에서 try/catch됨.
Future<void> toggleScrapWithNotif(WidgetRef ref, Opportunity o) async {
  final notifier = ref.read(scrapsProvider.notifier);
  final notif = ref.read(notificationServiceProvider);
  if (notifier.isScrapped(o.id)) {
    await notifier.remove(o.id);
    await notif.cancelOpportunityDeadline(o.id);
  } else {
    await notifier.add(scrapEntryOf(o));
    if (o.deadline != null) {
      await notif.scheduleOpportunityDeadline(
          oppId: o.id, title: o.title, deadline: o.deadline!);
    }
  }
}
