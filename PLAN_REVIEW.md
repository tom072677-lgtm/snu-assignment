문서가 인코딩 깨짐 상태라 일부는 추정해서 리뷰합니다. 의도한 언어가 한국어라면 먼저 `PLAN.md`를 UTF-8로 다시 저장하는 게 좋습니다.
System.Management.Automation.RemoteException
## 1. 계획의 문제 / 리스크
System.Management.Automation.RemoteException
- **범위가 너무 큽니다.** 시간표, 도서관 좌석, push 알림, 홈 위젯은 각각 독립 기능인데 한 계획에 묶여 있어 실패 지점이 많습니다.
- **서버 저장 설계가 부족합니다.** Phase 3에서 `ical URL`, Canvas token, FCM token을 저장해야 하는데 DB 스키마, 암호화, 삭제, 구독 해제, 사용자 식별 방식이 없습니다.
- **Canvas API 세부사항이 빠져 있습니다.** `/courses?enrollment_state=active`는 pagination, 권한 실패, 만료 token, 과목명 매칭 문제를 고려해야 합니다.
- **iCal/RRULE 처리가 과소평가되어 있습니다.** timezone, `EXDATE`, `UNTIL`, `COUNT`, `RECURRENCE-ID`, 중복 이벤트, 종일 이벤트 처리가 필요합니다.
- **도서관 좌석 scraping은 깨지기 쉽습니다.** `lib.snu.ac.kr` 구조 변경, 차단, 느린 응답, 법적/정책적 허용 여부 확인이 필요합니다.
- **15분 polling 서버 루프는 운영 리스크가 큽니다.** 사용자 수가 늘면 iCal/Canvas 호출량, 중복 알림, 실패 재시도, rate limit 문제가 생깁니다.
- **홈 위젯은 Android만 명시되어 있습니다.** iOS 지원 여부를 명확히 해야 합니다. Android만이면 계획에 명시하는 편이 좋습니다.
System.Management.Automation.RemoteException
## 2. 빠진 edge case
System.Management.Automation.RemoteException
- Canvas token 없음 / 만료 / 권한 부족 / API rate limit
- Canvas courses pagination
- iCal URL 접근 실패, 빈 calendar, malformed ICS
- RRULE timezone mismatch
- 같은 과제가 여러 번 감지되는 중복 알림
- 과제 수정/삭제 시 알림 정책
- FCM token 갱신, 앱 삭제 후 stale token 정리
- 사용자가 알림 OFF 했을 때 서버 polling/저장 데이터 처리
- 도서관 좌석 페이지 응답 지연, 구조 변경, 좌석 수 `0`, 휴관일
- 위젯 데이터가 오래된 경우 표시 방식
- 네트워크 실패 시 UI empty/error/loading 구분
System.Management.Automation.RemoteException
## 3. 더 단순한 대안
System.Management.Automation.RemoteException
- **Phase를 더 작게 쪼개는 게 좋습니다.**
  1. 시간표 조회만 구현
  2. iCal parsing 안정화
  3. 도서관 좌석 조회
  4. push 알림
  5. 홈 위젯
System.Management.Automation.RemoteException
- **Phase 1은 서버 없이 시작할 수 있습니다.** 가능하다면 Flutter에서 iCal URL을 직접 fetch/parse하고, Canvas API만 서버 proxy가 필요한지 검토하세요.
System.Management.Automation.RemoteException
- **Phase 3은 처음부터 15분 polling하지 말고 앱 실행 시 diff부터 구현**하는 게 더 안전합니다. 중복 감지 로직이 안정된 뒤 서버 scheduled job + FCM으로 확장하는 편이 낫습니다.
System.Management.Automation.RemoteException
- **Canvas 공지사항 알림은 후순위가 좋습니다.** 과제 iCal diff만 먼저 만들고, Canvas announcements는 별도 Phase로 분리하는 게 단순합니다.
System.Management.Automation.RemoteException
## 4. 종합 verdict
System.Management.Automation.RemoteException
**needs revision**
System.Management.Automation.RemoteException
기능 방향은 명확하지만, 현재 계획은 구현 범위가 크고 서버 저장/보안/중복 알림/iCal edge case가 부족합니다. 먼저 인코딩을 복구한 뒤, Phase 1을 “시간표 조회 + iCal parsing”으로 좁히고, Phase 3의 push 알림은 별도 상세 설계로 분리하는 것을 권장합니다.
문서가 인코딩 깨짐 상태라 일부는 추정해서 리뷰합니다. 의도한 언어가 한국어라면 먼저 `PLAN.md`를 UTF-8로 다시 저장하는 게 좋습니다.

