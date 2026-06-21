// 대학생 혜택(장학·교육) 집계 모듈.
// 공식 오픈API를 호출해 앱의 통일 Opportunity 형식으로 정규화한다.
// 키는 환경변수로만 읽는다 (코드/리포에 키를 박지 않음):
//   ODCLOUD_KEY     — data.go.kr 학자금지원정보(대학생) serviceKey (장학)
//   WORK24_KDT_KEY  — 고용24 국민내일배움카드 훈련과정 authKey (교육)
// 공모전 스크래핑은 별도 격리 모듈에서 추가 예정(공개배포 전 정리).

const ODCLOUD_KEY = process.env.ODCLOUD_KEY || "";
const WORK24_KDT_KEY = process.env.WORK24_KDT_KEY || "";
const YOUTH_POLICY_KEY = process.env.YOUTH_POLICY_KEY || ""; // 온통청년 청년정책 apiKeyNm

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

// ── 청년정책 (온통청년 getPlcy) ─────────────────────────────
// 일자리 → intern(앱 라벨 "일자리"), 참여･기반 → activity(대외활동)만 수집.
// 지역은 전국 전부 수집하고, region(시·도)을 채워 앱에서 필터하게 한다.
// 법정동코드(zipCd) 앞2자리 → 시·도. 강원/전북 특별자치도 전환으로 구·신 코드 둘 다 매핑.
const SIDO_BY_PREFIX = {
  "11": "서울", "26": "부산", "27": "대구", "28": "인천", "29": "광주",
  "30": "대전", "31": "울산", "36": "세종", "41": "경기",
  "42": "강원", "51": "강원", "43": "충북", "44": "충남",
  "45": "전북", "52": "전북", "46": "전남", "47": "경북", "48": "경남", "50": "제주",
};

// zipCd 콤마목록 → 시·도 1개면 그 값, 0개/2개 이상(여러 지역에 걸침)이면 null(=전국, 앱에서 항상 노출).
// 근사: 한 시·도의 여러 구만 나열돼도 그 시·도로 판정(정상). 여러 시·도면 전국 취급(안전한 과다노출 방향).
function regionFromZipCd(zipCd) {
  const sidos = new Set();
  for (const code of String(zipCd || "").split(",")) {
    const sido = SIDO_BY_PREFIX[code.trim().slice(0, 2)];
    if (sido) sidos.add(sido);
  }
  return sidos.size === 1 ? [...sidos][0] : null;
}

// "20260615 ~ 20260630" / 단일 8자리 / "상시" 등 → 종료일 YYYY-MM-DD. 실패 시 null(상시).
function deadlineFromAplyYmd(aplyYmd) {
  const nums = String(aplyYmd || "").match(/\d{8}/g);
  if (!nums || !nums.length) return null;
  const end = nums[nums.length - 1]; // 구간이면 종료일, 단일이면 그 날짜
  return `${end.slice(0, 4)}-${end.slice(4, 6)}-${end.slice(6, 8)}`;
}

async function fetchYouthPolicies(pageSize = 100) {
  if (!YOUTH_POLICY_KEY) {
    console.warn("[opportunities] YOUTH_POLICY_KEY 없음 — 청년정책(일자리·대외활동) 생략");
    return [];
  }
  const base =
    `https://www.youthcenter.go.kr/go/ythip/getPlcy` +
    `?apiKeyNm=${encodeURIComponent(YOUTH_POLICY_KEY)}&rtnType=json&pageSize=${pageSize}`;
  const getPage = async (n) => {
    const j = await getJson(`${base}&pageNum=${n}`);
    return (j && j.result) || {};
  };

  const first = await getPage(1);
  const totCount = (first.pagging && first.pagging.totCount) || 0;
  let rows = first.youthPolicyList || [];

  // 나머지 페이지: 제한 동시성(콜드스타트 완화) + 페이지 상한(폭주 방지).
  const totalPages = Math.min(Math.ceil(totCount / pageSize), 30);
  if (totalPages > 1) {
    const nums = [];
    for (let n = 2; n <= totalPages; n++) nums.push(n);
    const CONC = 5;
    for (let i = 0; i < nums.length; i += CONC) {
      const batch = await Promise.all(nums.slice(i, i + CONC).map(getPage));
      for (const r of batch) rows.push(...(r.youthPolicyList || []));
    }
  }
  if (Math.ceil(totCount / pageSize) > 30) {
    console.warn(`[opportunities] 청년정책 ${totCount}건 중 상한 30페이지만 수집`);
  }

  const out = [];
  for (const r of rows) {
    const lcls = r.lclsfNm || "";
    let category;
    if (lcls === "일자리") category = "intern";
    else if (lcls.includes("참여")) category = "activity";
    else continue; // 그 외 분류(교육·금융복지·주거) 제외 — 사용자 확정 범위
    out.push({
      id: stableId("yth", r.plcyNo || `${r.plcyNm || ""}${lcls}`),
      category,
      title: r.plcyNm || "",
      organization: r.sprvsnInstCdNm || r.rgtrInstCdNm || "",
      url:
        r.aplyUrlAddr ||
        r.refUrlAddr1 ||
        `https://www.youthcenter.go.kr/youngPlcyUnif/youngPlcyUnifDtl.do?bizId=${r.plcyNo || ""}`,
      source: "온통청년",
      deadline: deadlineFromAplyYmd(r.aplyYmd),
      startDate: null,
      region: regionFromZipCd(r.zipCd),
      // 키워드는 검색·표시용. kInterestOptions 어휘와 달라 관심매칭엔 안 걸림(의도된 한계).
      tags: String(r.plcyKywdNm || "")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean)
        .slice(0, 4),
      summary: r.plcyExplnCn || null,
      extra: pruned({
        support: r.plcySprtCn,
        field: r.mclsfNm,
        applyPeriod: r.aplyYmd,
        ageMin: r.sprtTrgtMinAge,
        ageMax: r.sprtTrgtMaxAge,
      }),
    });
  }
  return out;
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
    fetchYouthPolicies(),
    fetchContests(),
  ]);
  let items = [];
  const errors = [];
  const labels = ["scholarship", "education", "youth", "contest"];
  settled.forEach((s, i) => {
    if (s.status === "fulfilled") {
      items.push(...s.value);
    } else {
      const msg = (s.reason && s.reason.message) || String(s.reason);
      console.error(`[opportunities] ${labels[i]} 소스 실패:`, msg);
      errors.push({ source: labels[i], message: String(msg).slice(0, 300) });
    }
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
  return { items: out, errors };
}

module.exports = { getOpportunities, fetchScholarships, fetchKdtCourses, fetchYouthPolicies };
