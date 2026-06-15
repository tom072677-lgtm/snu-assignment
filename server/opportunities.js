// 대학생 혜택(장학·교육) 집계 모듈.
// 공식 오픈API를 호출해 앱의 통일 Opportunity 형식으로 정규화한다.
// 키는 환경변수로만 읽는다 (코드/리포에 키를 박지 않음):
//   ODCLOUD_KEY     — data.go.kr 학자금지원정보(대학생) serviceKey (장학)
//   WORK24_KDT_KEY  — 고용24 국민내일배움카드 훈련과정 authKey (교육)
// 공모전 스크래핑은 별도 격리 모듈에서 추가 예정(공개배포 전 정리).

const ODCLOUD_KEY = process.env.ODCLOUD_KEY || "";
const WORK24_KDT_KEY = process.env.WORK24_KDT_KEY || "";

// ── 작은 유틸 ───────────────────────────────────────────────
async function getJson(url) {
  // Node 18+ 전역 fetch 사용 (Render Node 20+).
  const r = await fetch(url, { headers: { Accept: "application/json" } });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
}

function ymd(d) {
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}`;
}

function ymdDash(d) {
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

// undefined/null/빈문자 제거한 extra 맵
function pruned(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined || v === null) continue;
    const s = String(v).trim();
    if (s) out[k] = s;
  }
  return out;
}

function stableId(prefix, s) {
  let h = 5381;
  for (const c of String(s)) h = ((h << 5) + h + c.charCodeAt(0)) & 0x7fffffff;
  return `${prefix}_${h}`;
}

// ── 장학 (data.go.kr odcloud) ───────────────────────────────
// 데이터가 버전(날짜)별 uddi로 나뉘어 있어 최신 uddi를 OAS 명세에서 자동 조회.
let _scholarPath = null;
let _scholarPathAt = 0;
const UDDI_TTL = 24 * 60 * 60 * 1000;

async function latestScholarshipPath() {
  if (_scholarPath && Date.now() - _scholarPathAt < UDDI_TTL) return _scholarPath;
  const spec = await getJson("https://infuser.odcloud.kr/oas/docs?namespace=15028252/v1");
  let best = null;
  let bestDate = "";
  for (const [p, v] of Object.entries(spec.paths || {})) {
    const sum = (v.get && v.get.summary) || "";
    const m = sum.match(/(\d{8})/);
    const d = m ? m[1] : "0";
    if (d >= bestDate) {
      bestDate = d;
      best = p;
    }
  }
  if (!best) throw new Error("장학 엔드포인트(uddi) 경로를 찾지 못함");
  _scholarPath = best;
  _scholarPathAt = Date.now();
  return best;
}

async function fetchScholarships(perPage = 1000) {
  if (!ODCLOUD_KEY) return [];
  const path = await latestScholarshipPath();
  const url =
    `https://api.odcloud.kr/api${path}` +
    `?serviceKey=${encodeURIComponent(ODCLOUD_KEY)}&page=1&perPage=${perPage}&returnType=JSON`;
  const j = await getJson(url);
  const rows = j.data || [];
  return rows.map((r) => ({
    id: stableId("sch", `${r["상품명"] || ""}${r["운영기관명"] || ""}${r["모집종료일"] || ""}`),
    category: "scholarship",
    title: r["상품명"] || "",
    organization: r["운영기관명"] || "",
    url: "https://www.kosaf.go.kr/ko/scholar.do",
    source: "data.go.kr",
    deadline: r["모집종료일"] || null, // YYYY-MM-DD
    startDate: r["모집시작일"] || null,
    region: null,
    tags: [],
    summary: r["상품구분"] || null,
    extra: pruned({
      capacity: r["선발인원 상세내용"],
      grade: r["성적기준 상세내용"],
      eligibility: r["소득기준 상세내용"],
      restriction: r["자격제한 상세내용"],
      univType: r["대학구분"],
      residency: r["지역거주여부 상세내용"],
    }),
  }));
}

// ── 교육 (고용24 국민내일배움카드 훈련과정) ─────────────────
async function fetchKdtCourses(pageSize = 100) {
  if (!WORK24_KDT_KEY) return [];
  const now = new Date();
  const end = new Date(now.getTime() + 1000 * 60 * 60 * 24 * 120); // 향후 120일 개강
  const url =
    `https://www.work24.go.kr/cm/openApi/call/hr/callOpenApiSvcInfo310L01.do` +
    `?authKey=${encodeURIComponent(WORK24_KDT_KEY)}&returnType=JSON&outType=1` +
    `&pageNum=1&pageSize=${pageSize}&srchTraStDt=${ymd(now)}&srchTraEndDt=${ymd(end)}` +
    `&sort=ASC&sortCol=2`;
  const j = await getJson(url);
  const rows = j.srchList || [];
  return rows.map((r) => ({
    id: stableId("edu", r.trprId || `${r.title || ""}${r.traStartDate || ""}`),
    category: "education",
    title: r.title || "",
    organization: r.subTitle || "",
    url: r.titleLink || "https://www.work24.go.kr",
    source: "고용24",
    deadline: null, // 접수마감 없음 → startDate 기준 정렬
    startDate: r.traStartDate || null, // YYYY-MM-DD
    region: (r.address || "").split(" ")[0] || null, // 시·도
    tags: [],
    summary: null,
    extra: pruned({
      cost: r.courseMan,
      capacity: r.yardMan,
      target: r.trainTarget,
      period:
        r.traStartDate && r.traEndDate
          ? `${r.traStartDate}~${r.traEndDate}`
          : undefined,
    }),
  }));
}

// 공모전(격리 스크래핑 모듈). 파일이 없거나 던져도 다른 소스엔 영향 없음.
let fetchContests = async () => [];
try {
  ({ fetchContests } = require("./contests"));
} catch (e) {
  console.warn("[opportunities] contests 모듈 없음 — 공모전 생략:", e.message);
}

// ── 집계: 소스별 실패 격리 + 마감필터 + dedup ──────────────
async function getOpportunities() {
  const settled = await Promise.allSettled([
    fetchScholarships(),
    fetchKdtCourses(),
    fetchContests(),
  ]);
  let items = [];
  const labels = ["scholarship", "education", "contest"];
  settled.forEach((s, i) => {
    if (s.status === "fulfilled") items.push(...s.value);
    else console.error(`[opportunities] ${labels[i]} 소스 실패:`, s.reason && s.reason.message);
  });

  // 마감 지난 항목 제거 (deadline 있고 오늘 이전)
  const today = ymdDash(new Date());
  items = items.filter((o) => !o.deadline || o.deadline >= today);

  // dedup: 정규화(title)+organization+deadline
  const seen = new Set();
  const out = [];
  for (const o of items) {
    const key = `${(o.title || "").replace(/\s+/g, "").toLowerCase()}|${o.organization}|${o.deadline || ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(o);
  }
  return out;
}

module.exports = { getOpportunities, fetchScholarships, fetchKdtCourses };
