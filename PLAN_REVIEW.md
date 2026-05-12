# PLAN_REVIEW

계획 리뷰 스크립트 실행 생략:
- 현재 환경에 `~/.Codex/scripts/codex_plan_review.ps1`가 없다.

수동 검토:
- 스크린샷의 메시지는 카카오 SDK 인증 실패 경로가 실제로 발생했음을 보여준다.
- 사용자가 Kakao Developers에 `https://tom072677-lgtm.github.io`를 등록하면 카카오 지도가 정상화될 수 있다.
- 하지만 앱 안정성 측면에서는 SDK 인증 실패 시 대체 지도 제공이 더 좋다.
- Leaflet/OpenStreetMap fallback은 별도 도메인 인증 없이 지도 표시가 가능하며, 기존 `SNU_LOCATIONS` 데이터를 재사용할 수 있다.
- 기존 Kakao Mobility directions 응답의 vertexes를 Leaflet polyline으로 변환하면 길찾기 경로도 유지할 수 있다.
