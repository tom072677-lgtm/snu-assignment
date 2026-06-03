// Department notice scraper: static HTML fetch + cheerio extraction.
// Covers SNU departments whose notice boards the Flutter app cannot fetch
// on-device (TLS/HTTP2 quirks, legacy charset, JS-built nav). NOT a headless
// browser: every covered board is server-rendered HTML.
//
// Anti-SSRF: callers pass only a dept CODE; URLs come from this allowlist.
// Run directly to test live:  node deptNotices.js <deptCode>

const https = require("https");
const http = require("http");
const dns = require("dns");
const cheerio = require("cheerio");
const iconv = require("iconv-lite");

const BROWSER_UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/124.0 Safari/537.36";
const MAX_BODY = 3 * 1024 * 1024; // 3 MB
const TIMEOUT_MS = 15000;
const MAX_REDIRECTS = 3;

// ---- POST request (for JSON API endpoints). Returns decoded string.
function httpPost(targetUrl, bodyStr, { insecureTLS = false } = {}) {
  return new Promise((resolve, reject) => {
    let u;
    try { u = new URL(targetUrl); } catch { return reject(new Error("bad url")); }
    if (u.protocol !== "http:" && u.protocol !== "https:")
      return reject(new Error("bad protocol: " + u.protocol));
    if (isPrivateAddr(u.hostname)) return reject(new Error("blocked private host"));

    const mod = u.protocol === "https:" ? https : http;
    const bodyBuf = Buffer.from(bodyStr, "utf-8");
    const opts = {
      method: "POST",
      headers: {
        "User-Agent": BROWSER_UA,
        Accept: "application/json, */*",
        "Accept-Language": "ko,en;q=0.8",
        "Content-Type": "application/x-www-form-urlencoded",
        "Content-Length": bodyBuf.length,
      },
      timeout: TIMEOUT_MS,
      lookup: safeLookup,
    };
    if (u.protocol === "https:" && insecureTLS) {
      opts.rejectUnauthorized = false;
      opts.maxVersion = "TLSv1.2";
    }
    const req = mod.request(targetUrl, opts, (res) => {
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error("HTTP " + res.statusCode));
      }
      const chunks = [];
      let len = 0;
      res.on("data", (c) => {
        len += c.length;
        if (len > MAX_BODY) { req.destroy(); reject(new Error("body too large")); return; }
        chunks.push(c);
      });
      res.on("end", () => resolve(Buffer.concat(chunks).toString("utf-8")));
    });
    req.on("timeout", () => req.destroy(new Error("timeout")));
    req.on("error", reject);
    req.write(bodyBuf);
    req.end();
  });
}

// Phase 1: fully verified boards (gnuboard + eGov skin). Add more in Phase 2.
const DEPT_NOTICE_SOURCES = {
  mathematics: {
    url: "https://www.math.snu.ac.kr/bbs/board.php?bo_table=Math_Notice",
    insecureTLS: true, // known SNU host; default TLS/HTTP2 negotiation fails
  },
  dentistry: {
    url: "https://dentistry.snu.ac.kr/fnt/nac/selectNoticeList.do?bbsId=BBS_0000000000001",
    detail: (id) =>
      `https://dentistry.snu.ac.kr/fnt/nac/selectNoticeDetail.do?nttId=${id}&bbsId=BBS_0000000000001`,
  },
  medicine: {
    url: "https://medicine.snu.ac.kr/fnt/nac/selectNoticeList.do?bbsId=BBSMSTR_000000000001",
    detail: (id) =>
      `https://medicine.snu.ac.kr/fnt/nac/selectNoticeDetail.do?nttId=${id}&bbsId=BBSMSTR_000000000001`,
  },
  french_language: {
    url: "https://www.snufrance.com/home/opsquare/notice.asp?gubun=SNUFR&board_cd=NOTICE",
    detail: (id) =>
      `https://www.snufrance.com/home/opsquare/notice.asp?gubun=SNUFR&board_cd=NOTICE&mode=VIEW&idx=${id}`,
  },
  civil: {
    // gnuboard 공지사항; list truncates subjects, so pull full titles from each
    // article's detail-page <title> ("게시판 > 공지사항 > [full subject]").
    url: "https://cee.snu.ac.kr/bbs/board.php?bo_table=sub6_1",
    fullTitle: (html) => {
      const m = html.match(/<title>([^<]*)<\/title>/i);
      if (!m) return "";
      return (
        m[1]
          .split(/\s*>\s*/)
          .map((s) => s.trim())
          .filter((s) => s && s !== "게시판" && s !== "공지사항")
          .sort((a, b) => b.length - a.length)[0] || ""
      );
    },
  },
  philosophy: {
    // Dedicated list is a JS shell; the board index renders recent notices
    // (menu6/sub06_view.html?wr_id=) inline. EUC-KR.
    url: "https://philosophy.snu.ac.kr/board/html/main/index.php",
  },
  english_edu: {
    url: "https://engedu.snu.ac.kr/05_sub/5c_sub01.php", // 학부 공지사항, EUC-KR
  },
  // psir.snu.ac.kr: 공지 목록은 AJAX(POST /event/listProc → JSON).
  // gnbType=01&type=01 이 학부 공지 게시판의 필수 필터 (없으면 테스트 board 반환).
  // 상세 URL: /event/${pid} (path 방식; ?pid= 방식은 다른 board로 이동됨).
  political_science: {
    jsonList: {
      url: "https://psir.snu.ac.kr/event/listProc",
      params: "pnum=1&gnbType=01&type=01&srch_type=&srch_filter=&srch_name=&category=",
      detail: (pid) => `https://psir.snu.ac.kr/event/${pid}`,
    },
  },
};

