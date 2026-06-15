# 혜택·기회 탭 — 앱 측(Plan A) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** sharap 앱에 "혜택·기회" 탭을 추가해, (서버 없이) 로컬 fixture 데이터로 5개 카테고리 기회를 마감순으로 보고, 스크랩·D-day 로컬 알림·개인화 필터·함정 안내를 동작시킨다.

**Architecture:** 기존 feature-first 구조(`lib/features/<name>/{data,domain,presentation}`)를 따른다. 데이터는 `OpportunityRepository` 인터페이스 뒤에 두고 Plan A에서는 **asset fixture 구현체**를 쓴다(Plan B에서 dio 서버 구현체로 교체). 스크랩·개인화·알림은 모두 기기 로컬(`shared_preferences`, `flutter_local_notifications`).

**Tech Stack:** Flutter, flutter_riverpod ^2.5.1, shared_preferences, flutter_local_notifications, url_launcher, intl. (모두 기존 pubspec에 존재 — 신규 의존성 없음)

**전제:** Plan B(서버)는 별도. 이 계획은 `assets/data/opportunities_sample.json` fixture만으로 완결 동작한다. 서버 연동 지점은 Task 4에서 인터페이스로 격리한다.

**기존 패턴 참고:** provider/repository 와이어링은 `lib/features/notices/`(가장 유사한 기능)의 스타일을 그대로 따른다. dio 사용 시 `lib/core/dio_client.dart` 재사용.

---

## Codex 리뷰 반영 (v2 수정사항)

2026-06-15 Codex 플랜 리뷰 후 아래를 반영해 구현한다(원 태스크 본문보다 우선):
1. **UI 생성 순서**: 카드 → 상세 → 내스크랩 → **메인 페이지(마지막)**. 메인이 import하는 페이지를 먼저 만들어 중간 빌드 깨짐 방지.
2. **스크랩 상태 단일화**: 카드별 로컬 state 제거 → Riverpod `scrapsProvider`(StateNotifier<List<ScrapEntry>>) 하나로 관리. 목록·상세·내스크랩이 모두 구독.
3. **알림은 마지막 독립 Phase**: 결정적 notif ID(`String.hashCode` 금지 — code unit fold 해시), Android 13+ 권한·timezone·채널을 main.dart 기존 알림 셋업과 연결, plugin provider는 throw 대신 override 주입.
4. **query 보강**: `process()`에 region 필터 추가(전국=region null은 항상 노출). 관심 태그는 온보딩 옵션과 **동일 어휘**(`kInterestOptions`)를 fixture 태그에도 사용해야 매칭됨.
5. **검색 입력창** 추가, **launchUrl 실패 가드** 추가, **widget smoke test** 추가.
6. **커밋 단위**: 태스크별 → **Phase별**(domain/data/ui/notif/integration)로 완화.
7. (반려) "인코딩 깨짐/JSON 깨짐"은 codex 파이프 전송 아티팩트 — 디스크 원문은 정상. "subagent skill 없음"도 이 환경엔 존재하므로 유지. 단 fixture는 실제 JSON 파싱으로 검증.

---

## 파일 구조 (생성/수정 대상)

```
lib/features/opportunities/
  domain/
    opportunity.dart            # Opportunity 모델 + OppCategory enum
    scrap_entry.dart            # 스크랩 항목(상태 포함)
    user_prefs.dart            # 개인화 설정(관심분야·지역)
    pitfall_content.dart        # 함정/체크리스트 정적 콘텐츠
  data/
    opportunity_repository.dart # 인터페이스 + Fixture 구현체
    scrap_store.dart            # shared_preferences 스크랩 저장
    prefs_store.dart            # shared_preferences 개인화 저장
    deadline_notifier.dart      # flutter_local_notifications 예약/취소
  presentation/
    opportunities_providers.dart
    opportunities_page.dart     # 혜택 탭 메인(칩+배너+리스트)
    opportunity_card.dart       # 컴팩트 카드 위젯(레이아웃 A)
    opportunity_detail_page.dart
    my_scraps_page.dart
assets/data/opportunities_sample.json   # fixture
test/features/opportunities/
  opportunity_test.dart
  scrap_store_test.dart
  prefs_store_test.dart
  repository_test.dart
  sort_filter_test.dart
```

수정:
- `pubspec.yaml` — (assets에 이미 `assets/data/` 포함됨, 확인만)
- `lib/app.dart` — 네비게이션에 혜택 탭 추가
- `lib/features/onboarding/...` — 관심분야·지역 스텝 추가

---

## Phase 1 — 도메인 모델

### Task 1: Opportunity 모델 + OppCategory

**Files:**
- Create: `lib/features/opportunities/domain/opportunity.dart`
- Test: `test/features/opportunities/opportunity_test.dart`

- [ ] **Step 1: 실패 테스트 작성**

```dart
// test/features/opportunities/opportunity_test.dart
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
      'id': 'x2', 'category': 'contest', 'title': 't',
      'organization': 'org', 'url': 'u', 'source': 's',
    });
    expect(o.deadline, isNull);
    expect(o.region, isNull);
    expect(o.tags, isEmpty);
    expect(o.extra, isEmpty);
  });

  test('unknown category falls back to contest', () {
    final o = Opportunity.fromJson({
      'id': 'x3', 'category': 'NONSENSE', 'title': 't',
      'organization': 'o', 'url': 'u', 'source': 's',
    });
    expect(o.category, OppCategory.contest);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/features/opportunities/opportunity_test.dart`
Expected: FAIL ("opportunity.dart" 없음 / 컴파일 에러)

- [ ] **Step 3: 모델 구현**

