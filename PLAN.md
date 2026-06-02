# Plan: 학과별 공지 (사용자 학과 기반, RSS 1단계 / on-device)

## 목적
현재 하드코딩된 "체육교육과 공지" 탭을, 사용자가 온보딩에서 고른 **본인 학과의 공지**로 일반화한다.
1단계는 RSS(WordPress) 학과를 커버하고, 미지원 학과는 "학과 홈페이지 열기" fallback을 제공한다.

## 실측 조사 결론 (2026-06-02, 직접 확인 — 규칙 9)
- 학과 사이트는 제각각(표본 8개 중 7개 상이). 공통 API 없음.
- mySNU `deptList` JSON 엔드포인트에 전 학과 홈페이지 URL이 있음 (288+개 유닛, 학부 학과 ~80).
- 표본 26개 중 **~50%가 WordPress RSS(`/feed/`) 동작** (국문·영문·독문·역사·사회·언론·통계·기계·재료·건축·식물생산·산림·체육 등). 나머지 50%는 커스텀(404/500).
- **주의:** RSS 존재 ≠ 실제 공지 포함. 기계공학부(me.snu)는 RSS는 뜨지만 KBoard 공지가 빠지고 옛 글만 나옴 → **등록 전 피드 내용을 1건씩 확인**한다.
- 구현 위치: **on-device** (기존 sports 스크래퍼와 동일 방식, 서버 불필요, 각 학생은 본인 과 피드 1개만 요청).

## 아키텍처 (Codex 리뷰 반영)

> 플랫폼: **모바일 전용**(Android/iOS). Flutter web 미지원이므로 on-device fetch CORS 문제 없음.

### 상태 3단계 (별도 flag 없음 — Codex)
1. `noticeSourceFor(deptCode) == null` → **학과 매핑 없음** (예: 온보딩 미완, 미등록 학과) → "학과 설정/준비 중" 안내
2. source 있음 + `rssFeedUrl == null` → **홈페이지 fallback** ("학과 홈페이지 열기")
3. source 있음 + `rssFeedUrl != null` → **RSS 시도** (실패 시 stale 캐시 → 그래도 없으면 네트워크 에러 뷰, "미지원"과 구분)

### 1. 도메인: 학과 공지 소스 (`department_notice_source.dart` 신규)
```dart
class DepartmentNoticeSource {
  final String deptCode;      // snu_departments.dart의 code
  final String? rssFeedUrl;   // null이면 RSS 미지원 → 홈페이지 fallback
  final String homepageUrl;   // "학과 홈페이지 열기"용 (항상 존재)
  const DepartmentNoticeSource({required this.deptCode, this.rssFeedUrl, required this.homepageUrl});
}
const Map<String, DepartmentNoticeSource> departmentNoticeSources = { ... };
DepartmentNoticeSource? noticeSourceFor(String? deptCode);
```
- **1단계는 피드 내용까지 검증된 소수 학과만 등록**(80개 일괄 등록 금지 — Codex). 나머지는 homepage fallback 또는 미등록.

### 2. 범용 피드 파서 (`notice_repository.dart` — 순수 함수 `parseFeed`)
- **`xml` 패키지로 파싱**(package:html 아님 — Codex). HTML entity decode가 필요한 텍스트만 별도 unescape.
- **RSS + Atom 둘 다 지원:**
  - RSS: `rss>channel>item` (`title`,`link`,`pubDate`|`dc:date`)
  - Atom: `feed>entry` (`title`,`link[@href]`,`updated`|`published`)
- → 기존 `Notice` 도메인 재사용.
- **엣지 처리:**
  - 날짜: RFC822("Thu, 28 May 2026 15:20:15 +0000") + ISO8601(`dc:date`/`updated`) 모두 `parseFeedDate`로. 없거나 파싱불가 → `date=null` 보존(숨기지 않음), 정렬 시 맨 뒤.
  - `title` 또는 `link` 빈 item → skip.
  - 상대 link → feed base URL로 절대화.
  - dedupe: link 정규화(소문자 host, http→https, trailing slash·fragment 제거) 후 비교.
  - item 과다 → 최신 **50개** 제한.
- 제목의 `[학생]`,`[장학]` 접두사 → category 추출(선택).
- 안정 id: `dept_<deptCode>_<djb2(normalizedLink)>`.