// ---- SSRF guard: reject any address in private / loopback / link-local ranges.
function isPrivateAddr(ip) {
  if (typeof ip !== "string" || !ip) return false;
  if (ip === "::1" || ip.startsWith("fc") || ip.startsWith("fd") || ip.startsWith("fe80"))
    return true;
  const m = ip.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (!m) return false; // non-IPv4 literal host names are resolved via safeLookup
  const [a, b] = [Number(m[1]), Number(m[2])];
  if (a === 10 || a === 127) return true;
  if (a === 169 && b === 254) return true;
  if (a === 192 && b === 168) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  return false;
}

function safeLookup(hostname, options, cb) {
  dns.lookup(hostname, options, (err, address, family) => {
    if (err) return cb(err);
    // With { all: true } address is an array of { address, family }.
    const list = Array.isArray(address) ? address : [{ address, family }];
    for (const a of list) {
      if (isPrivateAddr(a.address))
        return cb(new Error(`blocked private address: ${hostname} -> ${a.address}`));
    }
    cb(null, address, family);
  });
}

// ---- Fetch HTML with redirects, timeout, body cap, optional insecure TLS.
function httpGet(targetUrl, { insecureTLS = false, depth = 0 } = {}) {
  return new Promise((resolve, reject) => {
    if (depth > MAX_REDIRECTS) return reject(new Error("too many redirects"));
    let u;
    try {
      u = new URL(targetUrl);
    } catch {
      return reject(new Error("bad url"));
    }
    if (u.protocol !== "http:" && u.protocol !== "https:")
      return reject(new Error("bad protocol: " + u.protocol));
    if (isPrivateAddr(u.hostname)) return reject(new Error("blocked private host"));

    const mod = u.protocol === "https:" ? https : http;
    const opts = {
      method: "GET",
      headers: {
        "User-Agent": BROWSER_UA,
        Accept: "text/html,application/xhtml+xml,*/*",
        "Accept-Language": "ko,en;q=0.8",
      },
      timeout: TIMEOUT_MS,
      lookup: safeLookup,
    };
    if (u.protocol === "https:" && insecureTLS) {
      // Scoped to the allowlisted SNU host (math). A custom Agent caused
      // ECONNRESET here; setting TLS options directly works.
      opts.rejectUnauthorized = false;
      opts.maxVersion = "TLSv1.2";
    }

    const req = mod.get(targetUrl, opts, (res) => {
      const { statusCode, headers } = res;
      if ([301, 302, 303, 307, 308].includes(statusCode) && headers.location) {
        res.resume();
        let next;
        try {
          next = new URL(headers.location, targetUrl).href;
        } catch {
          return reject(new Error("bad redirect location"));
        }
        return resolve(httpGet(next, { insecureTLS, depth: depth + 1 }));
      }
      if (statusCode !== 200) {
        res.resume();
        return reject(new Error("HTTP " + statusCode));
      }
      const chunks = [];
      let len = 0;
      res.on("data", (c) => {
        len += c.length;
        if (len > MAX_BODY) {
          req.destroy();
          reject(new Error("body too large"));
          return;
        }
        chunks.push(c);
      });
      res.on("end", () =>
        resolve({
          buf: Buffer.concat(chunks),
          contentType: headers["content-type"] || "",
        })
      );
    });
    req.on("timeout", () => req.destroy(new Error("timeout")));
    req.on("error", reject);
  });
}

