# 혜택·기회 탭 (Opportunities) 설계 문서

- 작성일: 2026-06-15
- 대상 저장소: `sharap-flutter` (SNU 학생 앱, monorepo: Flutter `lib/` + Render Node 서버 `server/`)
- 상태: 설계 승인 완료, 구현 계획 작성 전

---

## 1. 개요 / 목표

대학생이 받을 수 있는 **공모전·대외활동·장학금·무료교육·인턴/채용** 기회를 한 곳에 모아 폰에서 틈날 때마다 훑어보고, **마감을 놓치지 않으며**, 신청 과정의 **함정(돈·권리 손실)** 을 피하도록 돕는 기능. sharap 앱에 **새 탭("혜택·기회")** 으로 추가한다.

**v1 범위 확정:** 5개 카테고리(공모전·대외활동·장학금·교육·인턴) 전부를 v1에 포함한다. 개인화 입력(F1)은 **sharap 기존 온보딩에 1스텝으로 통합**한다(별도 설정 화면 아님).

배포 경로: **우선 개인용 → 품질이 좋으면 구글플레이 공개 배포.** 따라서 합법성·유지보수성이 공개 배포 시점까지 이어지도록 설계한다.

### 성공 기준 (verify)
1. 혜택 탭에서 5개 카테고리의 실제 기회 목록을 마감일 순으로 본다.
2. 관심 분야/지역 설정으로 개인화 필터가 동작한다.
3. ⭐ 스크랩한 항목이 마감 D-3/D-1에 로컬 푸시로 알림 온다.
4. 장학금/공모전 화면에 함정 경고가 노출된다.
5. data.go.kr/온통청년 인증키가 APK에 포함되지 않는다(서버에만 존재).

## 2. 비목표 (YAGNI / 명시적 제외)

- 회원/로그인, 클라우드 동기화(스크랩은 기기 로컬에만).
- AI 추천·맞춤 글쓰기·자소서 기능.
- 교내 비교과 통합시스템 로그인 연동(학교마다 인증 상이 → v1 제외).
- 서버 FCM 글로벌 알림(추후 선택). v1 알림은 **로컬 알림만**.
- 카테고리별 별도 모델 클래스 5종(대신 공통 모델 + `extra` Map).

## 3. 아키텍처

```
Render 서버 (server/)
  기존: 학과 공지 스크래핑(deptNotices.js)
  추가: GET /api/opportunities
    ├─ [합법 코어] data.go.kr 장학(15028252)
    ├─ [합법 코어] 온통청년 청년정책 API(15143273)
    ├─ [합법 코어] 고용24 내일배움카드 훈련과정 API(15109032)
    └─ [격리 모듈] 공모전 스크래핑(cheerio) — server/opportunities/contests.js
    → 통일 스키마 정규화 + 마감 지난 항목 제거 + dedup + 캐시
        │ JSON
        ▼
Flutter 앱 (lib/features/opportunities/)
  data/    OpportunityRepository (dio) + 로컬 저장(shared_preferences)
  domain/  Opportunity 모델, OppCategory enum, 필터 설정
  present. 혜택 탭 → 카테고리 칩+검색 → 카드 리스트 → 상세 → 스크랩
  알림     flutter_local_notifications (스크랩 마감 D-3/D-1 예약)
```

### 핵심 결정
- **집계는 서버에서.** 이유: (1) 공식 API 인증키를 APK에 넣으면 유출 → 서버 보관 필수, (2) 정규화·dedup·마감필터·캐시·스크래핑은 서버 책임(기존 `_server` 패턴 재사용).
- **마감 알림은 로컬 푸시.** 스크랩 목록은 개인정보 → 서버에 보내지 않음. `flutter_local_notifications`(기설치)로 기기에서 예약. 프라이버시·안정성 확보.
- **공모전 스크래핑은 단일 파일로 격리.** 공개 배포 직전 이 모듈만 끄거나 합법 소스로 교체(기술부채 봉인).

## 4. 데이터 소스 (검증 완료)

