# Plan: Phase 2 — 커스텀 학과 공지 (서버 HTML 범용 추출기)

## 배경 (실측 2026-06-03)
- 1단계(RSS)로 **29개 학과** 커버 완료(기기 검증됨).
- 나머지 ~40개 커스텀 학과 조사 결과:
  - **대부분 서버 렌더링 HTML** (econ, cba, chem, biosci, math, nursing, physics, medicine, ece, cbe, sees, music, geog, aerospace, cee 등) → API 역공학 불필요.
  - **SPA**: cse(Vite/Remix) 등 소수 → HTML 파싱 불가, 홈페이지 fallback.
  - **WordPress+KBoard**(me, cls, art, religion): /feed/에 공지 없음 → 서버 HTML 경로로 처리하거나 fallback.
- 게시판 URL·구조는 학과마다 다름(econ `/announcement/notice`, nursing `/board/notice`, chem `/community/notice`, cba `/newsroom/notice`, physics `/boards/notice`).

## 목표
서버 HTML 학과 공지를 **학과별 selector 없이** 범용 추출기 하나로 다수 커버. 점진 등록.

## 접근: 범용 파서 + 최소 선택적 설정 (Codex 반영 — 목표 하향)

### 1. 소스 모델 확장 (`department_notice_source.dart`)
```dart
class DepartmentNoticeSource {
  final String deptCode;
  final String? rssFeedUrl;            // 1단계 RSS (우선)
  final String? noticeListUrl;         // 2단계 서버 HTML 목록 페이지
  final String? containerSelector;     // (선택) 목록 컨테이너 강제 지정
  final List<String> excludeTextPatterns; // (선택) "더보기","목록" 등 제외
  final String homepageUrl;
}
```
- fetch 우선순위: `rssFeedUrl` → `noticeListUrl` → 없으면 homepage fallback.
- 기본은 범용 휴리스틱, 오탐 학과만 containerSelector/excludeTextPatterns로 보정.

### 2. `parseHtmlNoticeList(html, baseUrl, {selector, exclude})` (순수 함수, package:html)
- 후보 행: `<tr>`/`<li>` 중 **텍스트 있는 `<a>` + 가시 텍스트 날짜** 동시 포함.
- **링크 추출**: `href` 우선, 없으면 `onclick`/`javascript:goView('123')`에서 id 추출 시도. 상대·protocol-relative → baseUrl 절대화. query-only(`#`,`javascript:void`)·앵커는 제외.
- **날짜 정규화**(`parseListDate`): `YYYY.MM.DD`, `YYYY-MM-DD`, `YYYY/MM/DD`, `YYYY. MM. DD`, `YYYY년 M월 D일`, `YY.MM.DD`. **가시 텍스트에서만** 추출(버전쿼리·파일경로 숫자 무시). `MM.DD`만 있으면 **현재 연도** 가정.
- **컨테이너 선택**: selector 있으면 그것, 없으면 후보 행이 가장 많은 공통 부모 채택(메뉴·푸터 배제).
- **비게시글 필터**: 링크 텍스트가 "공지사항/Notice/더보기/목록/검색/로그인/첨부" 등 또는 너무 짧으면 제외(+excludeTextPatterns).
- **고정(상단)공지**: 날짜 없거나 오래돼도 포함하되 정렬은 날짜순(없으면 뒤).
- **모바일/데스크탑 중복 목록**: 정규화 링크 dedupe로 흡수.
- limit 50, 날짜 내림차순(없으면 뒤). 반환 `List<Notice>`.
- **실패 vs 공지없음 구분**: 후보 컨테이너 자체를 못 찾으면 `throw`(→ fallback/에러), 컨테이너는 있는데 0행이면 정상 빈 목록.

### 3. 인코딩 처리 (Codex — bytes로)
- HTML은 **`ResponseType.bytes`로 수신**. `Content-Type` charset → 없으면 바이트 앞부분 `<meta charset>`/`euc-kr` 탐지. UTF-8 기본, euc-kr이면 변환 후 파싱(문자열 디코딩 후엔 복구 불가하므로 반드시 bytes 단계에서).

### 4. source 의미 정리
- 현재 학과 공지는 `NoticeSource.sports`를 재사용 중 → 의미 혼동. `NoticeSource.department` 값 추가하고 학과 공지에 사용(캐시 하위호환: 기존 'sports' 값은 그대로 디코딩).

### 5. fetch 경로 (`notice_repository.dart`)
- `getDepartmentNotices`: rssFeedUrl → RSS, 없고 noticeListUrl → HTML(bytes+charset+`parseHtmlNoticeList`), 둘 다 없으면 빈 결과. 캐시·오프라인 fallback 동일.

## 롤아웃 (점진, 큰 학과부터)
- 학과별로 `noticeListUrl` 확인 + 추출 결과 **육안 검증** 후 등록.
- 1차 후보: 경제·경영·화학·생명과학·간호·물리·수리·전기정보·화생공·지구환경·의예.
- 검증 실패/SPA(cse) → 홈페이지 fallback.

## 성공 기준 (fixture 기반 — Codex)
- [x] **실제 HTML fixture 저장**(econ/nursing/chem 3~5개를 `test/fixtures/`에) 후 그에 대한 단위 테스트.
- [x] `parseHtmlNoticeList` 테스트: 표/리스트 픽스처, head·버전쿼리 날짜 false positive 무시, 상대·onclick 링크 처리, "더보기/목록" 제외, dedupe, limit, 컨테이너 못 찾으면 throw.
- [x] `parseListDate` 다양한 형식 + MM.DD 현재연도 가정 테스트.
- [ ] (수동/통합, CI 제외) 라이브 페이지 추출이 실제 공지와 일치 확인.
- [n/a] EUC-KR fixture 한글 정상 디코딩 — 현재 등록 학과 모두 UTF-8; EUC-KR 시도 시 ScrapingException throw로 처리.
- [x] `flutter analyze` 무경고 / `flutter test` 전체 통과. (117/117 — 2026-06-03)
- [ ] 기기에서 1개 이상 커스텀 학과 공지 표시 확인.

## 범위 (점진)
- **1차 PR: econ / nursing / chem 만** 등록·검증. 파서 규칙이 충분히 맞는지 본 뒤 학과 확대.
- 라이브 검증은 수동, 단위 테스트는 fixture로(네트워크 비의존).
- (장기) 더 나은 유지보수: 서버 사이드 수집·정규화 후 앱은 정규화 API만 — 서버 repo 접근 시 별도 검토.

## 변경 파일
1. `lib/features/notices/domain/department_notice_source.dart` (noticeListUrl 추가 + 등록)
2. `lib/features/notices/data/notice_repository.dart` (parseHtmlNoticeList + HTML fetch 경로 + 인코딩)
3. `test/notice_parser_test.dart` (HTML 추출 테스트)

## 리스크
- 범용 추출 오탐(엉뚱한 표 선택) → 학과별 검증 필수, 실패 시 fallback.
- CMS 구조 변경 시 깨짐 → 개별 학과 격리(한 곳 실패가 전체에 영향 없음).
- WAF/타임아웃 → graceful degradation.
- 점진 작업: 1차 PR은 소수 검증 학과만, 나머지는 후속.
