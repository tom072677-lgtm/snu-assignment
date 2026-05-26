먼저 계획서 본문이 인코딩 깨짐 상태라 일부 항목은 추정해서 리뷰합니다.
System.Management.Automation.RemoteException
## 1. 문제 / 리스크
System.Management.Automation.RemoteException
- 범위가 너무 큽니다. 서버 알림 중복 방지, 카운트다운 UI, 다크모드 제거, 지도 UX, 장소 마커까지 한 번에 묶여 있어 리뷰와 검증이 어려워집니다. 최소 2~3개 PR로 나누는 편이 안전합니다.
- `sentKeys`를 MongoDB TTL 컬렉션으로 옮기는 계획은 방향은 맞지만, **atomic upsert + unique index**가 명시되어야 합니다. 단순 저장/조회 방식이면 서버 재시작 문제는 해결해도 동시 실행 중복 발송은 남습니다.
- `syncTasksForNotification`을 `assignmentsProvider` 로드 후 자동 호출하는 방식은 rebuild마다 API가 반복 호출될 위험이 있습니다. idempotent 처리, debounce, “이미 동기화한 과제” 기준이 필요합니다.
- `NOverlayImage.fromWidget`로 500개 마커를 만들면 성능 리스크가 큽니다. 카테고리별 아이콘은 캐싱하거나 asset 기반으로 가는 게 더 안전합니다.
- `_applyVenueFilter`가 async라면 빠르게 칩을 바꿀 때 이전 마커 추가 작업이 뒤늦게 완료되어 잘못된 마커가 남을 수 있습니다. request sequence/cancel guard가 필요합니다.
- `DraggableScrollableSheet`와 `NaverMap` 제스처 충돌 가능성이 있습니다. 지도 pan/zoom, sheet drag, route panel 전환, back 버튼 동작을 따로 정의해야 합니다.
- 다크모드 제거는 단순 코드 삭제처럼 보이지만 persisted setting, provider 의존성, system UI overlay style까지 확인해야 합니다.
System.Management.Automation.RemoteException
## 2. 빠진 엣지 케이스
System.Management.Automation.RemoteException
- 과제 deadline timezone / 서버-클라이언트 시간 차이 / 이미 지난 과제 / 완료된 과제 / deadline이 null인 과제.
- 앱이 background에 있다가 resume될 때 카운트다운 타이머 갱신.
- 24시간 경계값: 정확히 24h, 0h, overdue 상태.
- venuesProvider가 loading/error일 때 칩을 눌렀을 때의 동작.
- 지도 컨트롤러가 아직 준비되지 않았을 때 `_applyVenueFilter`, `_showVenueDetail` 호출.
- venue lat/lng가 null, 0, invalid인 데이터.
- 마커 추가 중 화면 dispose 되었을 때 `setState`/overlay 호출 방지.
- 선택된 venue가 필터 변경으로 사라졌을 때 detail sheet 닫기 여부.
- route panel 진입 시 기존 `_selectedPlace`, `_selectedVenue`, `_sheetMode` 상태 정리.
- 500개 cap 기준: “현재 카메라 중심”을 언제 읽는지, 카메라 중심을 못 읽으면 fallback은 무엇인지.
System.Management.Automation.RemoteException
## 3. 더 단순한 대안
System.Management.Automation.RemoteException
- 첫 구현은 `NOverlayImage.fromAssetImage` 또는 기본 마커로 시작하세요. 커스텀 widget marker는 후순위가 낫습니다.
- restaurant 800개는 “nearest 500”보다 우선 “최대 500개까지만 표시 + 안내 메시지”로 시작해도 됩니다. 거리 정렬은 카메라 중심 API 확인 후 추가하는 게 안전합니다.
- 지도 UX 개선, 알림/카운트다운, 다크모드 제거는 분리하는 편이 좋습니다. 특히 지도 마커 기능만 먼저 완성하면 성공 기준이 훨씬 명확합니다.
- 카운트다운 배너는 `Timer.periodic`보다 deadline 기준으로 남은 시간을 계산하고, lifecycle resume 시 재계산하는 구조가 단순하고 정확합니다.
System.Management.Automation.RemoteException
## 4. Verdict
System.Management.Automation.RemoteException
**needs revision**
System.Management.Automation.RemoteException
방향은 괜찮지만 현재 계획은 범위가 넓고, async marker 처리와 알림 중복 방지 쪽의 핵심 안정성 조건이 부족합니다. 구현 전에 PR 범위를 나누고, MongoDB unique upsert, provider sync idempotency, marker async race 방지, map lifecycle edge case를 계획에 추가하는 게 필요합니다.
SUCCESS: The process with PID 7468 (child process of PID 44240) has been terminated.
SUCCESS: The process with PID 44240 (child process of PID 1500) has been terminated.