| 카테고리 | 소스 | 합법성 | 비고 |
|---|---|---|---|
| 장학금 | [data.go.kr 한국장학재단 학자금지원정보(대학생) #15028252](https://www.data.go.kr/data/15028252/fileData.do) | 공식 오픈데이터 | 국가+지자체+민간+대학 통합. 3단계↑ 파일은 자동 API 제공 |
| 청년정책/일경험 | [온통청년 청년정책 OpenAPI #15143273](https://www.data.go.kr/data/15143273/openapi.do) | 공식 오픈API | 인증키 필요(서버 보관), XML |
| 무료교육(KDT) | [고용24 내일배움카드 훈련과정 OpenAPI #15109032](https://www.data.go.kr/data/15109032/openapi.do) | 공식 오픈API | 인증키 필요 |
| 공모전·대외활동 | 위비티 등 스크래핑(격리 모듈) | 회색지대(개인용 한정) | 공개 배포 전 정리 필요 |

> 구현 착수 시 각 API의 **실제 응답 필드를 직접 호출해 확인**(전역 규칙 9). 인증키는 서버 환경변수로 관리.

## 5. 데이터 모델

```dart
enum OppCategory { contest, activity, scholarship, education, intern }

class Opportunity {
  final String id;            // 안정 해시: hash(source + sourceId/url)
  final OppCategory category;
  final String title;
  final String organization;  // 주최/주관
  final String url;           // 항상 원출처 링크
  final String source;        // 'data.go.kr' | '온통청년' | '고용24' | '위비티' ...
  final DateTime? deadline;
  final DateTime? startDate;
  final String? region;
  final List<String> tags;
  final String? summary;
  final Map<String, String> extra; // 카테고리별 가변 필드(라벨:값)
  //  scholarship: amount, scholarshipType, eligibility
  //  contest:     prize, field, target
  //  education:   period, cost, capacity
  //  intern:      workplace, pay, term
}
```

- **`extra` Map**: 카테고리별 상이 필드를 유연 수용(클래스 폭발 방지). 화면은 존재하는 키만 렌더.
- **dedup**: `정규화(title)+organization+deadline` 해시 기준(서버).
- **마감 필터**: `deadline < 오늘`이면 서버에서 기본 제외(재탕 공고 함정 방지). 기본 정렬 = 마감 임박순.

## 6. 기능 상세

### F1. 개인화 필터/추천
- 입력: 관심 분야(IT·디자인·마케팅·기획·이공계 등), 지역(거주지), 학교/학년(선택). `shared_preferences` 저장. **sharap 기존 온보딩(`lib/features/onboarding/`)에 1스텝 추가(확정)** — 별도 설정 화면을 새로 만들지 않는다. 온보딩 무결성 검증 필수(전역 규칙 14: 기존 온보딩 스텝이 사라지지 않았는지 확인).
- 동작: 서버 전체 리스트를 앱이 설정과 매칭해 상단 정렬/필터. 끄면 전체 표시.

### F2. 스크랩 + 마감 D-day 트래커
- 카드 ⭐ → 관심 목록 저장. 상태: 관심 / 준비중 / 지원완료.
- 스크랩 화면: 마감일 순 + D-day 뱃지, 마감 지난 항목 자동 아카이브.
- 저장: `shared_preferences`(JSON). 서버 미전송.

### F3. 마감 임박 로컬 푸시
- 스크랩 시 해당 항목 마감 D-3, D-1에 로컬 알림 예약(`flutter_local_notifications`).
- 스크랩 해제 시 예약 취소. `deadline` 없는 항목은 알림 미예약.

### F4. 함정/체크리스트 안내 (앱 내장 정적 콘텐츠)
- 장학금 탭 상단 배너: 가구원 정보제공 동의·중복수혜 한도·1차 신청 권장.
- 공모전 상세 하단: 저작권 조항·참가비 경고.
- API 비의존(거의 불변 지식). 앱 업데이트로만 갱신.

## 7. 화면 / UI

레이아웃 = **컴팩트 리스트(목업 A)** 채택.

```
[혜택·기회 탭]
  상단: 제목 + 카테고리 칩(전체/공모전/장학금/교육/인턴/대외활동) + 검색
        + 함정 경고 배너(해당 카테고리)
  본문: 카드 리스트(마감임박/추천 정렬)
        카드 = [카테고리 색태그] [D-day] / 제목 ⭐ / 주최·자격 / 혜택 강조줄
   └ [상세] 제목·주최·혜택·자격·마감 + 원문 열기(url_launcher) + ⭐ + 함정 경고
  하위 탭/진입: [내 스크랩] → 상태별·마감순 관리
```

- 디자인 토큰: sharap 기존 `core/theme.dart` 준수.
- 카테고리 색: 공모전(파랑)·장학금(초록)·교육(보라) 등 일관 적용.

## 8. 에러 처리

- 서버 호출 실패: 마지막 캐시 표시 + "새로고침" + 실패 사유 `debugPrint`(전역 규칙 11).
- 개별 소스 장애: 해당 소스만 비고, 나머지는 정상 노출(서버에서 소스별 try/catch).
- 스크래핑 빈 결과: 조용한 빈 리스트 금지 → 로그에 응답 앞부분 출력(전역 규칙 13).
- 알림 권한 거부: 안내 후 앱 내 D-day 표시는 유지(알림만 비활성).

## 9. 테스트

- 서버: 각 소스 정규화 함수 단위 테스트(샘플 응답 → Opportunity), dedup·마감필터 테스트. `node` 단독 실행 점검(기존 `node server/deptNotices.js <code>` 패턴).
- 앱: Opportunity 파싱·필터·스크랩 저장/복원 단위 테스트(`flutter_test`).
- 기기 검증: `/ship`으로 설치 후 실제 목록·스크랩·로컬 알림 동작 확인("기기에서 확인됨" 기준, 전역 규칙 10).

## 10. 공개 배포 전 체크리스트 (기술부채 봉인)

- [ ] `server/opportunities/contests.js`(공모전 스크래핑) 제거 또는 합법 소스로 교체.
- [ ] 각 오픈API 활용 약관·출처 표기 요건 확인.
- [ ] 개인정보 처리방침(스크랩 로컬 저장·알림 권한) 작성.

## 11. 미해결 / 추후

- 공모전 합법 대체 소스(정부/공기업 공개 공고 RSS 등) 조사 — 공개 배포 시 필요.
- 교내 비교과 연동(로그인) — v2 후보.
- 서버 FCM "이주의 추천" 글로벌 알림 — v2 후보.
