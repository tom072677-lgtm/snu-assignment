관련 파일 구조와 기존 패턴을 먼저 확인한 뒤, 계획 자체의 리스크 중심으로 피드백하겠습니다. 코드는 변경하지 않고 검토만 합니다.
`rg`가 설치되어 있지 않아 PowerShell 검색으로 대체합니다. 현재 작업트리에는 이미 여러 변경 파일이 있으므로, 검토 과정에서는 건드리지 않겠습니다.
기존 구조상 공지 저장소가 `SharedPreferences` 캐시와 Riverpod provider를 이미 갖고 있고, 비교과 탭은 현재 WebView 전용입니다. 이제 계획의 설계상 빠진 부분과 단순화 여지를 정리하겠습니다.
## 1. 계획의 문제 / 리스크
System.Management.Automation.RemoteException
- **계획 문서 인코딩이 깨져 있습니다.** 실제 구현 전에 `PLAN.md`, UI 문구, 주석의 한글 인코딩을 먼저 정상화해야 합니다. 지금 상태로는 버튼/빈 상태 메시지/카테고리 문구를 잘못 옮길 위험이 큽니다.
- **체육교육과 공지 `id = hashCode`는 부적절합니다.** Dart `hashCode`는 영속 ID로 보장되지 않습니다. 캐시/리스트 안정성을 위해 `title + dateText + category`를 정규화한 문자열, 또는 `sha1` 같은 안정 해시를 쓰는 편이 낫습니다.
- **체육교육과 URL을 전부 `_kSportsUrl`로 두면 상세 이동 품질이 떨어집니다.** 링크가 `#none`이라도 `onclick`, `data-*`, 숨은 input 등에 상세 식별자가 있는지 먼저 확인해야 합니다. 정말 없을 때만 목록 URL fallback으로 두는 것이 안전합니다.
- **`ul.body li` selector가 넓습니다.** `ul.board_type_list > ul.body > li`처럼 더 좁혀야 다른 중첩 `li`가 섞일 가능성을 줄일 수 있습니다.
- **비교과 조기 종료 조건이 위험합니다.** “페이지 내 `shouldShow`가 0개면 중단”은 정렬이 완전히 날짜/모집상태 기준이라는 보장이 있을 때만 안전합니다. 이후 페이지에 표시 대상이 있을 수 있습니다.
- **`startsWithin5Days`의 `inDays <= 5`는 시간 단위 floor 때문에 애매합니다.** 5일 23시간 뒤도 `5`로 계산될 수 있습니다. “한국 날짜 기준 5일 이내”인지 “정확히 120시간 이내”인지 명확히 해야 합니다.
- **성공 기준이 이미 `[x]`로 체크되어 있습니다.** 구현 전 계획이라면 `[ ]`가 맞습니다. 체크된 상태는 실제 검증 완료처럼 보입니다.
System.Management.Automation.RemoteException
## 2. 빠진 엣지 케이스
System.Management.Automation.RemoteException
- 체육교육과 공지에서 `strong` 없이 제목만 있는 경우, 공지 고정글의 번호가 `em`/텍스트 혼합인 경우.
- 날짜가 `2026.03.04`, `2026-3-4`, 공백 포함, 또는 없는 경우.
- 비교과 API 응답이 `Map`인지 `String`인지, 리스트 필드명이 무엇인지, `totalCnt`가 문자열인지 숫자인지.
- `aplFrDd`, `aplToDd` 중 하나가 비어 있는 프로그램.
- `aplToDd`가 오늘인 경우 end-of-day 포함 처리.
- 모집 시작일이 오늘이지만 현재 시간이 시작 전/후인 경우.
- API가 빈 리스트를 반환했지만 기존 캐시가 있는 경우 캐시 fallback 여부.
- 상세 URL 열기 실패 시 사용자 피드백.
- `autoDispose` provider가 탭 전환 시 다시 fetch하는 동작이 의도한 것인지.
System.Management.Automation.RemoteException
## 3. 더 단순한 대안
System.Management.Automation.RemoteException
- `ExtraProgram`에 `isCurrentlyOpen`, `startsWithin5Days` getter를 넣기보다, 처음에는 repository 안의 순수 함수로 필터링하는 편이 테스트하기 쉽습니다.
System.Management.Automation.RemoteException
```dart
bool shouldShowProgram(ExtraProgram p, DateTime now)
```
System.Management.Automation.RemoteException
- 비교과 페이지 fetch는 조기 종료하지 말고 **최대 5페이지를 항상 fetch 후 filter**가 더 단순하고 안전합니다. 네트워크 비용도 제한되어 있습니다.
- 체육교육과 parser는 기존 `Notice` 모델을 유지하되 selector만 바꾸는 것이 적절합니다. 별도 모델 추가는 비교과에만 한정하면 됩니다.
- 비교과 cache TTL은 기존 sports TTL 상수를 공유하지 말고 `_kExtraCacheTtlSeconds`로 분리하는 편이 변경 범위가 명확합니다.
System.Management.Automation.RemoteException
## 4. 전체 판정
System.Management.Automation.RemoteException
**수정 필요.**
System.Management.Automation.RemoteException
방향은 좋지만, 구현 전에 최소한 다음은 고쳐야 합니다: 한글 인코딩 복구, 안정적인 ID 생성, 비교과 조기 종료 로직 제거 또는 근거 명시, 날짜 기준 명확화, API 응답 shape 방어, 성공 기준 체크박스 초기화. 이 수정 후에는 구현 가능한 계획입니다.
SUCCESS: The process with PID 19076 (child process of PID 10724) has been terminated.
SUCCESS: The process with PID 10724 (child process of PID 7460) has been terminated.