```dart
// lib/features/opportunities/domain/opportunity.dart
enum OppCategory { contest, activity, scholarship, education, intern }

OppCategory categoryFromString(String s) {
  switch (s) {
    case 'contest': return OppCategory.contest;
    case 'activity': return OppCategory.activity;
    case 'scholarship': return OppCategory.scholarship;
    case 'education': return OppCategory.education;
    case 'intern': return OppCategory.intern;
    default: return OppCategory.contest; // 안전한 폴백
  }
}

String categoryLabel(OppCategory c) {
  switch (c) {
    case OppCategory.contest: return '공모전';
    case OppCategory.activity: return '대외활동';
    case OppCategory.scholarship: return '장학금';
    case OppCategory.education: return '교육';
    case OppCategory.intern: return '인턴';
  }
}

class Opportunity {
  final String id;
  final OppCategory category;
  final String title;
  final String organization;
  final String url;
  final String source;
  final DateTime? deadline;
  final DateTime? startDate;
  final String? region;
  final List<String> tags;
  final String? summary;
  final Map<String, String> extra;

  const Opportunity({
    required this.id,
    required this.category,
    required this.title,
    required this.organization,
    required this.url,
    required this.source,
    this.deadline,
    this.startDate,
    this.region,
    this.tags = const [],
    this.summary,
    this.extra = const {},
  });

  static DateTime? _date(dynamic v) =>
      (v == null || v == '') ? null : DateTime.tryParse(v as String);

  factory Opportunity.fromJson(Map<String, dynamic> j) => Opportunity(
        id: j['id'] as String,
        category: categoryFromString(j['category'] as String? ?? ''),
        title: j['title'] as String,
        organization: j['organization'] as String? ?? '',
        url: j['url'] as String? ?? '',
        source: j['source'] as String? ?? '',
        deadline: _date(j['deadline']),
        startDate: _date(j['startDate']),
        region: j['region'] as String?,
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        summary: j['summary'] as String?,
        extra: (j['extra'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
      );
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/features/opportunities/opportunity_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: 커밋**

```bash
git add lib/features/opportunities/domain/opportunity.dart test/features/opportunities/opportunity_test.dart
git commit -m "feat(opportunities): add Opportunity model + OppCategory"
```

---

### Task 2: fixture JSON + 로더 자산

**Files:**
- Create: `assets/data/opportunities_sample.json`

- [ ] **Step 1: fixture 작성** (5개 카테고리 각 2건 이상, 실제 리서치 기반 예시)

```json
[
  {"id":"uth2","category":"contest","title":"제2회 유쓰 쇼츠 페스티벌","organization":"LG유플러스","url":"https://www.lguplus.com/uth","source":"sample","deadline":"2026-07-31","tags":["AI","쇼츠","영상"],"summary":"AI로 쇼츠 제작, 대상 LA 연수","extra":{"prize":"LA 5박7일 연수 + 상금","target":"누구나","field":"영상/AI"}},
  {"id":"sch_blue","category":"scholarship","title":"푸른등대 기부장학금","organization":"한국장학재단","url":"https://www.kosaf.go.kr","source":"sample","deadline":"2026-07-18","region":"전국","tags":["생활비","중복가능"],"extra":{"amount":"100~500만원","eligibility":"8구간 이하"}},
  {"id":"edu_ssafy","category":"education","title":"SSAFY 16기 모집","organization":"삼성","url":"https://www.ssafy.com","source":"sample","deadline":"2026-08-12","tags":["SW","부트캠프"],"extra":{"period":"1년","cost":"무료 + 월 140만원","capacity":"제한"}},
  {"id":"act_supporters","category":"activity","title":"○○ 서포터즈 3기","organization":"△△재단","url":"https://example.org","source":"sample","deadline":"2026-08-05","tags":["서포터즈","마케팅"],"extra":{"prize":"활동비 + 수료증","target":"대학생"}},
  {"id":"intern_alio","category":"intern","title":"공공기관 체험형 청년인턴","organization":"○○공사","url":"https://www.alio.go.kr","source":"sample","deadline":"2026-07-25","region":"세종","tags":["공공","인턴"],"extra":{"pay":"월 약 215만원","term":"3개월"}}
]
```

- [ ] **Step 2: pubspec 자산 확인**

Run: `grep -n "assets/data/" pubspec.yaml`
Expected: `assets/data/` 라인 존재(이미 있음). 없으면 `flutter:` > `assets:`에 `- assets/data/` 추가 후 `flutter pub get`.

- [ ] **Step 3: 커밋**

```bash
git add assets/data/opportunities_sample.json
git commit -m "feat(opportunities): add sample fixture data"
```

---

## Phase 2 — 저장소 / 로컬 상태

### Task 3: OpportunityRepository (인터페이스 + Fixture 구현)

**Files:**
- Create: `lib/features/opportunities/data/opportunity_repository.dart`
- Test: `test/features/opportunities/repository_test.dart`

- [ ] **Step 1: 실패 테스트**

```dart
// test/features/opportunities/repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sharap/features/opportunities/data/opportunity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('FixtureOpportunityRepository loads list from asset', () async {
    final repo = FixtureOpportunityRepository(
      loadAsset: (_) async => '[{"id":"a","category":"contest","title":"t","organization":"o","url":"u","source":"s"}]',
    );
    final list = await repo.fetchAll();
    expect(list, hasLength(1));
    expect(list.first.id, 'a');
  });
}
```

- [ ] **Step 2: 실패 확인** — Run: `flutter test test/features/opportunities/repository_test.dart` → FAIL

- [ ] **Step 3: 구현**

```dart
// lib/features/opportunities/data/opportunity_repository.dart
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../domain/opportunity.dart';

abstract class OpportunityRepository {
  Future<List<Opportunity>> fetchAll();
}

typedef AssetLoader = Future<String> Function(String path);

/// Plan A 구현체: asset fixture에서 로드. Plan B에서 ServerOpportunityRepository로 교체.
class FixtureOpportunityRepository implements OpportunityRepository {
  final AssetLoader loadAsset;
  final String assetPath;
  FixtureOpportunityRepository({
    AssetLoader? loadAsset,
    this.assetPath = 'assets/data/opportunities_sample.json',
  }) : loadAsset = loadAsset ?? rootBundle.loadString;

