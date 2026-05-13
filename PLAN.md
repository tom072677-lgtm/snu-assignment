# PLAN: 지도 초기 커스텀 마커 제거

## 목표
지도 탭을 처음 열었을 때 앱이 추가한 파란 마커와 정보창이 보이지 않게 한다. 사용자가 지도 위 건물/장소를 직접 선택하면 카카오 지도 기본 정보가 보이도록 둔다.

## 가정
- 사용자가 지우려는 마크는 `SNU_LOCATIONS`를 기반으로 앱이 추가한 `kakao.maps.Marker`들이다.
- 식당 길찾기 목적지 마커와 현재 위치 마커는 사용자 동작 이후 필요한 기능이므로 유지한다.
- 초기 지도에는 카카오 기본 지도 레이어만 보이면 된다.

## 접근
1. 지도 초기화 시 `renderMapPlaces()` 호출을 제거한다.
   - verify: 지도 탭 진입 시 SNU_LOCATIONS 마커가 생성되지 않는다.
2. 커스텀 장소 마커/정보창 렌더링 함수와 상태를 제거한다.
   - verify: `mapPlaceMarkers`/`renderMapPlaces`/커스텀 클릭 정보창이 남지 않는다.
3. 캐시 버전을 갱신하고 문법 검증 후 푸시한다.
   - verify: `node --check script.js`, `node --check sw.js` 통과.

## 변경 파일
- index.html
- script.js
- sw.js
- PLAN.md
- PLAN_REVIEW.md
