# 공지 탭 개선 계획

## 목표
1. 체육교육과 공지 스크래핑 수정 (HTML table -> ul.body li 구조 변경 대응)
2. SNU 비교과 탭: WebView -> Native 리스트 (현재 신청중 + 5일 이내 시작만 표시)

---

## 1. 체육교육과 공지 스크래핑 수정

### 진단
sports.snu.ac.kr 게시판 HTML 구조 변경:
- 기존: table > tbody > tr > td[0..5]
- 현재: ul.board_type_list > ul.body > li > div
  - span.no / span.no.notice > em(공지)
  - span.type  (학생/학적/졸업/홍보)
  - div.subject > a[href=#none] > strong (제목)
  - span.writer, span.hit, span.date (2026-03-04)
  - 모든 링크가 href=#none (로그인 필요) → url = _kSportsUrl(목록 페이지)

### 수정: lib/features/notices/data/notice_repository.dart
_parseSportsHtml() 선택자 변경:
  rows = doc.querySelectorAll('ul.body li')
  title = row.querySelector('div.subject a strong')?.text.trim()
       ?? row.querySelector('div.subject a')?.text.trim()
  category = row.querySelector('span.type')?.text.trim() (공백 제거, 빈값은 null)
  dateText = row.querySelector('span.date')?.text.trim()
  date = DateTime.tryParse(dateText)  // "2026-03-04" 형식
  id = 'sports_${(title+dateText).hashCode}'
  url = _kSportsUrl

---

## 2. SNU 비교과 Native 리스트

### API
- GET https://extra.snu.ac.kr/ptfol/pgm/index.do?currentPageNo={n}&sort=0001
- 인증 불필요, 응답 JSON
- 주요 필드:
    pgmSeq, pgmNm, applyChk(모집중/신청예정/마감),
    aplFrDd("2026.06.01"), aplToDd("2026.06.12"),
    eduFrDd, eduToDd, planBigNm, operOrgzNm, operClassNm, dday
- 상세 URL: https://extra.snu.ac.kr/ptfol/pgm/view.do?pgmSeq={pgmSeq}
- 페이지네이션: totalCnt 필드로 총 개수 파악, 페이지당 10건 추정
- sort=0001 = 모집중 항목 우선 정렬 -> 앞 페이지에 관련 항목 집중

### 필터 기준
- 날짜 파싱: "2026.06.01" -> DateTime.tryParse("2026-06-01")
- isCurrentlyOpen: aplFrom <= now <= aplTo (endOfDay)
- startsWithin5Days: now < aplFrom && aplFrom.diff(now).inDays <= 5
- shouldShow = isCurrentlyOpen || startsWithin5Days
- 전략: page 1부터 fetch, 페이지 내 shouldShow 항목이 0이면 중단. 최대 5페이지.

### 새 파일: lib/features/notices/domain/extra_program.dart
class ExtraProgram {
  seq, name, category, status, aplFrom, aplTo, eduFrom, eduTo,
  organizer, mode, dday
  bool get isCurrentlyOpen
  bool get startsWithin5Days
  bool get shouldShow
  String get detailUrl
  factory ExtraProgram.fromJson(Map j)
}

### notice_repository.dart 추가
- _kExtraApiBase = 'https://extra.snu.ac.kr/ptfol/pgm/index.do'
- _kExtraCacheKey, _kExtraFetchedAtKey (TTL 30분)
- getExtraPrograms({forceRefresh}) -> List<ExtraProgram>
  * 캐시 유효하면 캐시 반환
  * 최대 5페이지 fetch, shouldShow 항목 수집
  * 페이지 내 shouldShow=0이면 조기 종료
  * 결과를 캐시 저장 후 반환
- extraProgramsProvider = FutureProvider.autoDispose

### notices_screen.dart 변경
_ExtraTab:
  - WebView 완전 제거 (WebViewController, initState 등)
  - extraProgramsProvider watch
  - loading: CircularProgressIndicator
  - error: _ErrorView
  - data(empty): "현재 신청 중이거나 곧 시작하는 프로그램이 없어요" 안내
  - data(비어있지않음): ListView of _ExtraProgramTile

_ExtraProgramTile (새 위젯):
  ExpansionTile:
    title: 프로그램명 (maxLines 2)
    subtitle: 카테고리 배지 + 상태 배지 (모집중/D-n일후시작) + D-day 배지
    children (펼침):
      - 신청기간: aplFrom ~ aplTo
      - 교육기간: eduFrom ~ eduTo
      - 주관기관, 운영방식
      - "신청 페이지 열기" 버튼 (url_launcher)

---

## 성공 기준
- [x] 체육교육과 공지 파싱 결과 > 0 (ScrapingException 발생 안함)
- [x] 비교과 API fetch + shouldShow 필터링 정확
- [x] ExpansionTile 세부 정보 올바른 날짜 포맷 표시
- [x] flutter analyze 경고 없음
- [x] 기존 42개 테스트 통과