  @override
  Future<List<Opportunity>> fetchAll() async {
    final raw = await loadAsset(assetPath);
    final List data = jsonDecode(raw) as List;
    return data
        .map((e) => Opportunity.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
```

- [ ] **Step 4: 통과 확인** — Run: 위 명령 → PASS
- [ ] **Step 5: 커밋**

```bash
git add lib/features/opportunities/data/opportunity_repository.dart test/features/opportunities/repository_test.dart
git commit -m "feat(opportunities): add repository interface + fixture impl"
```

---

### Task 4: 정렬·필터 유틸 (마감순 + 마감지난 제거 + 카테고리/개인화 필터)

**Files:**
- Create: `lib/features/opportunities/domain/opportunity_query.dart`
- Test: `test/features/opportunities/sort_filter_test.dart`

- [ ] **Step 1: 실패 테스트**

```dart
// test/features/opportunities/sort_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sharap/features/opportunities/domain/opportunity.dart';
import 'package:sharap/features/opportunities/domain/opportunity_query.dart';

Opportunity _o(String id, OppCategory c, DateTime? d, {List<String> tags = const []}) =>
    Opportunity(id: id, category: c, title: id, organization: 'o', url: 'u', source: 's', deadline: d, tags: tags);

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
    expect(r.map((e) => e.id).toList(), ['soon', 'later', 'nodate']); // past 제거, nodate 맨 뒤
  });

  test('category filter', () {
    final list = [
      _o('c', OppCategory.contest, DateTime(2026, 7, 5)),
      _o('s', OppCategory.scholarship, DateTime(2026, 7, 6)),
    ];
    final r = OpportunityQuery.process(list, now: now, category: OppCategory.scholarship);
    expect(r.map((e) => e.id).toList(), ['s']);
  });

  test('interest tags rank matching items higher', () {
    final list = [
      _o('plain', OppCategory.contest, DateTime(2026, 7, 10)),
      _o('match', OppCategory.contest, DateTime(2026, 7, 20), tags: ['디자인']),
    ];
    final r = OpportunityQuery.process(list, now: now, interests: {'디자인'});
    expect(r.first.id, 'match'); // 관심 태그 매칭이 상단
  });
}
```

- [ ] **Step 2: 실패 확인** — Run: `flutter test test/features/opportunities/sort_filter_test.dart` → FAIL

- [ ] **Step 3: 구현**

```dart
// lib/features/opportunities/domain/opportunity_query.dart
import 'opportunity.dart';

class OpportunityQuery {
  /// 마감 지난 항목 제거 → (관심 매칭 우선) → 마감 임박순. 마감 없는 항목은 맨 뒤.
  static List<Opportunity> process(
    List<Opportunity> items, {
    required DateTime now,
    OppCategory? category,
    Set<String> interests = const {},
    String? query,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    var list = items.where((o) {
      if (o.deadline != null && o.deadline!.isBefore(today)) return false;
      if (category != null && o.category != category) return false;
      if (query != null && query.trim().isNotEmpty) {
        final q = query.toLowerCase();
        final hay = '${o.title} ${o.organization} ${o.tags.join(" ")}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    bool matchesInterest(Opportunity o) =>
        interests.isNotEmpty && o.tags.any(interests.contains);

    list.sort((a, b) {
      final ai = matchesInterest(a), bi = matchesInterest(b);
      if (ai != bi) return ai ? -1 : 1;            // 관심 매칭 우선
      if (a.deadline == null && b.deadline == null) return 0;
      if (a.deadline == null) return 1;             // 마감 없는 건 뒤로
      if (b.deadline == null) return -1;
      return a.deadline!.compareTo(b.deadline!);    // 임박순
    });
    return list;
  }

  static int? daysLeft(Opportunity o, DateTime now) {
    if (o.deadline == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return o.deadline!.difference(today).inDays;
  }
}
```

- [ ] **Step 4: 통과 확인** — Run: 위 명령 → PASS (3 tests)
- [ ] **Step 5: 커밋**

```bash
git add lib/features/opportunities/domain/opportunity_query.dart test/features/opportunities/sort_filter_test.dart
git commit -m "feat(opportunities): add sort/filter query (deadline, category, interests)"
```

---

### Task 5: 스크랩 저장소 (shared_preferences)

**Files:**
- Create: `lib/features/opportunities/domain/scrap_entry.dart`, `lib/features/opportunities/data/scrap_store.dart`
- Test: `test/features/opportunities/scrap_store_test.dart`

- [ ] **Step 1: 실패 테스트**

```dart
// test/features/opportunities/scrap_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sharap/features/opportunities/data/scrap_store.dart';
import 'package:sharap/features/opportunities/domain/scrap_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add, read, update status, remove', () async {
    final store = ScrapStore();
    await store.add(ScrapEntry(id: 'a', title: 't', deadline: DateTime(2026, 7, 20), status: ScrapStatus.interested));
    expect((await store.all()).map((e) => e.id), ['a']);

    await store.setStatus('a', ScrapStatus.applied);
    expect((await store.all()).first.status, ScrapStatus.applied);

    await store.remove('a');
    expect(await store.all(), isEmpty);
  });

  test('survives reload (persisted as json)', () async {
    await ScrapStore().add(ScrapEntry(id: 'x', title: 't', deadline: null, status: ScrapStatus.interested));
    final reloaded = await ScrapStore().all();
    expect(reloaded.single.id, 'x');
  });
}
```

- [ ] **Step 2: 실패 확인** — Run: `flutter test test/features/opportunities/scrap_store_test.dart` → FAIL

- [ ] **Step 3: 구현**

```dart
// lib/features/opportunities/domain/scrap_entry.dart
enum ScrapStatus { interested, preparing, applied }

ScrapStatus scrapStatusFrom(String s) =>
    ScrapStatus.values.firstWhere((e) => e.name == s, orElse: () => ScrapStatus.interested);

class ScrapEntry {
  final String id;
  final String title;
  final DateTime? deadline;
  final ScrapStatus status;
  const ScrapEntry({required this.id, required this.title, required this.deadline, required this.status});

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title,
        'deadline': deadline?.toIso8601String(), 'status': status.name,
      };
  factory ScrapEntry.fromJson(Map<String, dynamic> j) => ScrapEntry(
        id: j['id'], title: j['title'],
        deadline: j['deadline'] == null ? null : DateTime.parse(j['deadline']),
        status: scrapStatusFrom(j['status'] ?? 'interested'),
      );
  ScrapEntry copyWith({ScrapStatus? status}) =>
      ScrapEntry(id: id, title: title, deadline: deadline, status: status ?? this.status);
}
```

```dart
// lib/features/opportunities/data/scrap_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/scrap_entry.dart';

class ScrapStore {
  static const _key = 'opp_scraps_v1';

  Future<List<ScrapEntry>> all() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => ScrapEntry.fromJson(e)).toList();
  }

