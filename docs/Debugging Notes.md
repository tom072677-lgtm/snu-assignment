---
tags: [sharap, debugging, lessons]
---
# Debugging Notes & War-Stories

Hard-won lessons. Each ends with a reusable rule.

## The anthropology TLS saga 🕵️
**Symptom:** `anthropology` showed "공지를 불러오지 못했다" on the phone, even though the code worked everywhere else.
**Trail:** Render fetch failed (overseas/geo) → moved it client-side (`_board`) → still failed on-device → but `ping` reached the host (IPv4, ~35 ms) **and** the phone's **browser loaded it fine** (HTTPS lock visible) → so it was the **TLS handshake**: `anthropology.or.kr` serves a Sectigo cert whose chain **browsers/curl/Node complete but Dart's HTTP client doesn't**. Fixed with a scoped domain+issuer cert pin ([[Decisions]] D3).
**Rules:**
- "Works in browser/curl/Node but fails in the Flutter app" → suspect the **TLS cert chain** (Dart's client doesn't do AIA chain-building).
- Flutter **release builds hide `debugPrint`** from logcat — diagnose by **reproducing each layer** (`ping` for reachability, the **browser** for TLS, a tiny `dart:io HttpClient` script for the app's exact stack) instead of hunting logs.

## The stale-folder trap 📁
**Symptom:** edits to "the server" did nothing; a push was rejected.
**Cause:** there are **two** server folders — the live one is `sharap-flutter/server/`; `~/Desktop/snu 과제 앱` is a dead copy with diverged git history. Real time was lost editing the dead one.
**Rule:** confirm the deployed path before editing a server (`git remote -v`, branch, and that the file matches what's live). This is *why* the [[Architecture]] note + the `CLAUDE.md` warning exist.

## Local ≠ Render
**Symptom:** `anthropology` returned 24 items locally but **502 (`fetch-failed`) on Render** for 8 straight minutes.
**Rule:** a scraper passing **locally is not verified for production** — the deploy environment's network differs (region, IPv6, geo-blocks). Verify against the **live** endpoint.

## math gnuboard `ECONNRESET`
**Symptom:** Node fetch to `www.math.snu.ac.kr` reset the connection, but a bare `https.get` with `rejectUnauthorized:false` worked.
**Cause:** passing a custom `new https.Agent(...)` triggered the reset; setting the TLS options **directly on the request** did not.
**Rule:** for a flaky old TLS host, set `rejectUnauthorized` / `maxVersion: 'TLSv1.2'` on the **request options**, not via a custom Agent.

## eGov boards (medicine / dentistry)
- List title links are `javascript:goToDetail('<id>')` (not real hrefs); the list URL is `selectNoticeList.do?bbsId=…`. The detail page navigates via a POST form to `selectNoticeDetail.do`, but a plain **GET** `selectNoticeDetail.do?nttId=<id>&bbsId=<id>` works as the article URL.
- A `react`-looking marker can be a false positive — verify the page is actually JS-rendered (compare `view?id=<a>` vs `<b>`; identical bytes = JS shell) before giving up on static scraping.

See also: [[Decisions]], [[Department Notices]].
