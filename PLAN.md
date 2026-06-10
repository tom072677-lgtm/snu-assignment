# PLAN — 과제 마감 ongoing 알림 실시간 카운트다운 (백그라운드)

## 무엇 / 왜
24시간 이내 마감 과제의 ongoing 알림이 **백그라운드/앱 종료 시 실시간으로 카운트다운되지 않는다**. 목표: 알림 바에 뜬 마감 임박 알림이 **앱을 닫아도 24h→0으로 실시간 틱**하고, 가능한 한 안 지워지게 해서 사용자가 제출을 까먹지 않게 한다.

## 현재 상태 (조사 결과)
- `notification_service.dart`의 `showOngoingNotification()`: `ongoing:true` + 💣 + 텍스트 진행바 + "X시간 Y분 후 마감"(정적 텍스트).
- 갱신: 포그라운드 `BombCountdownBanner`의 1분 타이머만. 앱 닫히면 멈춤.
- `handleBackgroundFcm`: `announcement`/`new_assignment`만 처리, **`deadline` 미처리**.
- 권한 선언 완료: SCHEDULE_EXACT_ALARM, USE_EXACT_ALARM, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED.
- urgent 판정: `assignments_screen`에서 `remaining.inHours < 24` 미완료·미만료 과제.

## 핵심 한계 (정직 — 사용자 통보 완료)
1. Android 14+(API34)는 ongoing 알림도 스와이프 가능 → "절대 안 지워짐"은 13 이하만 보장.
2. 알림에 움직이는 폭탄 애니메이션 불가 → 💣 + 실시간 HH:MM:SS(시스템 chronometer)로 대체. 인앱 배너는 유지.
3. OEM 배터리 최적화로 예약 지연 가능.

## 접근

### 1. 시스템 Chronometer로 실시간 카운트다운
`showOngoingNotification()`의 `AndroidNotificationDetails`에 추가:
- `when: <마감 epoch ms>`
- `usesChronometer: true`
- `chronometerCountDown: true`
- `timeoutAfter: <남은 ms>` (마감 시 자동 제거)
→ OS가 초 단위로 카운트다운을 직접 갱신(앱 불필요). 정적 텍스트 진행바는 보조로 유지하되, 실시간성은 chronometer가 담당.
- `flutter_local_notifications ^17.2.2`가 `when`/`usesChronometer`/`chronometerCountDown` 지원하는지 구현 시 확인.

### 2. zonedSchedule로 마감 24h 전 자동 출현
앱이 안 떠 있어도 알림이 뜨도록:
- 과제 목록 로드/갱신 시, 각 미완료 과제에 대해 **(마감−24h) 시각에** ongoing 알림을 `zonedSchedule`로 예약.
- 이미 24h 이내면 즉시 `show`.
- 완료/삭제/마감 시 해당 예약 취소.
- `zonedSchedule`는 `timezone` 패키지 + `tz.initializeTimeZones()` + 로컬 타임존 설정 필요 → 의존성·초기화 확인(없으면 추가).
- `AndroidScheduleMode.exactAllowWhileIdle` 사용(권한 이미 있음). Android 12+ 런타임에 exact alarm 허용 여부 확인 후 미허용 시 inexact로 폴백.

### 3. 백그라운드 FCM `deadline` 처리 추가 (보조 경로)
`handleBackgroundFcm`에 `deadline` 분기 추가 → 서버가 백그라운드로도 ongoing 알림 생성/갱신 가능(예약 실패 대비 안전망).

### 4. 스케줄 갱신 트리거
과제 목록이 바뀔 때(앱 시작/새로고침/완료 토글) 예약을 재동기화: 현재 urgent/예정 과제에 대해 schedule, 사라진 건 cancel. `BombCountdownBanner._update` 또는 repository 동기화 지점에 연결.