  Future<void> _save(List<ScrapEntry> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<bool> isScrapped(String id) async => (await all()).any((e) => e.id == id);

  Future<void> add(ScrapEntry e) async {
    final list = await all();
    if (list.any((x) => x.id == e.id)) return;
    list.add(e);
    await _save(list);
  }

  Future<void> remove(String id) async {
    final list = await all()..removeWhere((e) => e.id == id);
    await _save(list);
  }

  Future<void> setStatus(String id, ScrapStatus s) async {
    final list = await all();
    final i = list.indexWhere((e) => e.id == id);
    if (i == -1) return;
    list[i] = list[i].copyWith(status: s);
    await _save(list);
  }
}
```

- [ ] **Step 4: 통과 확인** — Run: 위 명령 → PASS
- [ ] **Step 5: 커밋**

```bash
git add lib/features/opportunities/domain/scrap_entry.dart lib/features/opportunities/data/scrap_store.dart test/features/opportunities/scrap_store_test.dart
git commit -m "feat(opportunities): add scrap store (shared_preferences)"
```

---

### Task 6: 개인화 설정 저장 (shared_preferences)

**Files:**
- Create: `lib/features/opportunities/domain/user_prefs.dart`, `lib/features/opportunities/data/prefs_store.dart`
- Test: `test/features/opportunities/prefs_store_test.dart`

- [ ] **Step 1: 실패 테스트**

```dart
// test/features/opportunities/prefs_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sharap/features/opportunities/data/prefs_store.dart';
import 'package:sharap/features/opportunities/domain/user_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save and load prefs', () async {
    final store = OppPrefsStore();
    await store.save(const OppUserPrefs(interests: {'디자인', 'IT'}, region: '서울'));
    final p = await store.load();
    expect(p.interests, containsAll({'디자인', 'IT'}));
    expect(p.region, '서울');
  });

  test('default is empty', () async {
    final p = await OppPrefsStore().load();
    expect(p.interests, isEmpty);
    expect(p.region, isNull);
  });
}
```

- [ ] **Step 2: 실패 확인** — Run: `flutter test test/features/opportunities/prefs_store_test.dart` → FAIL

- [ ] **Step 3: 구현**

```dart
// lib/features/opportunities/domain/user_prefs.dart
class OppUserPrefs {
  final Set<String> interests;
  final String? region;
  const OppUserPrefs({this.interests = const {}, this.region});
}

/// 온보딩/필터에서 고를 수 있는 관심 분야 목록(고정).
const kInterestOptions = [
  'IT/개발', '디자인', '마케팅', '기획', '영상/콘텐츠', '이공계/연구', '경영/경제', '예술/문학',
];
```

```dart
// lib/features/opportunities/data/prefs_store.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/user_prefs.dart';

class OppPrefsStore {
  static const _kInterests = 'opp_interests_v1';
  static const _kRegion = 'opp_region_v1';

  Future<OppUserPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return OppUserPrefs(
      interests: (p.getStringList(_kInterests) ?? const []).toSet(),
      region: p.getString(_kRegion),
    );
  }

  Future<void> save(OppUserPrefs prefs) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kInterests, prefs.interests.toList());
    if (prefs.region == null) {
      await p.remove(_kRegion);
    } else {
      await p.setString(_kRegion, prefs.region!);
    }
  }
}
```

- [ ] **Step 4: 통과 확인** — Run: 위 명령 → PASS
- [ ] **Step 5: 커밋**

```bash
git add lib/features/opportunities/domain/user_prefs.dart lib/features/opportunities/data/prefs_store.dart test/features/opportunities/prefs_store_test.dart
git commit -m "feat(opportunities): add personalization prefs store"
```

---

## Phase 3 — 함정 콘텐츠 + 알림

### Task 7: 함정/체크리스트 정적 콘텐츠

**Files:**
- Create: `lib/features/opportunities/domain/pitfall_content.dart`

- [ ] **Step 1: 구현** (테스트 불필요한 순수 상수 데이터)

```dart
// lib/features/opportunities/domain/pitfall_content.dart
import 'opportunity.dart';

class Pitfall {
  final String title;
  final String body;
  const Pitfall(this.title, this.body);
}

