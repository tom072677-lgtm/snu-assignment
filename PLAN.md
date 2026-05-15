# PLAN: 네이버 지도 스타일 4종 교통수단 경로 검색

## 목표
버스·자동차·도보·자전거 4종 탭을 동시에 보여주고,
탭 클릭 시 해당 교통수단의 실제 경로를 지도에 그리며 소요시간을 표시한다.

## API 전략
| 교통수단 | API | 비고 |
|---|---|---|
| 🚗 자동차 | Kakao Mobility `/v1/directions` | 이미 구현, 실제 경로+시간 |
| 🚶 도보 | OSRM public `/route/v1/foot` | 무료, 키 없음, 실제 경로+시간 |
| 🚲 자전거 | OSRM public `/route/v1/bicycle` | 무료, 키 없음, 실제 경로+시간 |
| 🚌 버스 | ODsay API (가입 필요) or 거리 추정 | 1단계는 추정(15km/h), 2단계 ODsay |

## UI 변경 (네이버 지도 스타일)
- 길찾기 결과 나오면 4개 탭을 **동시에** 보여줌 (각 탭에 소요시간 표시)
- 탭 클릭 → 해당 교통수단 경로를 지도에 다시 그림 (다른 색)
  - 자동차: 파란 실선
  - 도보: 초록 실선
  - 자전거: 주황 점선
  - 버스: 보라 실선 (추정이면 점선)
- 경로 정보 카드: 소요시간(크게) + 거리(작게)

## 변경 파일
- `server/index.js`: OSRM 프록시 엔드포인트 추가 (`/api/route/walk`, `/api/route/bike`)
- `script.js`: 4개 모드 병렬 호출, 모드별 폴리라인 저장, 탭 전환 로직
- `style.css`: 모드 탭 소요시간 inline 표시 스타일
- `index.html`: 모드 탭 구조 변경

## 단계별 접근
1. 서버에 OSRM 프록시 추가
   - verify: `/api/route/walk?olat=37.46&olng=126.95&dlat=37.47&dlng=126.96` 응답에 duration, distance, geometry 포함
2. 길찾기 시 4종 API 병렬 호출 (Promise.allSettled)
   - verify: 하나 실패해도 나머지 정상 표시
3. 탭에 소요시간 inline 표시 (예: "🚶 18분")
   - verify: 길찾기 결과 나오면 모든 탭에 시간 뜸
4. 탭 클릭 시 해당 경로 폴리라인으로 교체
   - verify: 자동차 탭→파란선, 도보 탭→초록선
5. 버전 v30, 문법 검증, 커밋/푸시
   - verify: `node --check script.js`, `node --check server/index.js` 통과