// ---- Decode body honoring charset (header, then <meta>), EUC-KR aware.
function decodeBody(buf, contentType) {
  const head = buf.slice(0, 2048).toString("latin1");
  let cs =
    (contentType.match(/charset=["']?([\w-]+)/i) || [])[1] ||
    (head.match(/charset=["']?([\w-]+)/i) || [])[1] ||
    "utf-8";
  cs = cs.toLowerCase();
  if (/euc-?kr|ks_?c_?5601|ksc5601|cp949|x?-?windows-949/.test(cs)) {
    return iconv.decode(buf, "euc-kr");
  }
  return buf.toString("utf-8");
}

// ---- Date parsing: YYYY.MM.DD / -/ / / spaces, YYYY년 M월 D일, YY.MM.DD.
function findDate(text) {
  if (!text) return "";
  let m = text.match(/(20\d{2})\s*[.\-\/]\s*(\d{1,2})\s*[.\-\/]\s*(\d{1,2})/);
  if (m) return `${m[1]}.${pad(m[2])}.${pad(m[3])}`;
  m = text.match(/(20\d{2})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일/);
  if (m) return `${m[1]}.${pad(m[2])}.${pad(m[3])}`;
  m = text.match(/\b(\d{2})\s*[.\-]\s*(\d{1,2})\s*[.\-]\s*(\d{1,2})\b/); // YY.MM.DD
  if (m) return `20${m[1]}.${pad(m[2])}.${pad(m[3])}`;
  m = text.match(/\b(\d{1,2})\s*[.\-]\s*(\d{1,2})\b/); // MM.DD (current year)
  if (m) {
    const mo = +m[1],
      da = +m[2];
    if (mo >= 1 && mo <= 12 && da >= 1 && da <= 31)
      return `${new Date().getFullYear()}.${pad(mo)}.${pad(da)}`;
  }
  return "";
}
function pad(n) {
  return String(n).padStart(2, "0");
}

// Article-link href patterns (board view pages), distinct from nav.
const ART_HREF =
  /(wr_id=|view\.asp|mode=view|[?&]No=|[?&]key=|selectNoticeView|selectNoticeDetail|bbsidx=|articleNo=|nttId=)/i;

// ---- Extract notice rows. General heuristic + per-dept detail() for JS links.
function extractNotices($, cfg) {
  const items = [];
  const seen = new Set();
  $("a").each((_, el) => {
    const $a = $(el);
    // Prefer a .subject child (eGov wraps title there); else anchor text.
    const $subj = $a.find(".subject").first();
    let title = ($subj.length ? $subj.text() : $a.text())
      .replace(/\s+/g, " ")
      .trim();
    // Strip leading notice/new badges and trailing "date [hits]" metadata.
    title = title
      .replace(/^(공지|중요|notice|new|hot)\s+/i, "")
      .replace(/\s*20\d{2}\s*[.\-]\s*\d{1,2}\s*[.\-]\s*\d{1,2}(\s+\d+)?\s*$/, "")
      .trim();
    if (title.length < 4 || title.length > 140) return;

    const href = ($a.attr("href") || "").trim();
    const onclick = $a.attr("onclick") || "";
    let url = null;

    if (cfg.detail && /goToDetail|goView|fnItemRead/i.test(onclick)) {
      const id = (onclick.match(/\d{2,}/) || [])[0];
      if (id) url = cfg.detail(id);
    } else if (href && !/^#|^javascript:/i.test(href) && ART_HREF.test(href)) {
      try {
        url = new URL(href, cfg.base || cfg.url).href;
      } catch {
        return;
      }
    }
    if (!url || seen.has(url)) return;

    // Date: prefer an explicit date cell in the nearest row (tr/li); else climb
    // a few levels (capped so it cannot reach shared list containers).
    let date = "";
    const $row = $a.closest("tr, li");
    if ($row.length) {
      const $d = $row.find('[class*="date"]').first();
      date = findDate($d.length ? $d.text() : $row.text());
    }
    if (!date) {
      let node = $a;
      for (let i = 0; i < 3 && node.length; i++) {
        const $d = node.find('[class*="date"]').first();
        const d = findDate($d.length ? $d.text() : node.text());
        if (d) {
          date = d;
          break;
        }
        node = node.parent();
      }
    }

    seen.add(url);
    items.push({ title, url, date });
  });
  return items.slice(0, 30);
}

// Replace each item's (truncated) list title with the full title from its
// detail page. For boards that truncate subjects in the list view (e.g. some
// gnuboard skins) but render the full title server-side on the article page.
async function enrichFullTitles(items, cfg) {
  const BATCH = 6;
  for (let i = 0; i < items.length; i += BATCH) {
    await Promise.all(
      items.slice(i, i + BATCH).map(async (it) => {
        try {
          const { buf, contentType } = await httpGet(it.url, {
            insecureTLS: !!cfg.insecureTLS,
          });
          const full = cfg.fullTitle(decodeBody(buf, contentType));
          const stem = it.title.replace(/[….]+$/, "").trim();
          if (full && full.length >= stem.length) it.title = full;
        } catch {
          /* keep the truncated title on failure */
        }
      })
    );
  }
  return items;
}

async function scrapeDept(dept) {
  const cfg = DEPT_NOTICE_SOURCES[dept];
  if (!cfg) {
    const e = new Error("unknown-dept");
    e.code = "UNKNOWN_DEPT";
    throw e;
  }
  // JSON API 방식 (psir 등 AJAX 기반 공지 게시판)
  if (cfg.jsonList) {
    const { url, params, detail } = cfg.jsonList;
    const raw = await httpPost(url, params);
    const data = JSON.parse(raw);
    // headerlist(공지/고정) + list(일반) 합산. headerlist를 앞에 두어 중요 공지 우선.
    const all = [...(data.headerlist || []), ...(data.list || [])];
    const seenUrl = new Set();
    const seenTitleDate = new Set();
    const items = [];
    for (const it of all) {
      const title = (it.title || "").trim();
      if (title.length < 4 || title.length > 140) continue;
      const itemUrl = detail(it.pid);
      if (seenUrl.has(itemUrl)) continue;
      seenUrl.add(itemUrl);
      const date = it.regDate
        ? it.regDate.replace(/-/g, ".")
        : (it.created || "").slice(0, 10).replace(/-/g, ".");
      const titleDateKey = title + "|" + date;
      if (seenTitleDate.has(titleDateKey)) continue;
      seenTitleDate.add(titleDateKey);
      items.push({ title, url: itemUrl, date });
      if (items.length >= 30) break;
    }
    return { items, htmlHead: "" };
  }

  // 일부 학과 서버(math)는 간헐적으로 TLS 연결을 리셋함 → 1회 재시도.
  let lastErr;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const { buf, contentType } = await httpGet(cfg.url, {
        insecureTLS: !!cfg.insecureTLS,
      });
      const html = decodeBody(buf, contentType);
      const $ = cheerio.load(html);
      let items = extractNotices($, cfg);
      if (cfg.fullTitle && items.length) items = await enrichFullTitles(items, cfg);
      return { items, htmlHead: html.slice(0, 500) };
    } catch (e) {
      lastErr = e;
    }
  }
  throw lastErr;
}

module.exports = { DEPT_NOTICE_SOURCES, scrapeDept };

// Live self-test: node deptNotices.js <deptCode>
if (require.main === module) {
  const dept = process.argv[2] || "math";
  scrapeDept(dept)
    .then((r) => {
      console.log(`[${dept}] ${r.items.length} items`);
      r.items.slice(0, 6).forEach((it) => console.log(JSON.stringify(it)));
      if (!r.items.length) console.log("HTML HEAD:", r.htmlHead);
    })
    .catch((e) => console.error(`[${dept}] ERROR:`, e.message));
}
