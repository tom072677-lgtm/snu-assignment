# PLAN: 24시간 폭탄 푸시 알림

## 목표
마감까지 24시간 초과로 남은 과제에는 앱 안 폭탄 UI를 숨기고, 24시간 이하로 들어오면 앱을 켜지 않아도 휴대폰 푸시 알림으로 남은 시간을 알려준다.

## 가정
- Web/PWA 알림은 OS 정책상 사용자가 직접 지우는 것을 완전히 막을 수 없다.
- `requireInteraction`, 동일 `tag`, `renotify`로 가능한 한 오래 남고 갱신되는 알림에 가깝게 만든다.
- 알림 안의 폭탄 감소 표현은 네이티브 애니메이션이 아니라 남은 시간과 텍스트 진행 바로 표현한다.

## 접근
1. 앱 안 폭탄 UI는 다시 실제 24시간 이하에서만 보이게 한다.
   - verify: 24시간 초과 D-1 과제에는 폭탄 UI가 보이지 않는다.
2. 푸시 알림 payload와 로컬 알림 옵션에 `requireInteraction`, `tag`, `renotify`, 남은 시간 진행 바를 넣는다.
   - verify: 서비스워커가 payload의 옵션을 알림에 전달한다.
3. 서버 백그라운드 푸시 타깃을 24시간부터 1시간까지 매시간으로 늘린다.
   - verify: 앱을 열지 않아도 서버가 등록된 과제에 대해 hourly push를 보낼 수 있다.
4. 클라이언트 로컬 알림도 같은 형식으로 맞춰 중복되어도 같은 tag로 갱신되게 한다.
   - verify: 앱이 열린 상태에서도 알림 형식이 동일하다.
5. 캐시 버전 갱신, 문법 검증, 코드 리뷰 후 커밋/푸시한다.
   - verify: `node --check script.js`, `node --check sw.js`, `node --check server/index.js`, `codex review --uncommitted` 통과.

## 변경 파일
- PLAN.md
- PLAN_REVIEW.md
- index.html
- script.js
- style.css
- sw.js
- server/index.js