### 3. Provider 추가 (기존 sports 흐름 보존 — Codex)
- 기존 `sportsNoticesProvider`는 **건드리지 않고**, 새 `departmentNoticesProvider`(`FutureProvider.autoDispose`)를 추가. (회귀 위험 최소화; 검증 후 정리 단계에서 sports 경로 제거)
- 동작: `departmentCodeProvider` → `noticeSourceFor`:
  - rss 있음 → fetch + `parseFeed` + 기존 유효(마감) 필터 재사용.
  - rss 없음/소스 없음 → 상태 3단계대로 UI가 분기(빈 데이터 반환, 에러 아님).
- 캐시 키 **deptCode별 분리** (`notices_dept_<code>_cache`). 1시간 TTL.
- **race condition 가드**: 응답이 현재 선택된 deptCode와 일치할 때만 사용(autoDispose + deptCode를 provider 인자/감시로). 네트워크 실패 → stale 캐시 → 없으면 에러(미지원과 구분).

### 4. UI (`notices_screen.dart`)
- 기존 `_SportsTab` 내부를 deptCode 기반으로 전환(클래스명 유지로 변경 최소화).
- 탭 라벨 = 사용자 학과명 동적 표시 (`snu_departments.dart`로 코드→이름).
- 분기:
  - source.rssFeedUrl 있음 → 기존 리스트 + 기존 마감/유효 필터 그대로.
  - source 없음(미지원) → fallback: "이 학과 공지는 아직 지원하지 않아요" + "학과 홈페이지 열기"(url_launcher, homepageUrl).
  - deptCode 없음(온보딩 미완) → "학과를 먼저 설정해주세요" 안내.

### 5. dept code ↔ feed URL 매핑
- `snu_departments.dart` 한국어명 ↔ `deptList` 한국어명 매칭으로 호스트 확보.
- **RSS-OK + 피드에 실제 공지 확인된 학과만** 1단계 등록(나머지는 homepage fallback).

## 성공 기준 (verify)
- [ ] `parseRssFeed` 단위 테스트: 정상 / 빈 피드 / 깨진 XML / pubDate 없음 / title·link 빈값 / CDATA / 중복 link dedupe
- [ ] `parsePubDate` RFC822(타임존) 파싱 테스트
- [ ] `noticeSourceFor` 테스트: 등록 학과 / 미등록 학과(null 반환 또는 unsupported) / deptCode null
- [ ] 체육교육과가 **RSS 경로**로 정상 표시 + 기존 유효(마감)필터 회귀 없음
- [ ] `flutter analyze` 무경고
- [ ] `flutter test` 전체 통과
- [ ] 빌드 성공 + 기기에서 본인 학과(체육교육과) 공지 확인

## 변경 파일
1. `lib/features/notices/domain/department_notice_source.dart` (신규)
2. `lib/features/notices/data/notice_repository.dart` (RSS 파서 + provider 일반화)
3. `lib/features/notices/presentation/notices_screen.dart` (탭 일반화 + fallback)
4. `test/notice_parser_test.dart` (RSS 파싱 테스트 추가)

## 범위 제외 (2단계 이후)
- 커스텀 플랫폼(econ/physics/chem/nursing/cba/cse 등) 전용 HTML 파서.
- 서버 사이드 집계(앱 업데이트 없이 파서 수정하려면 추후 도입).
- deptList JSON 동적 로딩(현재는 정적 맵으로 충분).

## 추가 엣지 케이스 (Codex)
- Atom feed / `/feed/` 외 경로(`/category/notice/feed/` 등) → 등록 시 실제 동작 URL 확인.
- `pubDate` 외 `dc:date`/`updated`/`published`.
- 상대 link, http/https·trailing slash·query 차이로 인한 중복.
- `deptCode`는 있는데 `snu_departments.dart` 이름 lookup 실패 → 안전 처리(코드 또는 "내 학과"로 표기).
- `homepageUrl` launch 실패 → 스낵바 안내.
- 네트워크 실패 vs 미지원 학과를 **다른 UI**로 표시(오해 방지).

## 리스크 / 주의
- RSS 피드가 실제 공지가 아닐 수 있음 → 등록 전 피드 내용(title/link/date + 최근 공지 일치) 확인(me.snu 반례).
- 일부 학과 WAF/SSL/타임아웃 → graceful degradation(빈 결과 + fallback).
- 학과명 표기 불일치(전공 분리 등) → 매핑 수동 확인.
- 기존 sports 경로는 **보존**(제거는 검증 후 별도 정리).
