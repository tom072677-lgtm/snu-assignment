# PLAN: 지도는 카카오만 사용하도록 정리

## 목표
도메인 등록이 완료된 상태에서 앱 지도 탭을 카카오 지도 전용으로 되돌린다. 카카오 SDK가 실패하면 대체 지도가 아니라 설정 오류를 표시한다.

## 가정
- `https://tom072677-lgtm.github.io` 도메인 등록 후 Kakao SDK 요청은 정상 응답한다.
- 사용자는 Leaflet/OpenStreetMap 대체 지도 품질을 원하지 않는다.
- 카카오 SDK 실패 시에는 대체 지도를 표시하지 않고 설정 문제를 명확히 보여주는 것이 맞다.

## 접근
1. Leaflet fallback 로더/지도/경로 코드를 제거한다.
   - verify: `renderFallbackMap`, Leaflet 상수/상태가 남지 않는다.
2. 카카오 SDK 로드 실패 시 카카오 설정 메시지만 표시한다.
   - verify: `renderMapTab` catch가 `showMapStatus(getKakaoMapSetupMessage())`로 끝난다.
3. 캐시 버전을 갱신한다.
   - verify: `index.html`/`sw.js` 버전이 오른다.
4. 문법 검증 후 커밋/푸시한다.
   - verify: `node --check script.js`, `node --check sw.js` 통과.

## 변경 파일
- index.html
- script.js
- sw.js
- PLAN.md
- PLAN_REVIEW.md
