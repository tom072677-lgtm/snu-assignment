## 1. 계획의 문제/리스크
System.Management.Automation.RemoteException
- 계획서 텍스트 인코딩이 깨져 있어 리뷰와 구현 기준으로 쓰기 어렵습니다. 구현 전 `PLAN.md`를 정상 한글 UTF-8로 다시 저장하는 게 먼저입니다.
- `unsupported` 상태 모델이 불명확합니다. `noticeSourceFor`가 `null`을 반환하는 경우와 `homepageUrl만 있고 rssFeedUrl이 null`인 경우를 명확히 분리해야 합니다.
- “RSS 존재 + 최신 글 1건 확인”만으로 등록한다는 기준은 약합니다. RSS가 공지 전체가 아니라 블로그/뉴스/게시판 일부일 수 있으므로 최소 `title/link/date` 형태와 최근 공지 일치 여부를 확인해야 합니다.
- `package:html unescape` 계획은 애매합니다. XML 파싱은 `xml` 패키지로 하고, HTML entity decode가 실제로 필요한 지점만 별도 처리하는 쪽이 안전합니다.
- 기존 `sportsNoticesProvider`를 일반화할 때 기존 체육교육과 동작이 깨질 위험이 큽니다. 기존 provider/API를 유지하면서 새 provider를 추가하는 방식이 더 안전할 수 있습니다.
- on-device fetch는 모바일에서는 괜찮아도 Flutter web 대상이면 CORS 문제가 생길 수 있습니다. 앱 타깃이 모바일 전용인지 명시해야 합니다.
System.Management.Automation.RemoteException
## 2. 빠진 엣지 케이스
System.Management.Automation.RemoteException
- RSS가 아니라 Atom feed인 경우.
- WordPress feed가 `/feed/` 외에 `/category/notice/feed/`, `/notice/feed/`처럼 다른 경로를 쓰는 경우.
- `pubDate` 대신 `dc:date`, `updated`, `published`가 있는 경우.
- `link`가 상대경로인 경우.
- 같은 공지가 http/https, trailing slash, query parameter 차이로 중복되는 경우.
- feed item이 너무 많거나 너무 오래된 경우의 limit 기준.
- 캐시된 데이터가 현재 선택한 학과와 다른 학과로 표시되는 race condition.
- `deptCode`는 있는데 `snu_departments.dart`에서 이름 lookup이 실패하는 경우.
- `homepageUrl` launch 실패 시 UI 처리.
- 네트워크 실패와 RSS 파싱 실패를 같은 “지원 안 함”으로 보이면 사용자가 오해할 수 있음.
System.Management.Automation.RemoteException
## 3. 더 단순한 대안
System.Management.Automation.RemoteException
- 1단계에서는 `sportsNoticesProvider`를 완전히 일반화하지 말고, `departmentNoticesProvider(deptCode)`를 별도로 추가하는 게 더 작고 안전합니다.
- `DepartmentNoticeSource`에 별도 unsupported flag를 두기보다:
  - source 없음: 학과 매핑 없음
  - source 있음 + rss 없음: 홈페이지 fallback
  - source 있음 + rss 있음: RSS 시도
  정도로 단순화하면 충분합니다.
- RSS 파서 테스트를 먼저 작게 만들고, 실제 학과 매핑은 검증된 소수 학과만 넣는 게 좋습니다. 1단계에서 80개 가까운 매핑을 한 번에 넣으면 유지보수와 검증 부담이 커집니다.
System.Management.Automation.RemoteException
## 4. 총평
System.Management.Automation.RemoteException
**needs revision**
System.Management.Automation.RemoteException
방향은 좋습니다. 다만 구현 전에 정상 인코딩으로 계획서를 고치고, 상태 모델(`null`, fallback, fetch 실패, unsupported)을 명확히 해야 합니다. 특히 기존 sports 공지 흐름을 크게 건드리지 않는 더 작은 변경으로 시작하는 편이 안전합니다.
SUCCESS: The process with PID 27152 (child process of PID 24136) has been terminated.
SUCCESS: The process with PID 24136 (child process of PID 8480) has been terminated.
## 1. 계획의 문제/리스크

- 계획서 텍스트 인코딩이 깨져 있어 리뷰와 구현 기준으로 쓰기 어렵습니다. 구현 전 `PLAN.md`를 정상 한글 UTF-8로 다시 저장하는 게 먼저입니다.
- `unsupported` 상태 모델이 불명확합니다. `noticeSourceFor`가 `null`을 반환하는 경우와 `homepageUrl만 있고 rssFeedUrl이 null`인 경우를 명확히 분리해야 합니다.
- “RSS 존재 + 최신 글 1건 확인”만으로 등록한다는 기준은 약합니다. RSS가 공지 전체가 아니라 블로그/뉴스/게시판 일부일 수 있으므로 최소 `title/link/date` 형태와 최근 공지 일치 여부를 확인해야 합니다.
- `package:html unescape` 계획은 애매합니다. XML 파싱은 `xml` 패키지로 하고, HTML entity decode가 실제로 필요한 지점만 별도 처리하는 쪽이 안전합니다.
- 기존 `sportsNoticesProvider`를 일반화할 때 기존 체육교육과 동작이 깨질 위험이 큽니다. 기존 provider/API를 유지하면서 새 provider를 추가하는 방식이 더 안전할 수 있습니다.
- on-device fetch는 모바일에서는 괜찮아도 Flutter web 대상이면 CORS 문제가 생길 수 있습니다. 앱 타깃이 모바일 전용인지 명시해야 합니다.

## 2. 빠진 엣지 케이스

- RSS가 아니라 Atom feed인 경우.
- WordPress feed가 `/feed/` 외에 `/category/notice/feed/`, `/notice/feed/`처럼 다른 경로를 쓰는 경우.
- `pubDate` 대신 `dc:date`, `updated`, `published`가 있는 경우.
- `link`가 상대경로인 경우.
- 같은 공지가 http/https, trailing slash, query parameter 차이로 중복되는 경우.
- feed item이 너무 많거나 너무 오래된 경우의 limit 기준.
- 캐시된 데이터가 현재 선택한 학과와 다른 학과로 표시되는 race condition.
- `deptCode`는 있는데 `snu_departments.dart`에서 이름 lookup이 실패하는 경우.