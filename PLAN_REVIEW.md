# PLAN_REVIEW

계획 리뷰 스크립트를 실행하려 했으나 현재 환경에 `~/.Codex/scripts/codex_plan_review.ps1` 또는 `~/.codex/scripts/codex_plan_review.ps1`가 없어 실행할 수 없었다.

수동 검토 결과:
- 변경 범위는 `script.js`의 식당 좌표 매칭으로 제한하는 것이 적절하다.
- 기존 인앱 카카오 경로 표시 로직은 유지한다.
- 누락 원인은 `SNU_LOCATIONS`의 `restId` 부족과 SNUCO 식당명 변형 매칭 부족으로 보인다.
- 좌표를 새로 크게 늘리기보다, 기존 대표 위치와 별칭 매칭을 우선 사용한다.

구현 전 확인:
- `boodang`은 고정 식당 목록에 있으나 지도 위치의 `restId` 연결이 없다.
- SNUCO 세부 식당은 이름이 `220동`, `학생회관`, `자하연`, `두레`, `공대`, `예술계`, `감골` 등으로 변형될 수 있다.
