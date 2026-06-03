# CLAUDE.md — sharap (project)

Project-specific context. **Complements** the global rules in `~/.claude/CLAUDE.md` (don't duplicate them; this file adds project facts).

## What this repo is
**sharap** — an SNU student app. This is a **monorepo**:
- **Flutter app** (`lib/`) — runs on Android, package `com.tom07.sharap`. Reaches users via an **APK install**, not a server deploy.
- **Node/Express server** (`server/`) — deployed to **Render** at `https://snu-assignment-server.onrender.com`. Git remote `github.com/tom072677-lgtm/snu-assignment`, branch `main`.

## ⚠️ The deployed server is THIS repo's `server/`
Live server = `sharap-flutter/server/index.js` (+ `server/deptNotices.js`). **`git push origin main` → Render auto-deploys it.**
**`~/Desktop/snu 과제 앱` is a DEAD old copy — never edit or deploy it.** (Its git history diverged; editing it once cost real time before the mistake was caught.)

## Build / install / deploy
- **Build + install on the phone:** use **`/ship`** (or `~/.claude/scripts/flutter_install.ps1`). It builds `--release --dart-define-from-file=dart_defines.json` and `adb install -r` (data-preserving). Never `flutter install`; never omit the dart-define (NaverMap auth breaks). See global rule 6.
- **Deploy the server:** `git push origin main` → Render rebuilds `server/`. The app itself is **not** deployed via push.
- After `adb install -r`, **force-stop** so the new build loads: `adb shell am force-stop com.tom07.sharap` (install -r doesn't restart a running app).
- `serverUrl` lives in `lib/core/constants.dart` (default the Render URL).

## Department notices system (`lib/features/notices/`)
Each department maps — in `domain/department_notice_source.dart` — to ONE source type:
| Helper | Means | When |
|---|---|---|
| `_wp(code, host)` | RSS/Atom (`/feed/`), parsed on-device | WordPress depts |
| `_html` / `_board(code, host, url)` | **client-side** HTML scrape (`parseHtmlNoticeList`) | site reachable from the phone **and UTF-8** (app can't decode EUC-KR) |
| `_server(code, host)` | **server** scrape via `GET /api/dept-notices?dept=<code>` | needs TLS/encoding handling the phone can't do (EUC-KR, HTTP/2 quirks); allowlist key in `server/deptNotices.js` must match `<code>` |
| `_home(code, host)` | homepage-button fallback | no in-app notices possible |

**Server scraper** (`server/deptNotices.js`): static fetch + cheerio (**not** headless), dept-code allowlist (anti-SSRF), DNS-level private-IP guard, 3MB cap, charset decode (`iconv-lite`), per-board `detail()` URL templates and `fullTitle()` detail-fetch where lists truncate.

**To add a department:** verify the live URL/charset/selectors first (global rule 9) → register in the registry (prefer `_board` if phone-reachable + UTF-8, else `_server`) → if `_server`, add the allowlist entry in `server/deptNotices.js` → test (`node server/deptNotices.js <code>`) → device-verify.

## Current notices status / quirks
- **In-app via server scrape:** 수리과학부(`mathematics`), 의과대학(`medicine`), 치의학대학원(`dentistry`), 불어불문학과(`french_language`), 건설환경공학부(`civil`), 철학과(`philosophy`), 영어교육과(`english_edu`).
- **인류학과(`anthropology`):** **client-side `_board` + a scoped Sectigo cert pin** in `notice_repository.dart` (Render can't reach `anthropology.or.kr`; a phone in Korea can; Dart's HTTP client rejects its cert chain, so the pin trusts that one host's genuine Sectigo cert).
- **Homepage fallback, can't fix:** 독어교육과(`german_edu`, JS-rendered article pages), 정치외교학부(`political_science`, resolves to an internal 10.x IP), 고고미술사학과(`archaeology`, dead host/bad cert).
- **건축학과(`architecture`):** 2026-06-03 현재 `architecture.snu.ac.kr` HTTPS 다운(TCP RST on 443). 임시 fallback → `_board`로 `eng.snu.ac.kr/communication/notice/notice` 공과대학 공지 사용(기기 검증 완료, 10건). 사이트 복구 시 `_html('architecture', 'architecture.snu.ac.kr', '/notice/')`로 되돌릴 것.
- **시스템생명공학부(`systems_biomedical`), 학제전공(`interdisciplinary_engineering`):** 독립 사이트 없음 → 공과대학 공지 게시판(`eng.snu.ac.kr/communication/notice/notice`) 공유 등록.
