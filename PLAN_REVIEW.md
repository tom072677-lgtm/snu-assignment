# PLAN_REVIEW

계획 리뷰 스크립트 실행 생략:
- 이전 확인과 동일하게 `~/.Codex/scripts/codex_plan_review.ps1`가 현재 환경에 없다.

수동 검토:
- 공식 Kakao 지도 Web API 가이드는 JavaScript SDK 도메인 등록이 필요하다고 설명한다.
- Kakao Developers 문서도 JavaScript 키가 등록된 JavaScript SDK 도메인에서만 사용 가능하다고 설명한다.
- 현재 앱의 일반 네트워크 연결 문제가 아니라 SDK 인증/활성화 문제일 가능성이 높다.
- 코드에서는 정적 스크립트 로드를 동적 로더로 바꿔 실패를 사용자에게 더 구체적으로 알려주는 것이 적절하다.
