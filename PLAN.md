# PLAN: 카카오 인증 실패 시 지도 fallback 추가

## 목표
카카오 JavaScript 키 도메인 인증이 실패해도 모바일 지도 탭이 빈 화면/오류 화면에 머물지 않고 지도를 표시한다.

## 가정
- 현재 오류는 `https://tom072677-lgtm.github.io` origin이 카카오 JavaScript SDK 도메인에 없거나 카카오맵 API가 비활성화되어 발생한다.
- 사용자가 Kakao Developers 설정을 고치기 전에도 앱 지도 탭은 동작해야 한다.
- 길찾기 경로 데이터는 기존 서버의 Kakao Mobility 프록시를 계속 사용할 수 있다.

## 접근
1. 카카오 SDK 로드 실패 시 Leaflet/OpenStreetMap fallback 지도를 동적으로 로드한다.
   - verify: 카카오가 실패해도 지도 탭에 캠퍼스 지도와 마커가 표시되는 경로가 있다.
2. fallback 지도에서도 현재 위치와 주요 위치 마커를 표시한다.
   - verify: 위치 권한이 허용되면 현재 위치가 표시되고, 거부되어도 기본 지도는 유지된다.
3. 식당 길찾기에서 fallback 지도일 때도 목적지와 경로 폴리라인을 그린다.
   - verify: `showRestaurantRoute`가 Kakao/Leaflet 양쪽 경로를 분기한다.
4. 캐시 버전을 갱신하고 문법 검증 후 푸시한다.
   - verify: `node --check script.js`, `node --check sw.js` 통과.

## 변경 파일
- index.html
- script.js
- style.css
- sw.js
- PLAN.md
- PLAN_REVIEW.md
