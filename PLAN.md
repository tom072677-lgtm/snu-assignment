# PLAN: 시간표 탭 + 도서관 좌석 + 알림 정교화 + 홈 위젯

## 목표
서울대생이 매일 아침 앱을 열게 만드는 핵심 4가지 기능 구현.
우선순위: 구현 리스크 낮은 것부터, 서버 변경 최소화.

---

## Phase 1 — 시간표 탭

### 전략
Canvas API의 courses 엔드포인트로 수강 중인 과목 목록,
ical에서 RRULE이 있는 반복 이벤트(수업 시간)를 파싱해 주간 그리드로 표시.

### 서버 변경
- POST /api/timetable — ical URL + canvas token 받아서:
  1. Canvas API GET /courses?enrollment_state=active → 과목 목록
  2. ical 파싱 → RRULE 있는 VEVENT 추출
  3. 두 데이터 병합 반환
- ical에 RRULE 없으면 과목 목록만 반환

### 성공 기준
- Canvas API 토큰 없으면 빈 상태 표시
- 과목 목록 카드 표시
- RRULE 이벤트 있으면 주간 그리드 렌더링

---

## Phase 2 — 도서관 좌석 조회

### 전략
lib.snu.ac.kr 스크래핑, 60초 캐시.

### 서버 변경
- GET /api/library/seats — 열람실별 현황 반환

### 성공 기준
- 열람실별 남은 좌석 수 표시
- 60초마다 자동 갱신

---

## Phase 3 — 새 과제/공지 push 알림

### 전략
서버가 ical URL을 저장해 15분마다 폴링, 새 etlId 감지 시 FCM 전송.
Canvas token 있으면 공지사항도 폴링.

### 서버 변경
1. POST /api/fcm/subscribe-etl — ical URL + canvas token 저장
2. 15분 주기 루프: ical diff → 새 과제 FCM
3. Canvas 공지사항 폴링 (token 있는 경우)

### 성공 기준
- 교수 과제 등록 후 15분 내 FCM 수신
- 설정에서 ON/OFF 가능

---

## Phase 4 — 홈 화면 위젯

### 전략
home_widget 패키지 + Android AppWidgetProvider.
다음 과제 2개 + 오늘 수업 표시.

### 성공 기준
- 홈 화면에 위젯 추가 가능
- 과제 갱신 시 위젯도 갱신

---

## 공통 원칙
- 모든 기능: eTL 미연동 시 graceful degradation
- 서버 실패 시 빈 상태 (앱 크래시 없음)
- 도서관/시간표는 기존 탭에서 Modal Sheet로 접근 (탭 추가 X)
