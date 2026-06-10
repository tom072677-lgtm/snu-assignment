---
tags: [sharap, decisions]
---
# Decision Log

The *why* behind the non-obvious choices, so we don't re-litigate them.

## D1 — Static server scraper, NOT a headless browser
**Decision:** scrape department sites with a static fetch + cheerio on the Render server; no Puppeteer/Playwright.
**Why:** every *reachable* dept site turned out to be **server-rendered HTML**, not JS-rendered. A headless browser would add ~300 MB Chromium to a 512 MB Render free tier (OOM risk) for **zero extra coverage**, and wouldn't rescue the truly-unreachable ones either. (Even `medicine`, which *looked* "react", is server-rendered eGov.)

## D2 — Client-side fetch for anthropology
**Decision:** fetch `anthropology.or.kr` on-device (`_board`), not via the server.
**Why:** Render's overseas servers can't reach the site (Korea-only reachability), but the **phone is in Korea** and can. If the device can reach it directly, the server doesn't need to.

## D3 — Cert pin for anthropology: domain + issuer, not byte-exact
**Decision:** a scoped `badCertificateCallback` that trusts `www.anthropology.or.kr` **only** when the cert is a genuine **Sectigo**-issued cert for that domain.
**Why:** Dart's HTTP client rejects the site's Sectigo chain (browsers complete it; Dart doesn't do AIA chain-building). A byte-exact pin would break on **every cert renewal**; a domain+issuer check **survives renewals** and still blocks MITM (an attacker can't obtain a Sectigo cert for that domain). Data is read-only public notices → low risk. Story: [[Debugging Notes]].

## D4 — Drop german_edu to homepage fallback
**Decision:** don't ship `german_edu` notices in-app.
**Why:** its article pages are JS-rendered — a static fetch of `view.asp?key=<anything>` returns a byte-identical shell, so full titles can't be recovered without a headless browser (rejected in D1).

## D5 — Detail-page fetch for full titles (gnuboard truncation)
**Decision:** for boards that truncate list titles (e.g. `civil`'s gnuboard), fetch each article's detail page and pull the full title from its `<title>`.
**Why:** the list view truncates with "…"; the detail page is server-rendered with the full subject. Done in parallel + cached 30 min, so the cost is bounded.

## D6 — Project memory: CLAUDE.md + this wiki
**Decision:** quick facts in `CLAUDE.md` (auto-loaded by Claude Code), richer narrative here in `docs/` (Obsidian vault).
**Why:** stops Claude re-deriving the architecture each session — which once led to editing the **dead** `snu 과제 앱` folder (see [[Debugging Notes]]). Inspired by Karpathy's "LLM Wiki" idea: a readable knowledge base the LLM navigates.

See also: [[Architecture]], [[Department Notices]].