/// 카테고리별 함정/체크리스트(앱 내장 정적 콘텐츠).
const Map<OppCategory, List<Pitfall>> kPitfalls = {
  OppCategory.scholarship: [
    Pitfall('가구원 정보제공 동의 필수',
        '국가장학금은 신청만으로 끝이 아닙니다. 부모/배우자의 가구원 정보제공 동의를 안 하면 소득구간 산정이 안 돼 자동 탈락합니다. 신청현황에서 동의·서류 상태를 꼭 확인하세요.'),
    Pitfall('재학생은 1차에 신청',
        '재학생은 가급적 1차에 신청하세요. 2차 신청은 평생 2회만 구제되고 이후 학기 수혜에 제한이 생길 수 있습니다.'),
    Pitfall('중복수혜 한도 주의',
        '교내+외부+국가 장학을 합쳐 등록금을 초과하면 환수되거나 일부만 인정될 수 있습니다.'),
  ],
  OppCategory.contest: [
    Pitfall('저작권·참가비 조항 확인',
        '응모 전 요강의 저작권 조항을 확인하세요. 입상하지 않은 응모작까지 저작권이 주최 측에 귀속되거나 참가비를 선불로 받는 공모전은 주의가 필요합니다.'),
  ],
};
```

- [ ] **Step 2: 커밋**

```bash
git add lib/features/opportunities/domain/pitfall_content.dart
git commit -m "feat(opportunities): add static pitfall/checklist content"
```

---

### Task 8: 마감 임박 로컬 알림 (D-3 / D-1)

**Files:**
- Create: `lib/features/opportunities/data/deadline_notifier.dart`

> 참고: 기존 `flutter_local_notifications` 초기화/타임존 셋업이 `lib/main.dart`에 있는지 먼저 확인하고 재사용한다(중복 초기화 금지). 채널/권한은 기존 알림 설정을 따른다.

- [ ] **Step 1: 구현** (플러그인 직접 의존 — 단위 테스트 대신 기기 검증. 로직은 ID 규칙·날짜 계산을 순수 함수로 분리해 검증 가능하게)

```dart
// lib/features/opportunities/data/deadline_notifier.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// 알림 ID는 opportunity id 해시에서 결정적으로 생성(예약/취소 짝 맞춤).
int notifId(String oppId, int daysBefore) =>
    (oppId.hashCode & 0x7fffffff) ^ daysBefore;

