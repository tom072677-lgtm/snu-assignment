계획 의도는 이해되지만, 원문이 인코딩 깨짐 상태라 세부 문구 검토에는 한계가 있습니다. 결론은 **needs revision**입니다.
System.Management.Automation.RemoteException
**1. Problems or Risks**
System.Management.Automation.RemoteException
- `selector 없이 범용 추출기` 목표가 너무 공격적입니다. 학과별 HTML 구조가 다르면 공통 휴리스틱만으로는 오탐/누락이 계속 생깁니다.
- `tr/li + 링크 + 날짜` 조건은 공지 목록에 날짜가 없거나, 날짜가 별도 컬럼/숨김 텍스트/스크립트 데이터에 있는 경우 누락됩니다.
- `MM.DD` 날짜 정렬 기준이 불명확합니다. 연도 추론 규칙이 없으면 12.31 / 01.01 근처에서 정렬이 틀어집니다.
- EUC-KR 처리는 Dio가 이미 문자열로 디코딩한 뒤에는 복구가 어렵습니다. HTML fetch는 `bytes`로 받고 charset 판별 후 직접 디코딩하는 방식이 명시되어야 합니다.
- `Notice(source=sports ...)`는 오타 또는 잘못된 source 값으로 보입니다. 도메인 모델 의미와 맞는 값인지 확인 필요합니다.
- 실제 페이지 검증을 성공 기준에 넣은 것은 좋지만, 네트워크 의존 테스트가 되면 CI/로컬 테스트가 불안정해집니다. fixture 기반 테스트가 필요합니다.
- SPA/cse fallback 기준이 모호합니다. “파싱 실패”와 “공지 없음”을 어떻게 구분할지 정해야 합니다.
System.Management.Automation.RemoteException
**2. Missing Edge Cases**
System.Management.Automation.RemoteException
- 고정 공지/상단 공지처럼 날짜가 없거나 오래된 날짜를 가진 항목.
- `javascript:goView('123')`, `onclick`, 상대경로, protocol-relative URL, query-only 링크.
- 제목 링크가 아니라 행 전체 클릭으로 상세 페이지가 열리는 구조.
- 날짜 형식: `2026. 06. 03`, `2026년 6월 3일`, `25.06.03`, `2026/06/03`, `작성일 2026-06-03`.
- 게시판 pagination 첫 페이지에 공지가 충분하지 않은 경우.
- 첨부파일/검색/로그인/메뉴 링크가 공지로 오인되는 경우.
- “공지사항”, “Notice”, “더보기”, “목록” 같은 비게시글 링크 필터링.
- HTML 안의 hidden mobile/desktop 중복 목록으로 인한 중복 추출.
- Flutter Web에서 직접 외부 학과 사이트를 fetch할 경우 CORS 문제.
System.Management.Automation.RemoteException
**3. Simpler Alternatives**
System.Management.Automation.RemoteException
- 완전 범용 파서 하나보다, **범용 파서 + 최소한의 per-department config**가 더 현실적입니다. 예: `noticeListUrl`, optional `containerSelector`, optional `excludeTextPatterns`.
- 실제 HTML fixture를 3~5개 저장해서 먼저 parser를 안정화하고, 라이브 검증은 별도 수동/통합 검증으로 분리하는 편이 안전합니다.
- 클라이언트에서 직접 scraping하기보다, 가능하다면 서버/백엔드에서 HTML을 수집·정규화하고 Flutter는 정규화된 API만 읽는 방식이 유지보수에 더 좋습니다.
- 1차 PR 범위는 econ/nursing/chem 정도로 제한하고, parser 규칙이 충분히 맞는지 본 뒤 학과를 늘리는 것이 적절합니다.
System.Management.Automation.RemoteException
**4. Overall Verdict**
System.Management.Automation.RemoteException
**Needs revision.**
System.Management.Automation.RemoteException
방향은 괜찮지만, 범용 HTML 추출기의 실패 조건, charset 처리 방식, 날짜 정규화/정렬 규칙, fixture 기반 테스트 전략이 더 구체화되어야 합니다. 특히 “selector 없이 전부 커버”는 리스크가 크므로 “기본 범용 파서 + 필요 시 얕은 설정”으로 목표를 낮추는 것을 권장합니다.
SUCCESS: The process with PID 34752 (child process of PID 8828) has been terminated.
SUCCESS: The process with PID 8828 (child process of PID 27816) has been terminated.