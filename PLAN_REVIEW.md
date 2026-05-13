# PLAN_REVIEW

계획 리뷰 스크립트 실행 생략:
- 현재 환경에 `~/.Codex/scripts/codex_plan_review.ps1`가 없다.

수동 검토:
- 화살표를 숨기지 않는 것이 사용자 요구다.
- 센서값을 즉시 반영하지 말고 deadband/throttle/smoothing을 적용하는 방식이 적절하다.
- heading은 0/360도 경계가 있으므로 일반 평균이 아니라 원형 보간이 필요하다.