/// 마감 D-3, D-1 09:00에 로컬 알림 예약. 과거 시점은 건너뜀.
class DeadlineNotifier {
  final FlutterLocalNotificationsPlugin plugin;
  DeadlineNotifier(this.plugin);

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('opp_deadline', '혜택 마감 알림',
        channelDescription: '스크랩한 기회의 마감 임박 알림', importance: Importance.high),
  );

  Future<void> schedule({required String oppId, required String title, required DateTime deadline}) async {
    for (final d in [3, 1]) {
      final when = DateTime(deadline.year, deadline.month, deadline.day - d, 9);
      if (when.isBefore(DateTime.now())) continue;
      await plugin.zonedSchedule(
        notifId(oppId, d),
        '마감 D-$d · $title',
        '신청 마감이 다가옵니다. 잊지 마세요!',
        tz.TZDateTime.from(when, tz.local),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancel(String oppId) async {
    for (final d in [3, 1]) {
      await plugin.cancel(notifId(oppId, d));
    }
  }
}
```

- [ ] **Step 2: 커밋**

```bash
git add lib/features/opportunities/data/deadline_notifier.dart
git commit -m "feat(opportunities): add deadline local-notification scheduler"
```

---

## Phase 4 — Providers + UI (레이아웃 A)

### Task 9: Riverpod providers

**Files:**
- Create: `lib/features/opportunities/presentation/opportunities_providers.dart`

> `lib/features/notices/`의 provider 스타일을 그대로 따른다.

- [ ] **Step 1: 구현**

```dart
// lib/features/opportunities/presentation/opportunities_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/opportunity_repository.dart';
import '../data/scrap_store.dart';
import '../data/prefs_store.dart';
import '../domain/opportunity.dart';
import '../domain/user_prefs.dart';

final opportunityRepositoryProvider =
    Provider<OpportunityRepository>((ref) => FixtureOpportunityRepository());

final scrapStoreProvider = Provider<ScrapStore>((ref) => ScrapStore());
final prefsStoreProvider = Provider<OppPrefsStore>((ref) => OppPrefsStore());

final allOpportunitiesProvider = FutureProvider<List<Opportunity>>(
    (ref) => ref.watch(opportunityRepositoryProvider).fetchAll());

final userPrefsProvider = FutureProvider<OppUserPrefs>(
    (ref) => ref.watch(prefsStoreProvider).load());

/// 현재 선택된 카테고리 필터(null=전체)와 검색어.
final selectedCategoryProvider = StateProvider<OppCategory?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');
```

- [ ] **Step 2: 커밋**

```bash
git add lib/features/opportunities/presentation/opportunities_providers.dart
git commit -m "feat(opportunities): add riverpod providers"
```

---

### Task 10: 컴팩트 카드 위젯 (레이아웃 A)

**Files:**
- Create: `lib/features/opportunities/presentation/opportunity_card.dart`

- [ ] **Step 1: 구현**

```dart
// lib/features/opportunities/presentation/opportunity_card.dart
import 'package:flutter/material.dart';
import '../domain/opportunity.dart';
import '../domain/opportunity_query.dart';

class OpportunityCard extends StatelessWidget {
  final Opportunity opp;
  final bool scrapped;
  final VoidCallback onTap;
  final VoidCallback onToggleScrap;
  const OpportunityCard({super.key, required this.opp, required this.scrapped, required this.onTap, required this.onToggleScrap});

  Color _catColor() {
    switch (opp.category) {
      case OppCategory.scholarship: return const Color(0xFF1A8F3C);
      case OppCategory.education: return const Color(0xFF7B3FF2);
      case OppCategory.intern: return const Color(0xFFE08600);
      default: return const Color(0xFF1C5FD6); // contest/activity
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = OpportunityQuery.daysLeft(opp, DateTime.now());
    final benefit = opp.extra['prize'] ?? opp.extra['amount'] ?? opp.extra['cost'] ?? opp.extra['pay'];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: _catColor().withOpacity(.12), borderRadius: BorderRadius.circular(6)),
                child: Text(categoryLabel(opp.category), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _catColor())),
              ),
              const Spacer(),
              if (d != null)
                Text(d <= 0 ? 'D-day' : 'D-$d',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: d <= 3 ? const Color(0xFFE5484D) : Colors.grey)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text(opp.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(scrapped ? Icons.star : Icons.star_border, color: scrapped ? const Color(0xFFFFB400) : Colors.grey),
                onPressed: onToggleScrap,
              ),
            ]),
            Text('${opp.organization}${opp.extra['target'] != null ? " · ${opp.extra['target']}" : ""}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (benefit != null) Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(benefit, style: const TextStyle(fontSize: 12, color: Color(0xFF1A8F3C), fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 커밋**

```bash
git add lib/features/opportunities/presentation/opportunity_card.dart
git commit -m "feat(opportunities): add compact opportunity card (layout A)"
```

---

### Task 11: 혜택 탭 메인 페이지 (칩 + 함정 배너 + 리스트)

**Files:**
- Create: `lib/features/opportunities/presentation/opportunities_page.dart`

- [ ] **Step 1: 구현**

```dart
// lib/features/opportunities/presentation/opportunities_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/opportunity.dart';
import '../domain/opportunity_query.dart';
import '../domain/pitfall_content.dart';
import 'opportunities_providers.dart';
import 'opportunity_card.dart';
import 'opportunity_detail_page.dart';
import 'my_scraps_page.dart';

class OpportunitiesPage extends ConsumerWidget {
  const OpportunitiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAll = ref.watch(allOpportunitiesProvider);
    final asyncPrefs = ref.watch(userPrefsProvider);
    final cat = ref.watch(selectedCategoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('혜택·기회'), actions: [
        IconButton(icon: const Icon(Icons.star), tooltip: '내 스크랩',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyScrapsPage()))),
      ]),
      body: Column(children: [
        _CategoryChips(selected: cat, onSelect: (c) => ref.read(selectedCategoryProvider.notifier).state = c),
        if (cat != null && kPitfalls[cat] != null) _PitfallBanner(pitfalls: kPitfalls[cat]!),
        Expanded(child: asyncAll.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('불러오지 못했어요\n$e', textAlign: TextAlign.center)),
          data: (all) {
            final prefs = asyncPrefs.asData?.value;
            final list = OpportunityQuery.process(all, now: DateTime.now(),
                category: cat, interests: prefs?.interests ?? const {},
                query: ref.watch(searchQueryProvider));
            if (list.isEmpty) return const Center(child: Text('해당 조건의 기회가 없어요'));
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(allOpportunitiesProvider),
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _CardConnector(opp: list[i]),
              ),
            );
          },
        )),
      ]),
    );
  }
}

class _CardConnector extends ConsumerStatefulWidget {
  final Opportunity opp;
  const _CardConnector({required this.opp});
  @override
  ConsumerState<_CardConnector> createState() => _CardConnectorState();
}

class _CardConnectorState extends ConsumerState<_CardConnector> {
  bool _scrapped = false;
  @override
  void initState() {
    super.initState();
    ref.read(scrapStoreProvider).isScrapped(widget.opp.id).then((v) {
      if (mounted) setState(() => _scrapped = v);
    });
  }
  @override
  Widget build(BuildContext context) {
    return OpportunityCard(
      opp: widget.opp,
      scrapped: _scrapped,
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => OpportunityDetailPage(opp: widget.opp))),
      onToggleScrap: () async {
        final store = ref.read(scrapStoreProvider);
        if (_scrapped) {
          await store.remove(widget.opp.id);
        } else {
          await store.add(_scrapEntryOf(widget.opp));
        }
        if (mounted) setState(() => _scrapped = !_scrapped);
      },
    );
  }
}

class _CategoryChips extends StatelessWidget {
  final OppCategory? selected;
  final ValueChanged<OppCategory?> onSelect;
  const _CategoryChips({required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final items = <(String, OppCategory?)>[('전체', null), for (final c in OppCategory.values) (categoryLabel(c), c)];
    return SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
      for (final it in items) Padding(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
        child: ChoiceChip(label: Text(it.$1), selected: selected == it.$2, onSelected: (_) => onSelect(it.$2))),
    ]));
  }
}

class _PitfallBanner extends StatelessWidget {
  final List<Pitfall> pitfalls;
  const _PitfallBanner({required this.pitfalls});
  @override
  Widget build(BuildContext context) {
    final p = pitfalls.first;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFD8A8))),
      child: Text('⚠️ ${p.title} — ${p.body}', style: const TextStyle(fontSize: 12, color: Color(0xFF9A5B00))),
    );
  }
}
```

> `_scrapEntryOf`는 Task 12에서 상세 페이지와 공유하므로 `opportunity.dart` 또는 별도 헬퍼에 정의(아래 Step에서 추가).

- [ ] **Step 2: 공유 헬퍼 추가** — `lib/features/opportunities/domain/scrap_entry.dart` 하단에:

```dart
import 'opportunity.dart';
ScrapEntry scrapEntryOf(Opportunity o) =>
    ScrapEntry(id: o.id, title: o.title, deadline: o.deadline, status: ScrapStatus.interested);
```

그리고 page에서 `_scrapEntryOf` → `scrapEntryOf`로 호출하고 import 추가.

- [ ] **Step 3: 커밋**

```bash
git add lib/features/opportunities/presentation/opportunities_page.dart lib/features/opportunities/domain/scrap_entry.dart
git commit -m "feat(opportunities): add main page (chips, pitfall banner, list)"
```

---

### Task 12: 상세 페이지 (원문 열기 + 스크랩 + 함정 + 알림 예약)

**Files:**
- Create: `lib/features/opportunities/presentation/opportunity_detail_page.dart`

- [ ] **Step 1: 구현**

```dart
// lib/features/opportunities/presentation/opportunity_detail_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/opportunity.dart';
import '../domain/pitfall_content.dart';
import '../domain/scrap_entry.dart';
import 'opportunities_providers.dart';

class OpportunityDetailPage extends ConsumerStatefulWidget {
  final Opportunity opp;
  const OpportunityDetailPage({super.key, required this.opp});
  @override
  ConsumerState<OpportunityDetailPage> createState() => _S();
}

class _S extends ConsumerState<OpportunityDetailPage> {
  bool _scrapped = false;
  @override
  void initState() {
    super.initState();
    ref.read(scrapStoreProvider).isScrapped(widget.opp.id).then((v) { if (mounted) setState(() => _scrapped = v); });
  }

  Future<void> _toggle() async {
    final store = ref.read(scrapStoreProvider);
    if (_scrapped) {
      await store.remove(widget.opp.id);
    } else {
      await store.add(scrapEntryOf(widget.opp));
      // 마감 알림 예약은 DeadlineNotifier로 (main에서 주입된 플러그인 사용).
      // ref로 노출된 notifier가 있으면 schedule 호출. 없으면 이 단계 생략하고 Task 14에서 연결.
    }
    if (mounted) setState(() => _scrapped = !_scrapped);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.opp;
    final pitfalls = kPitfalls[o.category] ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(categoryLabel(o.category)), actions: [
        IconButton(icon: Icon(_scrapped ? Icons.star : Icons.star_border), onPressed: _toggle),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(o.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(o.organization, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        for (final e in o.extra.entries) _row(e.key, e.value),
        if (o.deadline != null) _row('마감', '${o.deadline!.year}.${o.deadline!.month}.${o.deadline!.day}'),
        if (o.region != null) _row('지역', o.region!),
        if (o.tags.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(spacing: 6, children: [for (final t in o.tags) Chip(label: Text(t))])),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: () => launchUrl(Uri.parse(o.url), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new), label: const Text('원문 보기')),
        if (pitfalls.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('⚠️ 신청 전 확인하세요', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final p in pitfalls) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text('• ${p.title}\n  ${p.body}', style: const TextStyle(fontSize: 13, color: Color(0xFF9A5B00)))),
        ],
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 84, child: Text(k, style: const TextStyle(color: Colors.grey))),
        Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]));
}
```

- [ ] **Step 2: 커밋**

```bash
git add lib/features/opportunities/presentation/opportunity_detail_page.dart
git commit -m "feat(opportunities): add detail page (open url, scrap, pitfalls)"
```

---

### Task 13: 내 스크랩 페이지 (상태별·마감순)

**Files:**
- Create: `lib/features/opportunities/presentation/my_scraps_page.dart`

- [ ] **Step 1: 구현**

```dart
// lib/features/opportunities/presentation/my_scraps_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/scrap_entry.dart';
import 'opportunities_providers.dart';

class MyScrapsPage extends ConsumerStatefulWidget {
  const MyScrapsPage({super.key});
  @override
  ConsumerState<MyScrapsPage> createState() => _S();
}

class _S extends ConsumerState<MyScrapsPage> {
  List<ScrapEntry> _items = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final all = await ref.read(scrapStoreProvider).all();
    all.sort((a, b) {
      if (a.deadline == null && b.deadline == null) return 0;
      if (a.deadline == null) return 1;
      if (b.deadline == null) return -1;
      return a.deadline!.compareTo(b.deadline!);
    });
    setState(() { _items = all; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 스크랩')),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty ? const Center(child: Text('스크랩한 기회가 없어요'))
        : ListView.builder(itemCount: _items.length, itemBuilder: (_, i) {
            final e = _items[i];
            final d = e.deadline == null ? null
              : e.deadline!.difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays;
            return ListTile(
              title: Text(e.title),
              subtitle: Text(d == null ? '마감 미정' : (d < 0 ? '마감됨' : 'D-$d')),
              trailing: DropdownButton<ScrapStatus>(
                value: e.status,
                items: const [
                  DropdownMenuItem(value: ScrapStatus.interested, child: Text('관심')),
                  DropdownMenuItem(value: ScrapStatus.preparing, child: Text('준비중')),
                  DropdownMenuItem(value: ScrapStatus.applied, child: Text('지원완료')),
                ],
                onChanged: (s) async {
                  if (s == null) return;
                  await ref.read(scrapStoreProvider).setStatus(e.id, s);
                  _load();
                },
              ),
            );
          }),
    );
  }
}
```

- [ ] **Step 2: 커밋**

```bash
git add lib/features/opportunities/presentation/my_scraps_page.dart
git commit -m "feat(opportunities): add my-scraps page (status + deadline sort)"
```

---

## Phase 5 — 통합 (앱 탭 + 온보딩 + 알림 연결)

### Task 14: 스크랩 ↔ 마감 알림 연결

**Files:**
- Modify: `lib/features/opportunities/presentation/opportunities_providers.dart` (DeadlineNotifier provider 추가)
- Modify: 카드/상세의 스크랩 토글에서 schedule/cancel 호출

- [ ] **Step 1: provider 추가** — `main.dart`에서 초기화된 `FlutterLocalNotificationsPlugin` 인스턴스를 찾아 주입(기존 알림 인스턴스 재사용). 없으면 전역 인스턴스를 노출하는 provider 작성:

```dart
// opportunities_providers.dart 에 추가
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../data/deadline_notifier.dart';

final localNotifPluginProvider = Provider<FlutterLocalNotificationsPlugin>((ref) {
  throw UnimplementedError('main.dart에서 override로 주입'); // ProviderScope overrides로 기존 인스턴스 주입
});
final deadlineNotifierProvider = Provider<DeadlineNotifier>(
    (ref) => DeadlineNotifier(ref.watch(localNotifPluginProvider)));
```

- [ ] **Step 2: main.dart의 `ProviderScope`에 override 추가**

```dart
// main.dart (기존 ProviderScope에 overrides 추가)
ProviderScope(
  overrides: [ localNotifPluginProvider.overrideWithValue(flutterLocalNotificationsPlugin) ],
  child: const MyApp(),
)
```

- [ ] **Step 3: 스크랩 토글에서 호출** — `opportunities_page.dart`와 `opportunity_detail_page.dart`의 토글 로직 수정:

```dart
// add 시
if (widget.opp.deadline != null) {
  await ref.read(deadlineNotifierProvider).schedule(
    oppId: widget.opp.id, title: widget.opp.title, deadline: widget.opp.deadline!);
}
// remove 시
await ref.read(deadlineNotifierProvider).cancel(widget.opp.id);
```

- [ ] **Step 4: 기기 검증** — `/ship`으로 설치 후: 마감 임박(D-3 이내) 항목 스크랩 → 알림 예약 로그 확인(`debugPrint`). 해제 시 취소.

- [ ] **Step 5: 커밋**

```bash
git add lib/features/opportunities/presentation/ lib/main.dart
git commit -m "feat(opportunities): wire scrap toggle to deadline notifications"
```

---

### Task 15: 앱 네비게이션에 혜택 탭 추가

**Files:**
- Modify: `lib/app.dart`

> ⚠️ 전역 규칙 14: 편집 후 기존 탭(과제·달력·식당·지도·공지 등)이 모두 그대로인지 Read로 재확인.

- [ ] **Step 1: 기존 탭 구성 확인** — Run: `grep -n "BottomNavigation\|NavigationBar\|destinations\|tabs" lib/app.dart` → 현재 탭 등록부 파악.

- [ ] **Step 2: 혜택 탭 추가** — 기존 탭 목록에 `OpportunitiesPage()`와 아이콘(`Icons.card_giftcard`/라벨 '혜택')을 **기존 항목을 지우지 않고** 추가.

- [ ] **Step 3: 무결성 검증** — Read `lib/app.dart` 전체를 다시 읽어 기존 탭이 모두 존재하는지 육안 확인.

- [ ] **Step 4: 빌드 + 기기 검증** — `/ship` → 혜택 탭 진입, 리스트·카드·상세·스크랩 동작 확인.

- [ ] **Step 5: 커밋**

```bash
git add lib/app.dart
git commit -m "feat(opportunities): add 혜택 tab to app navigation"
```

---

### Task 16: 온보딩에 관심분야·지역 스텝 추가

**Files:**
- Modify: `lib/features/onboarding/...` (기존 온보딩 플로우)

> ⚠️ 전역 규칙 14: 기존 온보딩 스텝(있던 항목)이 사라지지 않았는지 편집 후 반드시 재확인.

- [ ] **Step 1: 기존 온보딩 구조 파악** — Run: `find lib/features/onboarding -name "*.dart"` 및 각 파일 Read로 스텝 추가 지점 확인.

- [ ] **Step 2: 관심분야(멀티선택, `kInterestOptions`) + 지역(텍스트/선택) 스텝 추가** — 완료 시 `OppPrefsStore().save(OppUserPrefs(interests:..., region:...))` 호출.

- [ ] **Step 3: 무결성 검증** — 온보딩 전체 Read로 기존 스텝 보존 확인.

- [ ] **Step 4: 기기 검증** — 앱 데이터 초기화(또는 온보딩 재진입 경로) 후 온보딩에서 관심분야 저장 → 혜택 탭에서 개인화 상단 정렬 확인.

- [ ] **Step 5: 커밋**

```bash
git add lib/features/onboarding/
git commit -m "feat(onboarding): add interests/region step for opportunities personalization"
```

---

## Phase 6 — 마무리 검증

### Task 17: 전체 테스트 + 기기 종단 검증

- [ ] **Step 1:** Run `flutter test` → 전체 통과
- [ ] **Step 2:** Run `flutter analyze` → 경고 0(또는 기존 수준)
- [ ] **Step 3:** `/ship`으로 설치 후 시나리오 검증:
  - 혜택 탭 → 카테고리 칩 전환 → 함정 배너 노출
  - 카드 스크랩 ⭐ → 내 스크랩에 표시 → 상태 변경
  - 마감 임박 항목 스크랩 → 로컬 알림 예약(로그 확인)
  - 상세 → 원문 열기(외부 브라우저)
  - 온보딩 관심분야 → 혜택 탭 상단 정렬 반영
- [ ] **Step 4:** 검증 결과를 "기기에서 확인됨" 수준으로 기록(전역 규칙 10).

---

## Self-Review 결과 (작성자 점검)

- **스펙 커버리지:** F1(개인화=Task 6,16) · F2(스크랩/D-day=Task 5,13) · F3(로컬알림=Task 8,14) · F4(함정=Task 7,11,12) · UI 레이아웃 A(Task 10,11) · 데이터 모델(Task 1) · 탭 추가(Task 15) 모두 태스크 존재. ✅
- **서버 의존성:** Plan A는 fixture로 완결. 서버 연동은 Task 3의 `OpportunityRepository` 인터페이스 교체점으로 격리 → Plan B에서 `ServerOpportunityRepository` 추가 시 provider 한 줄 교체. ✅
- **타입 일관성:** `Opportunity`, `OppCategory`, `ScrapEntry/ScrapStatus`, `OppUserPrefs`, `OpportunityQuery.process/daysLeft`, `scrapEntryOf`, `DeadlineNotifier.schedule/cancel`, provider 명칭 전 태스크 일치 확인. ✅
- **플레이스홀더:** 없음(모든 코드 단계에 실제 코드 포함). Task 15/16은 기존 코드 미확인 영역이라 "구조 파악 → 추가 → 무결성 검증" 단계로 구성(규칙 14 준수). 

---

## ⚠️ Plan B (서버) 착수 전 필요 — 사용자 액션

Plan B(서버 집계 파서)는 **실제 API 응답 확인 후** 작성한다(규칙 9). 그 전에 필요한 것:

1. **공공데이터포털(data.go.kr) 회원가입 + 활용신청**
   - 한국장학재단 학자금지원정보(대학생) #15028252
   - 온통청년 청년정책 OpenAPI #15143273
   - 고용24 내일배움카드 훈련과정 OpenAPI #15109032
2. 발급된 **인증키**를 Render 서버 환경변수로 등록.
3. 키 확보 후, 각 API를 `curl`로 실제 호출해 응답 필드를 함께 확인 → 정확한 필드명으로 파서 태스크 작성.
