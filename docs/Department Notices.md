---
tags: [sharap, notices, feature]
---
# Department Notices

**Goal:** show every SNU department's notices in-app, like the existing PE-dept (체육교육과) tab.

Code: `lib/features/notices/`. Registry: `domain/department_notice_source.dart`. Parsers + cert pin: `data/notice_repository.dart`. Server scraper: `server/deptNotices.js`.

## The four source types
Each department maps to exactly one of these in the registry:

| Helper | Means | Use when |
|---|---|---|
| `_wp(code, host)` | RSS/Atom (`/feed/`), parsed on-device | WordPress depts |
| `_html` / `_board(code, host, url)` | **client-side** HTML scrape (`parseHtmlNoticeList`) | site reachable from the phone **and UTF-8** (the app can't decode EUC-KR) |
| `_server(code, host)` | **server** scrape via `GET /api/dept-notices?dept=<code>` | needs TLS/encoding/JS-menu handling the phone can't do; the allowlist key in `server/deptNotices.js` must match `<code>` |
| `_home(code, host)` | homepage-button fallback | no in-app notices possible |

**Server scraper** (`server/deptNotices.js`): static fetch + cheerio (**not** a headless browser — see [[Decisions]] D1), dept-code allowlist (anti-SSRF), DNS-level private-IP guard, 3 MB cap, `iconv-lite` charset decode, per-board `detail()` URL templates, and `fullTitle()` detail-page fetch where the list truncates titles. Also supports AJAX/JSON boards (`httpPost` + `jsonList`).

## Live status — keep this current ✅
**Working in-app (server scrape):** 수리과학부 `mathematics`, 의과대학 `medicine`, 치의학대학원 `dentistry`, 불어불문학과 `french_language`, 건설환경공학부 `civil`, 철학과 `philosophy`, 영어교육과 `english_edu`, 정치외교학부 `political_science`.

**Special cases:**
- **인류학과 `anthropology`** — client-side `_board` + a scoped **Sectigo cert pin** in `notice_repository.dart`. Render can't reach `anthropology.or.kr`; a phone in Korea can; Dart's HTTP client rejects its cert chain → the pin trusts that one host's genuine Sectigo cert. Full story: [[Debugging Notes]].
- **정치외교학부 `political_science`** — new domain `psir.snu.ac.kr` is an **AJAX board**: POST `/event/listProc` → JSON, requires `gnbType=01&type=01`; detail URL `/event/${pid}` (path-style); `headerlist` (14 pinned) + `list` (10 general) = 24 items; dedup by URL **and** title+date. (`_server`, `httpPost`/`jsonList`.)
- **건축학과 `architecture`** — `architecture.snu.ac.kr` HTTPS down (TCP RST on 443, as of 2026-06-03). Temp fallback → `_board` on `eng.snu.ac.kr/communication/notice/notice` (공과대학 공지, device-verified, 10 items). **Revert** to `_html('architecture', 'architecture.snu.ac.kr', '/notice/')` when the site recovers.
- **시스템생명공학부 `systems_biomedical`, 학제전공 `interdisciplinary_engineering`** — no independent site → share the 공과대학 board (`eng.snu.ac.kr/communication/notice/notice`).

**Homepage fallback (can't fix):**
- **독어교육과 `german_edu`** — article pages are JS-rendered (`view.asp?key=*` all return a byte-identical shell), so full titles aren't statically extractable. See [[Decisions]] D4.
- **고고미술사학과 `archaeology`** — server fully broken (IIS/5.0, every path 404 as of 2026-06-03).

## Runbook — add or fix a department
1. **Verify the live source first** (global rule 9): `curl` the board, check the **charset** (UTF-8 vs EUC-KR), inspect the **row markup** (real `href` vs `javascript:`/onclick, and where the date lives).
2. **Pick the source type:**
   - reachable from a Korean phone + UTF-8 + standard HTML → **`_board`** (client-side, no server load).
   - EUC-KR / TLS / HTTP2 quirks / JS-built menu / AJAX-JSON → **`_server`** (add the allowlist entry in `server/deptNotices.js`).
   - genuinely unreachable (internal IP, dead host, JS-only articles) → **`_home`**.
3. **Register** in `department_notice_source.dart`.
4. **Test server-side:** `node server/deptNotices.js <code>` — expect ≥1 item with a title, an http(s) url, and a date.
5. **Device-verify** with `/ship` → open the dept's 공지 tab.
6. **Update this note** (the status list + the dept) — and tell Claude to.

See also: [[Decisions]], [[Debugging Notes]].