## 변경 파일(예상)
1. `lib/shared/providers/notification_service.dart` — chronometer 필드, `scheduleDeadlineNotification()`(zonedSchedule), `handleBackgroundFcm`의 deadline 분기, tz 초기화.
2. `lib/main.dart` — tz 초기화 1회(필요 시).
3. `pubspec.yaml` — `timezone`(미보유 시) 추가.
4. 예약 동기화 호출 지점(assignments_screen / banner / repository) — 최소 침습.

## 성공 기준
1. `flutter analyze` 무경고 + 빌드 성공. (verify: analyze / build apk)
2. 기기: 24h 이내 과제 알림이 **앱을 백그라운드로 보내거나 recents에서 스와이프한 상태에서도 초 단위로 카운트다운**. ⚠️ **설정→강제중지(force-stop) 시에는 OS가 알람·FCM·핸들러를 모두 차단하므로 보장하지 않음**(스펙 — 사용자 통보). (verify: 실기기 — 앱 닫고 알림 관찰)
3. 기기(Android ≤13): 알림 스와이프 시 안 지워짐. Android 14+: 스와이프 가능(스펙). (verify: 실기기)
4. 마감/완료 시 알림 자동 제거. (verify: 실기기)
5. exact alarm 권한 미허용 시 inexact로 폴백(크래시 X) + 로그. (verify: analyze/코드)
6. 기존 알림(공지·새 과제·heads-up)·기존 6탭 무손상. (verify: analyze + 기기)

## 범위 밖 (YAGNI)
- 알림 내 커스텀 애니메이션/이미지(폭탄 이동) — 불가.
- 24h보다 이른 시점의 추가 리마인더.
- iOS(앱은 Android 전용).

## 리뷰 반영 결정사항 (v2 — Codex 피드백 후 확정)
- **보장 범위:** 정상 백그라운드/종료·recents 스와이프까지 실시간 카운트다운. **force-stop은 보장 불가**(OS 제약, 성공기준에 명시).
- **채널:** 신규 생성 X. 기존 `sharap_ongoing`(importance high) 재사용, 갱신은 low importance로 무음.
- **chronometer 필드:** Codex가 `when`/`usesChronometer`/`chronometerCountDown`/`timeoutAfter` 존재 확인. **구현 시 17.2.2로 실제 컴파일 확인 필수**(없거나 시그니처 다르면 분 단위 텍스트 폴백).
- **exact alarm 폴백:** `exactAllowWhileIdle` 시도 → 권한 없음/실패 시 `inexactAllowWhileIdle`로 폴백 + debugPrint(규칙11). 크래시 금지.
- **다중 과제:** 과제별 ongoing 1개씩(기존 `syncUrgentNotifications` 동작 유지). 그룹화는 범위 밖.
- **background isolate:** deadline 처리 시 `show`(+`when` chronometer)만 사용 → **tz 불필요**. `zonedSchedule`(tz 필요)는 **포그라운드 전용**. tz 초기화는 main에서 1회(zonedSchedule용).
- **deadline FCM = data-only** 전제(서버가 notification payload 보내면 로컬과 중복 → data-only로 받아 로컬이 단독 표시).
- **timeoutAfter:** 표시 시점 기준 남은 ms로 계산(예약분은 발화 시점에 ~24h). 이미 마감 지난 과제는 schedule/show 모두 skip + 기존 예약 cancel.

## 추가 엣지 케이스 (반영)
- 이미 마감 지난 과제: skip + cancel.
- 마감 시각 변경: stable id로 cancel 후 재예약.
- 완료/삭제가 타 기기·서버에서 발생 + 앱 죽어있던 경우: 다음 앱 실행 시 `syncUrgentNotifications`의 "사라진 id cancel" 로직으로 정리.
- 재부팅·timezone·DST·수동 시간 변경: 부팅 후 자동 재예약에 의존하지 않고 **앱 실행 시 전체 재예약**.
- POST_NOTIFICATIONS 거부: skip + 로그(크래시·강제요청 X).
- FCM payload 중복: deadline은 data-only로만 처리.
