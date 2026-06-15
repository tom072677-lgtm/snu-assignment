// ⚠️ 격리 모듈 — 공모전 스크래핑 (위비티). 공식 오픈API가 없어 임시로 스크래핑한다.
// 개인용 한정. 공개 배포(구글플레이) 전에는 이 파일을 제거하거나 합법 소스로 교체할 것.
// (상업 플랫폼 데이터 무단 수집·재배포는 법적 분쟁 소지 — 잡코리아 v 사람인 판례 참고)
//
// 한계: 위비티 목록은 절대 마감일이 아니라 상대 D-day(예: D-45)만 제공한다.
//       deadline = 오늘 + N일로 근사하며, 접수예정 항목의 D-day는 '접수 시작'까지일 수 있어 근사값이다.
//       정확한 마감일이 필요하면 상세페이지를 추가로 긁어야 한다(현재는 목록만).

const cheerio = require("cheerio");

const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120 Safari/537.36";

function ymdDash(d) {
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function stableId(prefix, s) {
  let h = 5381;
  for (const c of String(s)) h = ((h << 5) + h + c.charCodeAt(0)) & 0x7fffffff;
  return `${prefix}_${h}`;
}

function pruned(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined || v === null) continue;
    const s = String(v).trim();
    if (s) out[k] = s;
  }
  return out;
}

async function fetchContests() {
  const url = "https://www.wevity.com/?c=find&s=1";
  const res = await fetch(url, {
    headers: {
      "User-Agent": UA,
      Accept:
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
      "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7",
      Referer: "https://www.wevity.com/",
      "Upgrade-Insecure-Requests": "1",
      "sec-ch-ua": '"Chromium";v="120", "Not?A_Brand";v="24"',
      "sec-ch-ua-mobile": "?0",
      "sec-ch-ua-platform": '"Windows"',
    },
  });
  if (!res.ok) throw new Error(`위비티 HTTP ${res.status}`);
  const html = await res.text();
  const $ = cheerio.load(html);

  const items = [];
  const today = new Date();
  $("ul.list > li").each((_, el) => {
    const $el = $(el);
    if ($el.hasClass("top")) return; // 헤더 행 제외

    const a = $el.find(".tit a").first();
    // 제목에서 SPECIAL 같은 배지(span) 제거 후 텍스트만
    const title = a.clone().children().remove().end().text().replace(/\s+/g, " ").trim();
    const href = (a.attr("href") || "").trim();
    if (!title || !href) return;

    const link = "https://www.wevity.com/" + href.replace(/^\//, "");
    const field = $el.find(".sub-tit").text().replace(/^\s*분야\s*:\s*/, "").trim();
    const organ = $el.find(".organ").text().replace(/\s+/g, " ").trim();
    const dayText = $el.find(".day").text().replace(/\s+/g, " ").trim(); // "D-45 접수예정"

    let deadline = null;
    const m = dayText.match(/D-(\d+)/);
    if (m) {
      const d = new Date(today);
      d.setDate(d.getDate() + parseInt(m[1], 10));
      deadline = ymdDash(d); // 근사값
    }
    const status = /접수예정/.test(dayText)
      ? "접수예정"
      : /마감|D-?day/i.test(dayText)
      ? "마감임박"
      : "접수중";

    const ix = (href.match(/ix=(\d+)/) || [])[1];
    items.push({
      id: stableId("con", ix || title),
      category: "contest",
      title,
      organization: organ || "주최 미상",
      url: link,
      source: "위비티",
      deadline,
      startDate: null,
      region: null,
      tags: field
        ? field.split(",").map((s) => s.trim()).filter(Boolean).slice(0, 4)
        : [],
      summary: null,
      extra: pruned({ field, status, dday: m ? `D-${m[1]}` : undefined }),
    });
  });

  if (!items.length) {
    // rule 13: 조용한 빈 리스트 금지 — 진단용 HTML 앞부분과 함께 던진다.
    const head = html.slice(0, 600).replace(/\s+/g, " ");
    throw new Error(`위비티 0건 파싱 — 구조 변경 가능. HTML앞부분: ${head}`);
  }
  return items;
}

module.exports = { fetchContests };
