# PLAN: 카카오 지도 SDK 실패 원인 구체화

## 목표
모바일에서 카카오 지도 SDK가 준비되지 않을 때 네트워크 오해를 줄이고, 실제 조치해야 할 도메인/API 활성화 문제를 화면에 명확히 표시한다.

## 가정
- 사용자의 네트워크는 정상이다.
- `kakao.maps.Map` 미준비 원인은 JavaScript 키의 도메인 등록 누락 또는 카카오맵 API 비활성화일 가능성이 높다.
- 앱은 현재 접속 도메인을 보여줘야 사용자가 Kakao Developers에 정확히 등록할 수 있다.

## 접근
1. 정적 SDK 스크립트를 제거하고 `script.js`에서 동적으로 SDK를 로드한다.
   - verify: SDK 실패를 `onerror`/초기화 검증으로 앱 안에서 처리한다.
2. 실패 메시지에 현재 도메인과 Kakao Developers 설정 위치를 포함한다.
   - verify: 모바일 화면에서 등록해야 할 도메인을 볼 수 있다.
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
