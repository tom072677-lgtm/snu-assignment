계획 내용은 대체로 타당하지만 **needs revision**입니다. 구현 전에 몇 가지 동작 기준을 더 명확히 해야 합니다.
System.Management.Automation.RemoteException
## 1. 문제 / 리스크
System.Management.Automation.RemoteException
- `uid`와 `ev.id`가 같은 값인지 확인이 필요합니다. 계획에서는 `removeSession(String uid)`인데 `TimetableGrid`에서는 `onDeleteSession?.call(ev.id)`라고 되어 있어, `ClassSession.uid`와 렌더링 이벤트 id가 다르면 삭제가 실패하거나 잘못된 항목을 지울 수 있습니다.
System.Management.Automation.RemoteException
- `_importIcs` 성공 시에도 `capturedAt = DateTime.now()`를 기록하는 설계는 의미가 애매합니다. iCal 파일이 과거에 export된 파일이면 “방금 갱신됨”처럼 보일 수 있습니다. MySNU 캡처와 로컬 ICS import를 같은 freshness 기준으로 봐도 되는지 결정해야 합니다.
System.Management.Automation.RemoteException
- `semesterKey(DateTime.now())`를 provider 내부에서 직접 쓰면 테스트가 어려워집니다. 단위 테스트나 위젯 테스트에서는 clock 주입이 가능한 구조가 더 좋습니다. 예: `currentDateProvider`를 별도로 두고 stale provider가 그 값을 watch.
System.Management.Automation.RemoteException
- snooze가 `semesterKey(now)` 기준이라, 사용자가 학기 전환 직전/직후에 누른 경우 의도와 다르게 동작할 수 있습니다. 특히 2월 말, 8월 말, 9월 초 경계에서 확인 필요합니다.
System.Management.Automation.RemoteException
- `SharedPreferences.setString/remove`는 Future를 반환합니다. 기존 코드 스타일이 fire-and-forget이면 맞춰도 되지만, 저장 실패를 전혀 고려하지 않는다는 점은 명시된 tradeoff로 남습니다.
System.Management.Automation.RemoteException
## 2. 누락된 엣지 케이스
System.Management.Automation.RemoteException
- `DateTime.tryParse(raw)`가 실패해서 `null`이 되는 경우: 현재 stale false로 처리될 듯한데, 손상된 prefs 값을 지울지 그대로 둘지 정해야 합니다.
System.Management.Automation.RemoteException
- `removeSession`에서 같은 `uid`가 여러 개 있으면 전부 삭제됩니다. 의도한 동작인지 확인해야 합니다. 보통 같은 과목이 여러 요일/시간 블록으로 나뉘면 하나만 지울지, 같은 uid 전체를 지울지가 중요합니다.
System.Management.Automation.RemoteException
- 삭제 확인 UX가 필요합니다. 수업 블록 탭 후 바로 삭제 버튼을 누르면 복구 경로가 사실상 “MySNU 전체 갱신”뿐이므로 confirm dialog 또는 undo snackbar가 더 안전합니다.
System.Management.Automation.RemoteException
- MySNU 갱신 실패 시 `capturedAt`이 갱신되면 안 됩니다. 계획에는 “성공 후 setSessions 직후”라고 되어 있어 괜찮지만, 빈 결과/부분 실패/사용자 취소가 성공으로 처리되지 않는지 확인해야 합니다.
System.Management.Automation.RemoteException
- capturedAt이 현재 학기인데 실제 세션 목록이 이전 학기 데이터인 경우는 감지하지 못합니다. 이건 “캡처 시점 기반” 설계의 한계로 명시하면 충분합니다.
System.Management.Automation.RemoteException
## 3. 더 단순한 대안
System.Management.Automation.RemoteException
- snooze provider를 별도 provider로 두는 건 괜찮지만, capturedAt은 `MySNUSessionsNotifier.setSessions` 안에서 함께 기록하는 편이 더 단순할 수 있습니다. 그러면 `_openMySNU`, `_importIcs` 각각에서 기록을 빼먹을 위험이 줄어듭니다. 다만 ICS import와 MySNU capture를 다르게 취급하려면 현재 계획처럼 분리하는 편이 낫습니다.
System.Management.Automation.RemoteException
- `semesterKey`는 새 파일로 분리하지 않고 provider 근처 private 함수로 시작해도 됩니다. 다만 테스트를 명확히 하려면 새 domain 파일도 합리적입니다.
System.Management.Automation.RemoteException
- 개별 삭제는 별도 callback 추가보다 `TimetableGrid`가 `WidgetRef`를 받는 식으로도 가능하지만, 현재 계획의 callback 방식이 더 깔끔하고 영향 범위가 작습니다.
System.Management.Automation.RemoteException
## 4. Overall verdict
System.Management.Automation.RemoteException
**needs revision**
System.Management.Automation.RemoteException
핵심 방향은 좋습니다. 다만 구현 전에 최소한 다음 3가지는 정리해야 합니다.
System.Management.Automation.RemoteException
1. `ClassSession.uid`와 grid event id의 관계 확인  
2. ICS import도 freshness 갱신으로 볼지 결정  
3. 삭제 단위가 “블록 하나”인지 “같은 uid 전체”인지 결정  
System.Management.Automation.RemoteException
이 세 가지가 명확해지면 계획은 구현해도 괜찮습니다.
SUCCESS: The process with PID 9968 (child process of PID 20608) has been terminated.
SUCCESS: The process with PID 20608 (child process of PID 12572) has been terminated.