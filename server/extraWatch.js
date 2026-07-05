// SNU 비교과(extra.snu.ac.kr) 목록 파서 — 신규 프로그램 감시용.
// 상세 페이지(view.do)는 AJAX 렌더라 정적 fetch로는 본문이 없음(2026-07-06 확인)
// → 목록의 구조화 정보(제목·소개·신청기간·운영방식)만 사용한다.
// 셀렉터는 앱의 검증된 Dart 파서(notice_repository.dart parseExtraHtml)와 동일.
// CLI 테스트: node extraWatch.js
const cheerio = require("cheerio");

const LIST_URL = "https://extra.snu.ac.kr/ptfol/pgm/index.do";
const PAGES = 2;

async function fetchPage(page) {
  const r = await fetch(`${LIST_URL}?currentPageNo=${page}&sort=0001`, {
    headers: { "User-Agent": "Mozilla/5.0", Accept: "text/html" },
    signal: AbortSignal.timeout(15000),
  });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.text();
}

function parseList(html) {
  const $ = cheerio.load(html);
  const items = [];
  $("div.lica_wrap ul li").each((_, li) => {
    const el = $(li);
    if (el.find("div.lica_gp").length === 0) return;
    const title = el.find("a.tit").first().text().trim();
    if (!title) return;
    const dataParams = el.find("[data-params]").attr("data-params") || "";
    const seqM = dataParams.match(/"pgmSeq"\s*:\s*"(\d+)"/);
    if (!seqM) return;
    const majors = el.find("ul.major_type li");
    items.push({
      seq: seqM[1],
      title,
      organizer: majors.eq(0).text().trim(),
      category: majors.eq(1).text().trim() || majors.eq(0).text().trim() || "기타",
      status: el.find(".btn01 span").first().text().trim(),
      applyPeriod: el.find("dl.apl_date dd").first().text().trim(),
      mode: el.find("dl.class_cd dd").first().text().trim(),
      desc: el.find("p.desc").first().text().trim(),
    });
  });
  return items;
}

async function fetchExtraPrograms() {
  const bySeq = new Map();
  for (let p = 1; p <= PAGES; p++) {
    const items = parseList(await fetchPage(p));
    // 1페이지 0건 = "새 프로그램 없음"이 아니라 구조 변경/차단으로 취급 (규칙 13)
    if (p === 1 && items.length === 0) {
      throw new Error("파싱 0건 — 사이트 구조 변경 또는 차단 가능성");
    }
    items.forEach((it) => bySeq.set(it.seq, it));
    if (items.length < 10) break;
  }
  return [...bySeq.values()];
}

function detailUrl(seq) {
  return `https://extra.snu.ac.kr/ptfol/pgm/view.do?pgmSeq=${seq}`;
}

module.exports = { fetchExtraPrograms, detailUrl, parseList };

if (require.main === module) {
  fetchExtraPrograms()
    .then((items) => {
      console.log(`${items.length}건 파싱`);
      items.forEach((i) =>
        console.log(`- [${i.seq}] ${i.category} | ${i.title} | 신청 ${i.applyPeriod} | ${i.mode}`)
      );
    })
    .catch((e) => {
      console.error("실패:", e.message);
      process.exit(1);
    });
}