## 1. 계획의 문제 / 리스크

- **범위가 너무 큽니다.** 시간표, 도서관 좌석, push 알림, 홈 위젯은 각각 독립 기능인데 한 계획에 묶여 있어 실패 지점이 많습니다.
- **서버 저장 설계가 부족합니다.** Phase 3에서 `ical URL`, Canvas token, FCM token을 저장해야 하는데 DB 스키마, 암호화, 삭제, 구독 해제, 사용자 식별 방식이 없습니다.
- **Canvas API 세부사항이 빠져 있습니다.** `/courses?enrollment_state=active`는 pagination, 권한 실패, 만료 token, 과목명 매칭 문제를 고려해야 합니다.
- **iCal/RRULE 처리가 과소평가되어 있습니다.** timezone, `EXDATE`, `UNTIL`, `COUNT`, `RECURRENCE-ID`, 중복 이벤트, 종일 이벤트 처리가 필요합니다.
- **도서관 좌석 scraping은 깨지기 쉽습니다.** `lib.snu.ac.kr` 구조 변경, 차단, 느린 응답, 법적/정책적 허용 여부 확인이 필요합니다.
- **15분 polling 서버 루프는 운영 리스크가 큽니다.** 사용자 수가 늘면 iCal/Canvas 호출량, 중복 알림, 실패 재시도, rate limit 문제가 생깁니다.
- **홈 위젯은 Android만 명시되어 있습니다.** iOS 지원 여부를 명확히 해야 합니다. Android만이면 계획에 명시하는 편이 좋습니다.

## 2. 빠진 edge case

- Canvas token 없음 / 만료 / 권한 부족 / API rate limit
- Canvas courses pagination
- iCal URL 접근 실패, 빈 calendar, malformed ICS
- RRULE timezone mismatch
- 같은 과제가 여러 번 감지되는 중복 알림
- 과제 수정/삭제 시 알림 정책
- FCM token 갱신, 앱 삭제 후 stale token 정리
- 사용자가 알림 OFF 했을 때 서버 polling/저장 데이터 처리
- 도서관 좌석 페이지 응답 지연, 구조 변경, 좌석 수 `0`, 휴관일
- 위젯 데이터가 오래된 경우 표시 방식
- 네트워크 실패 시 UI empty/error/loading 구분

## 3. 더 단순한 대안

- **Phase를 더 작게 쪼개는 게 좋습니다.**
  1. 시간표 조회만 구현
  2. iCal parsing 안정화
  3. 도서관 좌석 조회
  4. push 알림
  5. 홈 위젯

- **Phase 1은 서버 없이 시작할 수 있습니다.** 가능하다면 Flutter에서 iCal URL을 직접 fetch/parse하고, Canvas API만 서버 proxy가 필요한지 검토하세요.

- **Phase 3은 처음부터 15분 polling하지 말고 앱 실행 시 diff부터 구현**하는 게 더 안전합니다. 중복 감지 로직이 안정된 뒤 서버 scheduled job + FCM으로 확장하는 편이 낫습니다.

- **Canvas 공지사항 알림은 후순위가 좋습니다.** 과제 iCal diff만 먼저 만들고, Canvas announcements는 별도 Phase로 분리하는 게 단순합니다.

## 4. 종합 verdict

**needs revision**

기능 방향은 명확하지만, 현재 계획은 구현 범위가 크고 서버 저장/보안/중복 알림/iCal edge case가 부족합니다. 먼저 인코딩을 복구한 뒤, Phase 1을 “시간표 조회 + iCal parsing”으로 좁히고, Phase 3의 push 알림은 별도 상세 설계로 분리하는 것을 권장합니다.