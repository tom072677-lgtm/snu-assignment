const express = require("express");
const ical = require("node-ical");
const https = require("https");
const http = require("http");
const webpush = require("web-push");
const { MongoClient } = require("mongodb");
const cheerio = require("cheerio");

// VAPID 설정 (없으면 Push 비활성화, 나머지 기능은 정상 동작)
const VAPID_PUBLIC = process.env.VAPID_PUBLIC;
const VAPID_PRIVATE = process.env.VAPID_PRIVATE;
const pushEnabled = !!(VAPID_PUBLIC && VAPID_PRIVATE);
if (pushEnabled) {
  webpush.setVapidDetails("mailto:admin@snu-app.com", VAPID_PUBLIC, VAPID_PRIVATE);
} else {
  console.warn("VAPID 환경변수 없음 — Push 알림 비활성화");
}

const app = express();
const PORT = process.env.PORT || 3001;

app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});
app.use(express.json());

// ──────────────────────────────────────────
// URL fetch (헤더 지원, 리다이렉트 자동 처리, POST 지원)
// ──────────────────────────────────────────
function fetchText(url, redirectCount = 0, extraHeaders = {}, method = "GET", body = null) {
  return new Promise((resolve, reject) => {
    if (redirectCount > 5) return reject(new Error("리다이렉트가 너무 많습니다."));

    const parsed = new URL(url);
    const bodyBuf = body ? Buffer.from(body, "utf8") : null;
    const options = {
      hostname: parsed.hostname,
      path: parsed.pathname + parsed.search,
      method: method,
      headers: {
        ...extraHeaders,
        ...(bodyBuf ? { "Content-Length": bodyBuf.length } : {}),
      },
    };

    const transport = parsed.protocol === "https:" ? https : http;
    const req = transport.request(options, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        return fetchText(res.headers.location, redirectCount + 1, extraHeaders).then(resolve).catch(reject);
      }
      if (res.statusCode !== 200) {
        res.setEncoding("utf8");
        let errBody = "";
        res.on("data", (c) => { errBody += c; });
        res.on("end", () => reject(new Error(`HTTP ${res.statusCode}: ${errBody.slice(0, 300)}`)));
        return;
      }
      res.setEncoding("utf8");
      let data = "";
      res.on("data", (chunk) => { data += chunk; });
      res.on("end", () => resolve(data));
    });

    req.on("error", reject);
    req.setTimeout(15000, () => req.destroy(new Error("요청 시간 초과 (15초)")));
    if (bodyBuf) req.write(bodyBuf);
    req.end();
  });
}

// ──────────────────────────────────────────
// Canvas API: 제출 여부 확인
// ──────────────────────────────────────────
async function isSubmitted(courseId, assignmentId, token) {
  try {
    const url = `https://myetl.snu.ac.kr/api/v1/courses/${courseId}/assignments/${assignmentId}/submissions/self`;
    const text = await fetchText(url, 0, { Authorization: `Bearer ${token}` });
    const data = JSON.parse(text);
    return ["submitted", "graded", "pending_review"].includes(data.workflow_state);
  } catch {
    return false; // 확인 실패 시 과제 유지 (안전 기본값)
  }
}

// ──────────────────────────────────────────
// Canvas iCal 파싱 유틸
// ──────────────────────────────────────────

function parseSummary(summary) {
  const match = (summary || "").match(/^(.*?)\s*\[([^\]]+)\]\s*$/);
  if (match) return { title: match[1].trim(), courseName: match[2].trim() };
  return { title: (summary || "").trim(), courseName: "" };
}

function buildAssignmentUrl(calendarUrl) {
  if (!calendarUrl) return "";
  const courseMatch = calendarUrl.match(/include_contexts=course_(\d+)/);
  const assignMatch = calendarUrl.match(/#assignment_(\d+)/);
  if (courseMatch && assignMatch) {
    return `https://myetl.snu.ac.kr/courses/${courseMatch[1]}/assignments/${assignMatch[1]}`;
  }
  return calendarUrl;
}

function parseEventDate(ev) {
  const start = ev.start;
  if (!start) return { date: null, dateOnly: false };
  if (start instanceof Date) {
    const isDateOnly = ev.start.dateOnly === true || (ev.dtstart && ev.dtstart.includes("VALUE=DATE"));
    if (isDateOnly) {
      // node-ical은 VALUE=DATE를 서버 로컬 자정으로 파싱함
      // eTL은 KST 기준이므로 +9h 보정으로 서버 시간대 무관하게 KST 날짜 추출
      const kst = new Date(start.getTime() + 9 * 60 * 60 * 1000);
      const y = kst.getUTCFullYear();
      const m = kst.getUTCMonth();
      const d = kst.getUTCDate();
      const deadline = new Date(Date.UTC(y, m, d, 14, 59, 0));
      return { date: deadline, dateOnly: false };
    }
    return { date: start, dateOnly: false };
  }
  return { date: null, dateOnly: false };
}

// ──────────────────────────────────────────
// POST /api/sync-ical
// body: { icalUrl, apiToken?, days? }
// ──────────────────────────────────────────
app.post("/api/sync-ical", async (req, res) => {
  let { icalUrl, apiToken, days } = req.body;
  const lookAheadDays = Math.min(Math.max(parseInt(days) || 14, 1), 60);

  if (!icalUrl) {
    return res.status(400).json({ error: "icalUrl이 필요합니다." });
  }

  icalUrl = icalUrl.trim().replace(/^webcal:\/\//i, "https://");

  try {
    const parsed = new URL(icalUrl);
    if (parsed.protocol !== "https:" || parsed.hostname !== "myetl.snu.ac.kr") {
      return res.status(400).json({ error: "유효한 eTL iCal URL을 입력해주세요. (myetl.snu.ac.kr 만 허용)" });
    }
  } catch {
    return res.status(400).json({ error: "유효한 URL을 입력해주세요." });
  }

  try {
    console.log(`[sync] fetch: ${icalUrl.slice(0, 70)}...`);
    const text = await fetchText(icalUrl);
    console.log(`[sync] 수신: ${text.length} bytes`);

    const events = ical.sync.parseICS(text);
    const now = new Date();
    const assignments = [];

    for (const key of Object.keys(events)) {
      const ev = events[key];
      if (ev.type !== "VEVENT") continue;

      const { date: dueDate, dateOnly } = parseEventDate(ev);
      if (!dueDate || isNaN(dueDate.getTime())) continue;

      const diffDays = (dueDate - now) / (1000 * 60 * 60 * 24);
      if (diffDays < 0 || diffDays > lookAheadDays) continue;

      const { title, courseName } = parseSummary(ev.summary);
      if (!title) continue;

      const uidMatch = (ev.uid || "").match(/assignment-(\d+)/);
      const etlId = uidMatch ? uidMatch[1] : (ev.uid || key).slice(0, 20);
      const assignmentUrl = buildAssignmentUrl(ev.url);

      const courseMatch = assignmentUrl.match(/courses\/(\d+)/);
      const assignMatch = assignmentUrl.match(/assignments\/(\d+)/);

      assignments.push({
        etlId,
        title,
        courseName,
        dueDate: dueDate.toISOString(),
        dateOnly,
        url: assignmentUrl,
        courseId: courseMatch ? courseMatch[1] : null,
        assignmentId: assignMatch ? assignMatch[1] : null,
      });
    }

    // API 토큰이 있으면 제출된 과제 필터링
    let filtered = assignments;
    if (apiToken) {
      console.log(`[sync] 제출 여부 확인 중 (${assignments.length}개)...`);
      const results = await Promise.all(
        assignments.map(async (a) => {
          if (!a.courseId || !a.assignmentId) return true;
          const submitted = await isSubmitted(a.courseId, a.assignmentId, apiToken);
          return !submitted;
        })
      );
      filtered = assignments.filter((_, i) => results[i]);
      console.log(`[sync] 제출 제외 후: ${filtered.length}개`);
    }

    // courseId/assignmentId도 클라이언트에 전달 (상세 화면에서 활용)
    const output = filtered;

    output.sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate));
    console.log(`[sync] 완료: ${output.length}개 과제`);
    res.json(output);

  } catch (err) {
    console.error(`[sync] 오류: ${err.message}`);
    res.status(500).json({ error: `iCal 불러오기 실패: ${err.message}` });
  }
});

// ──────────────────────────────────────────
// POST /api/assignment-detail
// body: { courseId, assignmentId, apiToken }
// ──────────────────────────────────────────

app.post("/api/assignment-detail", async (req, res) => {
  const { courseId, assignmentId, apiToken } = req.body;
  if (!courseId || !assignmentId || !apiToken) {
    return res.status(400).json({ error: "courseId, assignmentId, apiToken 필요" });
  }

  let data;
  try {
    const url = `https://myetl.snu.ac.kr/api/v1/courses/${courseId}/assignments/${assignmentId}`;
    const text = await fetchText(url, 0, { Authorization: `Bearer ${apiToken}` });
    data = JSON.parse(text);
  } catch (err) {
    const status = /HTTP 40[13]/.test(err.message) ? 401 : 502;
    return res.status(status).json({ error: `Canvas API 오류: ${err.message}` });
  }

  const rawHtml = data.description || "";
  const $ = cheerio.load(rawHtml);

  // 평문 설명 추출 (HTML 태그 제거)
  const descriptionText = $.text().replace(/\s+/g, " ").trim();

  // Canvas 파일 링크 추출 (중복 제거)
  const BASE = "https://myetl.snu.ac.kr";
  const seen = new Set();
  const attachments = [];
  $("a[href]").each((_, el) => {
    let href = $(el).attr("href") || "";
    // 상대 경로 정규화
    if (href.startsWith("/")) href = BASE + href;
    // Canvas 파일 다운로드 링크만 포함
    if (!/myetl\.snu\.ac\.kr/.test(href)) return;
    if (!/\/files\/\d+|\/download/.test(href)) return;
    if (seen.has(href)) return;
    seen.add(href);
    const name = $(el).text().trim() || href.split("/").pop() || "파일";
    attachments.push({ name, url: href });
  });

  res.json({
    name: data.name || "",
    descriptionText,
    attachments,
    submissionTypes: data.submission_types || [],
    allowedExtensions: data.allowed_extensions || [],
  });
});

// ──────────────────────────────────────────
// 학교 소식 크롤링
// ──────────────────────────────────────────

// 학사일정 기본값 (공식 사이트 크롤링 실패 시 사용)
const fallbackSchedule = [
  { title: "봄학기 개강", date: "2026-03-02", source: "snu" },
  { title: "수강변경 기간", date: "2026-03-02", endDate: "2026-03-13", source: "snu" },
  { title: "중간고사", date: "2026-04-20", endDate: "2026-04-25", source: "snu" },
  { title: "수강취소 기간", date: "2026-04-27", endDate: "2026-05-01", source: "snu" },
  { title: "기말고사", date: "2026-06-15", endDate: "2026-06-20", source: "snu" },
  { title: "봄학기 종강", date: "2026-06-19", source: "snu" },
  { title: "관악제", date: "2026-05-12", endDate: "2026-05-14", source: "snu" },
];

// SNU 공식 이벤트 페이지 크롤링 (YYYY.MM.DD 형식 파싱)
function parseSnuDate(str) {
  const m = str.match(/(\d{4})\.(\d{2})\.(\d{2})/);
  if (!m) return null;
  return `${m[1]}-${m[2]}-${m[3]}`;
}

async function fetchSnuEvents() {
  try {
    const html = await fetchText("https://www.snu.ac.kr/snunow/events", 0, { "User-Agent": "Mozilla/5.0" });
    const $ = cheerio.load(html);
    const items = [];
    $("span.texts").each((i, el) => {
      const title = $(el).find("span.title").text().trim();
      const pointText = $(el).find("span.point").text().trim();
      if (!title || !pointText) return;
      const dates = pointText.match(/\d{4}\.\d{2}\.\d{2}/g) || [];
      const startDate = parseSnuDate(dates[0]);
      const endDate = dates[1] ? parseSnuDate(dates[1]) : null;
      if (!startDate) return;
      items.push({ title, date: startDate, ...(endDate ? { endDate } : {}), source: "snu_events" });
    });
    console.log(`[events] SNU 공식 이벤트 ${items.length}개 크롤링 완료`);
    return items;
  } catch (err) {
    console.error("[events] SNU 이벤트 크롤링 오류:", err.message);
    return [];
  }
}

function parseRSS(xml) {
  const items = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/g;
  let match;
  while ((match = itemRegex.exec(xml)) !== null) {
    const block = match[1];
    const getTag = (tag) => {
      const m = block.match(new RegExp(`<${tag}>(?:<!\\[CDATA\\[)?([\\s\\S]*?)(?:\\]\\]>)?<\\/${tag}>`));
      return m ? m[1].trim() : "";
    };
    const title = getTag("title");
    const link = getTag("link") || block.match(/<link\s*\/?>(.*?)<\/link>/)?.[1]?.trim() || "";
    const pubDate = getTag("pubDate");
    const category = getTag("category");
    if (title) items.push({ title, link, pubDate, category });
  }
  return items;
}

async function fetchWeSnuRSS() {
  try {
    const xml = await fetchText("https://we.snu.ac.kr/feed/");
    const items = parseRSS(xml);
    return items.slice(0, 10).map((item) => ({
      title: item.title,
      url: item.link,
      date: item.pubDate ? new Date(item.pubDate).toISOString() : null,
      category: item.category || "총학생회",
      source: "wesnu",
    }));
  } catch (err) {
    console.error("[events] 총학 RSS 오류:", err.message);
    return [];
  }
}

async function fetchDongariNotices() {
  try {
    const html = await fetchText("https://dongari.snu.ac.kr/%EA%B3%B5%EC%A7%80%EC%82%AC%ED%95%AD/?mod=list");
    const $ = cheerio.load(html);
    const items = [];
    $("ul.board_body li").each((i, el) => {
      const title = $(el).find("div.cut-strings").text().trim();
      const href = $(el).find("div.subject a").attr("href");
      const date = $(el).find("span.date").text().trim();
      if (title && date) {
        items.push({
          title,
          url: href ? `https://dongari.snu.ac.kr${href}` : null,
          date: new Date(date).toISOString(),
          category: "동아리연합회",
          source: "dongari",
        });
      }
    });
    return items.slice(0, 10);
  } catch (err) {
    console.error("[events] 동아리연합회 오류:", err.message);
    return [];
  }
}

app.get("/api/events", async (req, res) => {
  const [wesnu, dongari, snuEvents] = await Promise.all([
    fetchWeSnuRSS(),
    fetchDongariNotices(),
    fetchSnuEvents(),
  ]);

  const notices = [...wesnu, ...dongari].sort((a, b) => {
    if (!a.date) return 1;
    if (!b.date) return -1;
    return new Date(b.date) - new Date(a.date);
  });

  // SNU 공식 이벤트가 있으면 사용, 없으면 fallback
  const schedule = snuEvents.length > 0
    ? [...fallbackSchedule, ...snuEvents]
    : fallbackSchedule;

  res.json({ schedule, notices });
});

// ──────────────────────────────────────────
// 푸시 알림
// ──────────────────────────────────────────

// { endpoint → { subscription, tasks: [{etlId, dueDate, title, courseName}] } }
const pushStore = new Map();
const sentKeys = new Set(); // "endpoint:etlId:Nh" - 중복 발송 방지
const HOURLY_DEADLINE_TARGETS = Array.from({ length: 24 }, (_, i) => 24 - i);

// ── 구독 MongoDB 영속화 ──────────────────────
const MONGO_URI = process.env.MONGO_URI;
let dbCol = null; // subscriptions 컬렉션 (연결 전엔 null)

async function connectMongo() {
  if (!MONGO_URI) {
    console.warn("[mongo] MONGO_URI 없음 — 구독 메모리 전용");
    return;
  }
  try {
    const client = new MongoClient(MONGO_URI);
    await client.connect();
    dbCol = client.db("sharap").collection("subscriptions");
    // 시작 시 저장된 구독 로드
    const docs = await dbCol.find({}).toArray();
    docs.forEach((doc) => pushStore.set(doc._id, { subscription: doc.subscription, tasks: doc.tasks || [] }));
    console.log(`[mongo] 구독 로드: ${pushStore.size}개`);
  } catch (err) {
    console.error("[mongo] 연결 실패:", err.message);
  }
}

async function saveSubscription(endpoint, data) {
  if (!dbCol) return;
  try {
    await dbCol.replaceOne({ _id: endpoint }, { _id: endpoint, ...data }, { upsert: true });
  } catch (err) {
    console.error("[mongo] 저장 실패:", err.message);
  }
}

async function deleteSubscription(endpoint) {
  if (!dbCol) return;
  try {
    await dbCol.deleteOne({ _id: endpoint });
  } catch (err) {
    console.error("[mongo] 삭제 실패:", err.message);
  }
}

connectMongo();

function buildBombProgressBar(diffH) {
  const totalBlocks = 12;
  const remainingRatio = Math.max(0, Math.min(1, diffH / 24));
  const filled = Math.max(0, Math.min(totalBlocks, Math.ceil(remainingRatio * totalBlocks)));
  return "█".repeat(filled) + "░".repeat(totalBlocks - filled);
}

function buildPushPayload(task, h, diffH) {
  const isUserEvent = !!task.targets;
  const name = task.courseName || task.title;
  const safeHours = Math.max(0, diffH);
  const wholeHours = Math.floor(safeHours);
  const minutes = Math.floor((safeHours - wholeHours) * 60);
  const timeText = `${String(wholeHours).padStart(2, "0")}:${String(minutes).padStart(2, "0")} 남음`;
  const id = task.etlId || task.id || task.title;

  return {
    title: isUserEvent ? `💣 일정 ${h}시간 전` : `💣 ${name}`,
    body: isUserEvent
      ? `"${name}" ${h}시간 전\n${timeText} ${buildBombProgressBar(safeHours)}`
      : `${task.title} 마감 ${h}시간 전\n${timeText} ${buildBombProgressBar(safeHours)}`,
    icon: "./icon-192.png",
    badge: "./icon-192.png",
    tag: `${isUserEvent ? "event" : "deadline"}-bomb-${id}`,
    renotify: true,
    requireInteraction: true,
    data: { url: task.url || "./" },
  };
}

// ── T Map 도보 경로 ──────────────────────────────────────────────────────────
// ── T Map 공통 헬퍼 ───────────────────────────────────────────────────────────
async function fetchTmapRoute(tmapUrl, body) {
  const key = process.env.TMAP_API_KEY;
  if (!key) throw new Error("TMAP_API_KEY not configured");
  const resp = await fetch(tmapUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json", appKey: key },
    body: JSON.stringify(body),
  });
  if (!resp.ok) throw new Error(`T Map HTTP ${resp.status}`);
  const data = await resp.json();
  if (data.error) throw new Error(`T Map error: ${data.error.id} ${data.error.code}`);
  const features = data.features || [];
  // summary는 totalTime/totalDistance가 있는 첫 번째 feature
  const summary = features.find(
    f => f.properties?.totalTime != null && f.properties?.totalDistance != null
  );
  if (!summary) throw new Error("T Map: no route found");
  const path = [];
  const steps = [];
  for (const f of features) {
    if (f.geometry?.type === "LineString") {
      for (const [x, y] of f.geometry.coordinates) {
        path.push([y, x]); // T Map [lng,lat] → [lat,lng]
      }
    } else if (f.geometry?.type === "Point") {
      const p = f.properties || {};
      if (p.description) {
        steps.push({
          description: p.description,
          distance: p.distance ?? 0,   // meters to next step
          turnType: p.turnType ?? 0,
        });
      }
    }
  }
  return {
    duration: summary.properties.totalTime,     // seconds
    distance: summary.properties.totalDistance, // meters
    path,
    steps,
  };
}

// ── 도보 경로 (T Map pedestrian) ──────────────────────────────────────────────
app.post("/api/route/tmap/pedestrian", async (req, res) => {
  const { olat, olng, dlat, dlng } = req.body;
  if (olat == null || olng == null || dlat == null || dlng == null)
    return res.status(400).json({ error: "파라미터 필요" });
  try {
    const result = await fetchTmapRoute(
      "https://apis.openapi.sk.com/tmap/routes/pedestrian?version=1",
      { startX: String(olng), startY: String(olat), endX: String(dlng), endY: String(dlat),
        reqCoordType: "WGS84GEO", resCoordType: "WGS84GEO", startName: "start", endName: "end" }
    );
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── 자동차 경로 (T Map car) ───────────────────────────────────────────────────
app.post("/api/route/tmap/car", async (req, res) => {
  const { olat, olng, dlat, dlng } = req.body;
  if (olat == null || olng == null || dlat == null || dlng == null)
    return res.status(400).json({ error: "파라미터 필요" });
  try {
    const result = await fetchTmapRoute(
      "https://apis.openapi.sk.com/tmap/routes?version=1",
      { startX: String(olng), startY: String(olat), endX: String(dlng), endY: String(dlat),
        reqCoordType: "WGS84GEO", resCoordType: "WGS84GEO", startName: "start", endName: "end" }
    );
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── 버스 API 임시 진단 엔드포인트 ─────────────────────────────────────────────
app.get("/api/debug/bus-raw", async (req, res) => {
  const key = process.env.SEOUL_BUS_API_KEY;
  const { stId, busRouteId } = req.query;
  if (!key) return res.json({ error: "SEOUL_BUS_API_KEY 없음" });
  if (!stId || !busRouteId) return res.json({ error: "stId, busRouteId 필요", key_first8: key.slice(0,8) });
  const url = `http://ws.bus.go.kr/api/rest/arrive/getArrInfoByRoute`
    + `?serviceKey=${encodeURIComponent(key)}&stId=${stId}&busRouteId=${busRouteId}&resultType=json`;
  try {
    const raw = await fetchText(url);
    const parsed = JSON.parse(raw);
    res.json({ url_used: url.slice(0, 120) + '...', key_first8: key.slice(0,8), raw_trimmed: raw.slice(0, 500), parsed });
  } catch(e) {
    res.json({ error: e.message, key_first8: key.slice(0,8) });
  }
});

// ── 버스/지하철 실시간 도착 정보 ──────────────────────────────────────────────
async function fetchBusArrival(stId, busRouteId) {
  const key = process.env.SEOUL_BUS_API_KEY;
  if (!key || !stId || !busRouteId) return null;

  // getArrInfoByRoute: 노선+정류소 ID로 도착 예정 조회
  const url = `http://ws.bus.go.kr/api/rest/arrive/getArrInfoByRoute`
    + `?serviceKey=${encodeURIComponent(key)}`
    + `&stId=${stId}&busRouteId=${busRouteId}&resultType=json`;
  const data = JSON.parse(await fetchText(url));
  const items = data.msgBody?.itemList ?? [];
  if (!items.length) return null;
  return items[0]?.arrmsg1 ?? null;
}

async function fetchSubwayArrival(routeName, startStation, subwayCode) {
  const key = process.env.SEOUL_SUBWAY_API_KEY;
  if (!key) return null;

  // 역명 정리: 괄호 제거, "역" 접미사 제거
  const cleanStation = startStation
    .replace(/\(.*?\)/g, '')
    .replace(/역$/, '')
    .trim();

  const url = `http://swopenAPI.seoul.go.kr/api/subway`
    + `/${encodeURIComponent(key)}/json/realtimeStationArrival/0/5`
    + `/${encodeURIComponent(cleanStation)}`;
  const data = JSON.parse(await fetchText(url));

  const list = data.realtimeArrivalList ?? data.errorMessage?.list ?? [];
  if (!Array.isArray(list) || list.length === 0) return null;

  // ODSAY subwayCode → Seoul API subwayId 매핑
  const codeMap = {
    1:1001, 2:1002, 3:1003, 4:1004, 5:1005,
    6:1006, 7:1007, 8:1008, 9:1009,
    21:1063, 22:1065, 101:1067, 104:1075, 108:1077,
    109:1092, 110:1093,
  };
  const targetId = subwayCode ? String(codeMap[subwayCode] ?? '') : '';

  // subwayCode 매칭 우선, 없으면 routeName 부분 매칭
  const match = list.find(a => targetId && a.subwayId === targetId)
    ?? list.find(a => a.trainLineNm?.includes(routeName));

  return match?.arvlMsg2 ?? null;
}


app.post("/api/transit/arrival", async (req, res) => {
  const { legType, routeName, startStation, subwayCode, stId, busRouteId } = req.body;
  if (!legType) return res.status(400).json({ error: "파라미터 필요" });
  try {
    let arrmsg = null;
    if (legType === "subway") {
      arrmsg = await fetchSubwayArrival(routeName, startStation, subwayCode);
    } else if (legType === "bus") {
      arrmsg = await fetchBusArrival(stId, busRouteId);
    }
    res.json({ arrmsg });
  } catch (err) {
    console.error("[transit/arrival]", err.message);
    res.json({ arrmsg: null });
  }
});

// ── 자전거 경로 (OSRM) ────────────────────────────────────────────────────────
app.post("/api/route/osrm/bike", async (req, res) => {
  const { olat, olng, dlat, dlng } = req.body;
  if (olat == null || olng == null || dlat == null || dlng == null)
    return res.status(400).json({ error: "파라미터 필요" });
  try {
    const url = `https://routing.openstreetmap.de/routed-bike/route/v1/bike/${olng},${olat};${dlng},${dlat}?overview=full&geometries=geojson`;
    const data = JSON.parse(await fetchText(url));
    if (data.code !== "Ok" || !data.routes || data.routes.length === 0)
      return res.status(404).json({ error: `자전거 경로 없음 (${data.code ?? "unknown"})` });
    const route = data.routes[0];
    const coords = route.geometry?.coordinates ?? [];
    const path = coords.map(([lng, lat]) => [lat, lng]); // OSRM은 [lng,lat] → [lat,lng]으로 변환
    res.json({ duration: route.duration, distance: route.distance, path });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── ODSAY 단일 경로 객체 → 클라이언트 shape 변환 ─────────────────────────────
function buildOdsayRoute(pathObj) {
  const info = pathObj.info;
  if (!info) throw new Error("ODSAY info 없음");
  const subPaths = Array.isArray(pathObj.subPath) ? pathObj.subPath : null;
  if (!subPaths) throw new Error("ODSAY subPath 없음");

  const duration = (info.totalTime || 0) * 60; // 분 → 초
  const distance = info.totalDistance || 0;
  const fare = info.payment || 0;

  const legs = [];
  const allCoords = [];
  for (const sub of subPaths) {
    const type = sub.trafficType === 1 ? 'subway'
               : sub.trafficType === 2 ? 'bus'
               : 'walk';
    const name = sub.lane?.[0]?.name || sub.lane?.[0]?.subwayCode?.toString() || '';
    const color = sub.lane?.[0]?.subwayColor || sub.lane?.[0]?.busColor || '#4CAF50';
    const subwayCode = type === 'subway' ? (sub.lane?.[0]?.subwayCode ?? null) : null;
    const stId = type === 'bus' ? (sub.startLocalStationID ? String(sub.startLocalStationID) : null) : null;
    const busRouteId = type === 'bus' ? (sub.lane?.[0]?.busLocalBlID ? String(sub.lane[0].busLocalBlID) : null) : null;
    const passStations = (sub.passStopList?.stations || [])
      .map(st => st.stationName || st.arsId || '')
      .filter(Boolean);
    legs.push({
      type,
      name,
      color: color.startsWith('#') ? color : `#${color}`,
      duration: (sub.sectionTime || 0) * 60,
      distance: sub.distance || 0,
      startStation: sub.startName || null,
      endStation: sub.endName || null,
      subwayCode,
      stId,
      busRouteId,
      stations: passStations,
    });
    if (type === 'walk' && sub.startX && sub.startY) {
      allCoords.push([parseFloat(sub.startY), parseFloat(sub.startX)]);
    }
    const stations = sub.passStopList?.stations || [];
    for (const st of stations) {
      if (st.x && st.y) allCoords.push([parseFloat(st.y), parseFloat(st.x)]);
    }
  }

  return { duration, distance, fare, path: allCoords, legs };
}

// ── ODSAY 대중교통 경로 ───────────────────────────────────────────────────────
app.get("/api/route/odsay/transit", async (req, res) => {
  const { olat, olng, dlat, dlng } = req.query;
  if (!olat || !olng || !dlat || !dlng)
    return res.status(400).json({ error: "파라미터 필요" });

  const odsayKey = process.env.ODSAY_API_KEY?.trim();
  if (!odsayKey)
    return res.status(500).json({ error: "ODSAY_API_KEY not configured" });

  try {
    const params = new URLSearchParams({ SX: String(olng), SY: String(olat), EX: String(dlng), EY: String(dlat), apiKey: odsayKey });
    const url = `https://api.odsay.com/v1/api/searchPubTransPathT?${params}`;
    const resp = await fetch(url);
    if (!resp.ok) {
      const body = await resp.text();
      throw new Error(`ODSAY HTTP ${resp.status}: ${body.slice(0, 200)}`);
    }
    let data;
    try { data = await resp.json(); }
    catch { throw new Error("ODSAY 응답이 JSON이 아닙니다"); }

    if (data.error) throw new Error(`ODSAY 오류: ${JSON.stringify(data.error)}`);

    const rawPaths = data.result?.path || [];
    if (rawPaths.length === 0)
      throw new Error(`ODSAY 경로 없음 (raw: ${JSON.stringify(data).slice(0, 200)})`);

    // 최대 3개 경로 변환 (변환 실패한 경로는 건너뜀)
    const routes = [];
    for (const pathObj of rawPaths.slice(0, 3)) {
      try { routes.push(buildOdsayRoute(pathObj)); }
      catch (_) { /* invalid path — skip */ }
    }
    if (routes.length === 0) throw new Error("유효한 경로를 찾을 수 없습니다");

    // routes 배열 반환 + 하위 호환을 위해 routes[0] 필드도 함께
    res.json({ routes, ...routes[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 장소 검색 (카카오 로컬 API 프록시)
// 좌표가 제공된 경우: "서울대학교 {q}" + "{q}" 이중 검색 후 SNU 결과 우선 병합
// "~역" 쿼리: SW8(지하철역) 카테고리 검색 결과를 맨 앞에 추가
app.get("/api/search-place", async (req, res) => {
  const { q, x, y } = req.query;
  if (!q) return res.status(400).json({ error: "q 필요" });
  const BASE = "https://dapi.kakao.com/v2/local/search/keyword.json";
  const headers = { Authorization: `KakaoAK ${KAKAO_REST_KEY}` };
  const toResult = (d) => ({
    name: d.place_name,
    address: d.road_address_name || d.address_name,
    lat: parseFloat(d.y),
    lng: parseFloat(d.x),
    category: d.category_group_name || "",
  });
  const deduped = (docs) => {
    const seen = new Set();
    const out = [];
    for (const d of docs) {
      const key = d.place_name + "|" + (d.road_address_name || d.address_name);
      if (!seen.has(key)) { seen.add(key); out.push(d); }
    }
    return out;
  };
  // "~역"으로 끝나는 쿼리면 SW8(지하철역) 키워드 검색을 별도로 실행
  const isStationQuery = q.trim().endsWith("역");
  try {
    // SW8 지하철역 검색 (실패해도 무시)
    let stationDocs = [];
    if (isStationQuery) {
      try {
        const stText = await fetchText(
          `${BASE}?query=${encodeURIComponent(q.trim())}&category_group_code=SW8&size=5`,
          0, headers
        );
        stationDocs = JSON.parse(stText).documents || [];
      } catch (_) { /* SW8 검색 실패 시 무시 */ }
    }

    if (x && y) {
      // SNU 캠퍼스 좌표 제공 시 이중 검색: "서울대학교 {q}" 결과를 앞에 배치
      // snuDocs: radius=5000 유지 (SNU 내 장소 우선)
      // generalDocs: radius 제거 (전국 검색, 판교 등 먼 곳도 검색 가능)
      const snuCoords = `&x=${x}&y=${y}&radius=5000&sort=accuracy`;
      const generalCoords = `&x=${x}&y=${y}&sort=accuracy`;
      const [snuText, generalText] = await Promise.all([
        fetchText(`${BASE}?query=${encodeURIComponent("서울대학교 " + q)}&size=5${snuCoords}`, 0, headers),
        fetchText(`${BASE}?query=${encodeURIComponent(q)}&size=15${generalCoords}`, 0, headers),
      ]);
      const snuDocs = JSON.parse(snuText).documents || [];
      const generalDocs = JSON.parse(generalText).documents || [];
      // 병합 순서: 지하철역 → SNU → 일반 (중복 제거)
      const merged = deduped([...stationDocs, ...snuDocs, ...generalDocs]);
      return res.json(merged.slice(0, 15).map(toResult));
    }
    // 좌표 없으면 일반 검색
    const text = await fetchText(`${BASE}?query=${encodeURIComponent(q)}&size=15`, 0, headers);
    const generalDocs = JSON.parse(text).documents || [];
    const merged = deduped([...stationDocs, ...generalDocs]);
    res.json(merged.slice(0, 15).map(toResult));
  } catch (err) {
    console.error("[search-place]", err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get("/api/push/vapid-public-key", (req, res) => {
  if (!pushEnabled) return res.status(503).json({ error: "Push 비활성화" });
  res.json({ key: VAPID_PUBLIC });
});

app.post("/api/push/subscribe", (req, res) => {
  if (!pushEnabled) return res.status(503).json({ error: "Push 비활성화" });
  const { subscription, tasks } = req.body;
  if (!subscription?.endpoint) return res.status(400).json({ error: "subscription 필요" });
  const data = { subscription, tasks: tasks || [] };
  pushStore.set(subscription.endpoint, data);
  saveSubscription(subscription.endpoint, data);
  console.log(`[push] 구독 등록: ${pushStore.size}개`);
  res.json({ ok: true });
});

// 5분마다 알림 체크 (과제: 24h~1h 매시간, 사용자 일정: task.targets 사용)
const DEFAULT_TARGETS = HOURLY_DEADLINE_TARGETS;
setInterval(async () => {
  const now = new Date();
  const WINDOW = 6 / 60; // ±6분 허용

  for (const [endpoint, { subscription, tasks }] of pushStore) {
    for (const task of tasks) {
      const due = new Date(task.dueDate);
      const diffH = (due - now) / (1000 * 60 * 60);
      if (diffH < 0) continue;

      const targets = task.targets || DEFAULT_TARGETS;
      for (const h of targets) {
        if (diffH <= h + WINDOW && diffH > h - WINDOW) {
          const key = `${endpoint}:${task.etlId}:${h}`;
          if (sentKeys.has(key)) continue;
          sentKeys.add(key);

          const name = task.courseName || task.title;
          try {
            await webpush.sendNotification(subscription, JSON.stringify(buildPushPayload(task, h, diffH)));
            console.log(`[push] 알림 발송: ${name} (${h}h)`);
          } catch (err) {
            console.error(`[push] 발송 실패:`, err.message);
            if (err.statusCode === 410) { pushStore.delete(endpoint); deleteSubscription(endpoint); }
          }
        }
      }
    }
  }
}, 5 * 60 * 1000);

// ──────────────────────────────────────────
// Instagram 공식 API (OAuth 방식)
// ──────────────────────────────────────────

const IG_APP_ID     = process.env.IG_APP_ID     || "975791108172537";
const IG_APP_SECRET = process.env.IG_APP_SECRET || "";
const IG_REDIRECT   = process.env.IG_REDIRECT   || "https://snu-assignment-server.onrender.com/api/instagram/callback";

// 액세스 토큰 저장 (메모리 + 환경변수 폴백)
// 서버 재시작 후에도 유지되도록 환경변수 IG_ACCESS_TOKEN 사용
let igAccessToken = process.env.IG_ACCESS_TOKEN || "";
const igPostCache = new Map(); // 게시물 캐시 (30분)

// ─── OAuth 콜백 (사장님이 승인 후 리다이렉트되는 곳) ───
app.get("/api/instagram/callback", async (req, res) => {
  const { code, error } = req.query;
  if (error || !code) {
    return res.send("Instagram 연결 실패: " + (error || "코드 없음"));
  }
  try {
    // 단기 토큰 발급
    const params = new URLSearchParams({
      client_id:     IG_APP_ID,
      client_secret: IG_APP_SECRET,
      grant_type:    "authorization_code",
      redirect_uri:  IG_REDIRECT,
      code,
    });
    const shortRes = await fetchText(
      `https://api.instagram.com/oauth/access_token`,
      0,
      { "Content-Type": "application/x-www-form-urlencoded" },
      "POST",
      params.toString()
    );
    const { access_token: shortToken } = JSON.parse(shortRes);

    // 장기 토큰으로 교환 (60일 유효)
    const longRes = await fetchText(
      `https://graph.instagram.com/access_token?grant_type=ig_exchange_token&client_secret=${IG_APP_SECRET}&access_token=${shortToken}`
    );
    const { access_token: longToken } = JSON.parse(longRes);
    igAccessToken = longToken;

    console.log("[ig] 액세스 토큰 발급 완료! Render 환경변수 IG_ACCESS_TOKEN에 저장하세요.");
    res.send("<h2>✅ Instagram 연결 완료!</h2><p>Render 대시보드 → Environment → IG_ACCESS_TOKEN에 토큰을 저장하세요.</p>");
  } catch (err) {
    console.error("[ig] 토큰 발급 오류:", err.message);
    res.status(500).send("토큰 발급 실패: " + err.message);
  }
});

// ─── 게시물 조회 ───
async function fetchInstagramPosts() {
  if (!igAccessToken) throw new Error("액세스 토큰 없음 — 사장님 승인 필요");

  const cached = igPostCache.get("posts");
  if (cached && Date.now() - cached.fetchedAt < 30 * 60 * 1000) {
    console.log("[ig] 캐시 사용");
    return cached.posts;
  }

  console.log("[ig] Instagram API 요청");
  const text = await fetchText(
    `https://graph.instagram.com/v21.0/me/media?fields=id,caption,media_type,media_url,thumbnail_url,timestamp,permalink&limit=5&access_token=${igAccessToken}`
  );
  const data = JSON.parse(text);
  if (data.error) throw new Error(data.error.message);

  const posts = (data.data || []).map((p) => ({
    id:        p.id,
    url:       p.permalink,
    imageUrl:  p.media_url || p.thumbnail_url || "",
    caption:   p.caption || "",
    date:      p.timestamp,
  }));

  igPostCache.set("posts", { posts, fetchedAt: Date.now() });
  console.log(`[ig] 게시물 ${posts.length}개 수집`);
  return posts;
}

// ─── 인증 URL 생성 (사장님에게 보낼 링크) ───
app.get("/api/instagram/auth-url", (req, res) => {
  const url = `https://www.instagram.com/oauth/authorize?client_id=${IG_APP_ID}&redirect_uri=${encodeURIComponent(IG_REDIRECT)}&response_type=code&scope=instagram_business_basic`;
  res.json({ url });
});

app.get("/api/instagram/posts", async (req, res) => {
  try {
    const posts = await fetchInstagramPosts();
    res.json(posts);
  } catch (err) {
    console.error(`[ig] 오류: ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

// ──────────────────────────────────────────
// 식당 메뉴
// ──────────────────────────────────────────

// ─── SNU 학생식당 (snuco.snu.ac.kr) ───
const snucoCache = new Map();

async function fetchSnucoMenu() {
  const cacheKey = new Date().toISOString().slice(0, 10); // 날짜 기준 캐시
  if (snucoCache.has(cacheKey)) return snucoCache.get(cacheKey);

  const html = await fetchText("https://snuco.snu.ac.kr/ko/foodmenu", 0, { "User-Agent": "Mozilla/5.0" });
  const $ = cheerio.load(html);

  const restaurants = [];

  // <br> → \n 변환 후 텍스트 추출하는 헬퍼
  function cellText(el) {
    // <br> 태그를 줄바꿈으로 치환
    $(el).find("br").replaceWith("\n");
    return $(el).text()
      .split("\n")
      .map(l => l.trim())
      .filter(Boolean)
      .join("\n");
  }

  // snuco.snu.ac.kr 실제 구조: #celeb-mealtable table.menu-table tbody tr
  $("#celeb-mealtable table.menu-table tbody tr").each((i, row) => {
    const name      = $(row).find("td.title").text().trim().replace(/\s+/g, " ");
    const breakfast = cellText($(row).find("td.breakfast"));
    const lunch     = cellText($(row).find("td.lunch"));
    const dinner    = cellText($(row).find("td.dinner"));
    if (name && (breakfast || lunch || dinner)) {
      restaurants.push({
        name,
        breakfast: breakfast || "",
        lunch:     lunch     || "정보 없음",
        dinner:    dinner    || "",
      });
    }
  });

  const result = { restaurants, fetchedAt: new Date().toISOString() };
  snucoCache.set(cacheKey, result);
  return result;
}

app.get("/api/restaurant/snuco", async (req, res) => {
  try {
    const data = await fetchSnucoMenu();
    res.json(data);
  } catch (err) {
    console.error("[snuco] 오류:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── 강여사집밥 Instagram 게시물 ───
app.get("/api/restaurant/gangyeo", async (req, res) => {
  try {
    const posts = await fetchInstagramPosts();
    res.json({ posts });
  } catch (err) {
    console.error("[gangyeo] 오류:", err.message);
    res.status(500).json({ error: err.message, needsAuth: !igAccessToken });
  }
});

// ─── 고정 식당 정보 (오픈시간 등) ───
const RESTAURANTS_INFO = [
  {
    id: "gangyeo",
    name: "강여사집밥",
    type: "instagram",
    tags: ["한식", "백반"],
    address: "서울 관악구 신림로 92-1",
    hours: { weekday: "11:00–14:00", weekend: "휴무" },
    instagram: "@sgon1476",
    note: "매일 메뉴 변동 — 인스타그램 확인",
  },
  {
    id: "snuco",
    name: "SNU 학생식당",
    type: "snuco",
    tags: ["학식", "구내식당"],
    address: "서울대학교 내",
    hours: {
      breakfast: "07:30–09:00",
      lunch: "11:00–14:00",
      dinner: "17:00–19:00",
    },
    note: "건물마다 운영 시간 상이",
  },
  {
    id: "boodang",
    name: "불당",
    type: "static",
    tags: ["한식", "분식"],
    address: "서울 관악구 관악로 1",
    hours: { weekday: "11:00–20:00", weekend: "11:00–17:00" },
    note: "대학원 기숙사 인근",
  },
];

// 현재 오픈 여부 계산
function isOpenNow(info) {
  const now = new Date();
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000); // UTC→KST
  const day = kst.getUTCDay(); // 0=일, 6=토
  const hhmm = kst.getUTCHours() * 100 + kst.getUTCMinutes();

  function parseRange(str) {
    if (!str || str === "휴무") return null;
    const m = str.match(/(\d{1,2}):(\d{2})[–\-~](\d{1,2}):(\d{2})/);
    if (!m) return null;
    return {
      open:  parseInt(m[1]) * 100 + parseInt(m[2]),
      close: parseInt(m[3]) * 100 + parseInt(m[4]),
    };
  }

  const hours = info.hours;
  if (!hours) return null;

  if (info.id === "snuco") {
    if (day === 0 || day === 6) return false; // 주말 휴무
    const ranges = [hours.breakfast, hours.lunch, hours.dinner].map(parseRange).filter(Boolean);
    return ranges.some(r => hhmm >= r.open && hhmm < r.close);
  }

  const rangeStr = (day === 0 || day === 6) ? (hours.weekend || hours.weekday) : hours.weekday;
  const r = parseRange(rangeStr);
  if (!r) return false;
  return hhmm >= r.open && hhmm < r.close;
}

app.get("/api/restaurant/list", (req, res) => {
  const list = RESTAURANTS_INFO.map(r => ({
    ...r,
    isOpen: isOpenNow(r),
  }));
  res.json(list);
});

app.get("/health", (req, res) => res.json({ ok: true }));

// ──────────────────────────────────────────
// 카카오 길찾기 프록시 (CORS 방지)
// ──────────────────────────────────────────
const KAKAO_REST_KEY = process.env.KAKAO_REST_KEY;

app.post("/api/directions", async (req, res) => {
  const { origin, destination } = req.body || {};
  if (!origin?.lat || !destination?.lat) {
    return res.status(400).json({ error: "origin/destination 필요" });
  }
  try {
    const url = `https://apis-navi.kakaomobility.com/v1/directions?origin=${origin.lng},${origin.lat}&destination=${destination.lng},${destination.lat}&priority=RECOMMEND`;
    const result = await fetchText(url, 0, { Authorization: `KakaoAK ${KAKAO_REST_KEY}` });
    res.json(JSON.parse(result));
  } catch (err) {
    console.error("[directions]", err.message);
    res.status(500).json({ error: err.message });
  }
});

// ──────────────────────────────────────────
// FCM (Flutter 앱 푸시 알림)
// ──────────────────────────────────────────
const FCM_SERVER_KEY = process.env.FCM_SERVER_KEY; // Firebase Admin SDK 서비스 계정 키 JSON (Base64)

let fcmAdmin = null;
if (FCM_SERVER_KEY) {
  try {
    const admin = require("firebase-admin");
    const serviceAccount = JSON.parse(Buffer.from(FCM_SERVER_KEY, "base64").toString("utf8"));
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    fcmAdmin = admin.messaging();
    console.log("[FCM] Firebase Admin SDK 초기화 완료");
  } catch (err) {
    console.warn("[FCM] 초기화 실패:", err.message);
  }
} else {
  console.warn("[FCM] FCM_SERVER_KEY 없음 — Flutter 푸시 알림 비활성화");
}

// FCM 토큰 저장소 { token → { tasks: [...] } }
const fcmTokenStore = new Map();
let fcmCol = null; // MongoDB fcm_tokens 컬렉션

async function connectFcmMongo() {
  if (!MONGO_URI) return;
  try {
    const client = new MongoClient(MONGO_URI);
    await client.connect();
    fcmCol = client.db("sharap").collection("fcm_tokens");
    const docs = await fcmCol.find({}).toArray();
    docs.forEach((doc) => fcmTokenStore.set(doc._id, {
      tasks: doc.tasks || [],
      ...(doc.icalUrl ? { icalUrl: doc.icalUrl } : {}),
      ...(doc.knownEtlIds !== undefined ? { knownEtlIds: doc.knownEtlIds } : {}),
    }));
    console.log(`[FCM] 토큰 로드: ${fcmTokenStore.size}개`);
  } catch (err) {
    console.error("[FCM] MongoDB 연결 실패:", err.message);
  }
}

async function saveFcmToken(token, data) {
  if (!fcmCol) return;
  try {
    await fcmCol.replaceOne({ _id: token }, { _id: token, ...data }, { upsert: true });
  } catch (err) {
    console.error("[FCM] 저장 실패:", err.message);
  }
}

async function deleteFcmToken(token) {
  if (!fcmCol) return;
  try {
    await fcmCol.deleteOne({ _id: token });
  } catch (err) {
    console.error("[FCM] 삭제 실패:", err.message);
  }
}

connectFcmMongo();

// Flutter 앱이 FCM 토큰 등록
app.post("/api/fcm/register", async (req, res) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ error: "token 필요" });
  const existing = fcmTokenStore.get(token) || {};
  const merged = { ...existing, tasks: existing.tasks || [] };
  fcmTokenStore.set(token, merged);
  await saveFcmToken(token, merged);
  console.log(`[FCM] 토큰 등록: ${token.slice(0, 20)}...`);
  res.json({ ok: true });
});

// Flutter 앱이 과제 목록 동기화 (알림 스케줄용)
app.post("/api/fcm/sync-tasks", async (req, res) => {
  const { token, tasks } = req.body;
  if (!token) return res.status(400).json({ error: "token 필요" });
  const existing = fcmTokenStore.get(token) || {};
  const data = { ...existing, tasks: tasks || [] };
  fcmTokenStore.set(token, data);
  await saveFcmToken(token, data);
  console.log(`[FCM] 과제 동기화: ${token.slice(0, 20)}... (${(tasks || []).length}개)`);
  res.json({ ok: true });
});

// FCM 알림은 24h / 5h / 1h 전 3번만 발송
const FCM_DEADLINE_TARGETS = [24, 5, 1];

// 5분마다 FCM 알림 체크
if (fcmAdmin) {
  setInterval(async () => {
    const now = new Date();
    const WINDOW = 6 / 60; // ±6분 허용

    for (const [token, { tasks }] of fcmTokenStore) {
      for (const task of tasks) {
        const due = new Date(task.dueDate);
        const diffH = (due - now) / (1000 * 60 * 60);
        if (diffH < 0) continue;

        for (const h of FCM_DEADLINE_TARGETS) {
          if (diffH <= h + WINDOW && diffH > h - WINDOW) {
            const key = `fcm:${token}:${task.etlId}:${h}`;
            if (sentKeys.has(key)) continue;
            sentKeys.add(key);

            try {
              await fcmAdmin.send({
                token,
                notification: {
                  title: `💣 ${task.courseName || task.title}`,
                  body: `${task.title} 마감 ${h}시간 전`,
                },
                // Flutter 앱이 ongoing 알림 생성에 사용
                data: {
                  type: "deadline",
                  etlId: String(task.etlId),
                  title: String(task.title),
                  courseName: String(task.courseName || ""),
                  dueDate: String(task.dueDate),
                  dateOnly: task.dateOnly ? "true" : "false",
                },
                android: { priority: "high" },
              });
              console.log(`[FCM] 발송: ${task.title} (${h}h)`);
            } catch (err) {
              console.error("[FCM] 발송 실패:", err.message);
              if (err.code === "messaging/registration-token-not-registered") {
                fcmTokenStore.delete(token);
                deleteFcmToken(token);
              }
            }
          }
        }
      }
    }
  }, 5 * 60 * 1000);
}

// sentKeys 주기적 정리 (7일마다 전체 초기화 — 이미 발송된 만료 과제 키 제거)
setInterval(() => {
  const before = sentKeys.size;
  sentKeys.clear();
  console.log(`[sentKeys] 정리 완료 (${before}개 제거)`);
}, 7 * 24 * 60 * 60 * 1000);

// 식당 메뉴 서버 시작 시 즉시 로드 + 1시간마다 갱신 (사용자 요청 전에 캐시 warm-up)
fetchSnucoMenu().catch(err => console.error('[snuco] 초기 로드 실패:', err.message));
setInterval(() => {
  fetchSnucoMenu().catch(err => console.error('[snuco] 주기적 갱신 실패:', err.message));
}, 60 * 60 * 1000);

// 서버 공인 IP 확인용 (ODSAY 등록 후 삭제 가능)
app.get('/api/myip', async (req, res) => {
  try {
    const text = await fetchText('https://api.ipify.org');
    res.json({ ip: text.trim() });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── 시간표 ────────────────────────────────────────────────────────────────────

async function fetchCanvasCourses(token) {
  const url = 'https://myetl.snu.ac.kr/api/v1/courses?enrollment_state=active&per_page=50';
  const text = await fetchText(url, 0, {
    'Authorization': `Bearer ${token}`,
    'Accept': 'application/json',
  });
  const data = JSON.parse(text);
  if (!Array.isArray(data)) return [];
  return data
    .filter(c => c.workflow_state === 'available')
    .map(c => ({
      id: String(c.id),
      name: c.name || '',
      courseCode: c.course_code || '',
    }));
}

function parseIcalSessions(icsText) {
  const events = ical.sync.parseICS(icsText);
  const sessions = [];

  for (const [, event] of Object.entries(events)) {
    if (event.type !== 'VEVENT' || !event.rrule) continue;
    const start = event.start;
    if (!start) continue;

    // RRULE에서 요일(BYDAY) 추출; 없으면 DTSTART 요일로 fallback
    const _dayNames = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
    let weekdays = [];
    try {
      const rruleStr = event.rrule.toString ? event.rrule.toString() : '';
      const m = rruleStr.match(/BYDAY=([^;\r\n]+)/);
      if (m) {
        weekdays = m[1].split(',').map(d => d.trim().toUpperCase());
      } else {
        // BYDAY 없는 주간 RRULE — DTSTART의 요일로 단일 반복
        weekdays = [_dayNames[start.getDay()]];
      }
    } catch (_) {}

    const pad = n => String(n).padStart(2, '0');
    // node-ical parses to UTC; add KST offset (+9h) before extracting H:M
    const toKst = d => new Date(d.getTime() + 9 * 60 * 60 * 1000);
    const kstStart = toKst(start);
    const kstEnd = event.end ? toKst(event.end) : null;
    sessions.push({
      uid: event.uid || '',
      summary: event.summary || '',
      location: event.location || '',
      startTime: `${pad(kstStart.getUTCHours())}:${pad(kstStart.getUTCMinutes())}`,
      endTime: kstEnd ? `${pad(kstEnd.getUTCHours())}:${pad(kstEnd.getUTCMinutes())}` : '',
      weekdays,
    });
  }
  return sessions;
}

app.post('/api/timetable', async (req, res) => {
  const { icalUrl, canvasToken } = req.body;
  if (!icalUrl) return res.status(400).json({ error: 'icalUrl required' });
  try {
    const host = new URL(icalUrl.replace(/^webcal:/i, 'https:')).hostname;
    if (host !== 'myetl.snu.ac.kr') return res.status(400).json({ error: 'invalid icalUrl host' });
  } catch { return res.status(400).json({ error: 'invalid icalUrl' }); }

  const [coursesResult, sessionsResult] = await Promise.allSettled([
    canvasToken ? fetchCanvasCourses(canvasToken) : Promise.resolve([]),
    (async () => {
      const httpsUrl = icalUrl.replace(/^webcal:/i, 'https:');
      const text = await fetchText(httpsUrl);
      return parseIcalSessions(text);
    })(),
  ]);

  res.json({
    courses: coursesResult.status === 'fulfilled' ? coursesResult.value : [],
    sessions: sessionsResult.status === 'fulfilled' ? sessionsResult.value : [],
    errors: {
      courses: coursesResult.status === 'rejected' ? coursesResult.reason?.message : null,
      sessions: sessionsResult.status === 'rejected' ? sessionsResult.reason?.message : null,
    },
  });
});

// ── 도서관 좌석 ───────────────────────────────────────────────────────────────

const librarySeatCache = { data: null, ts: 0 };
const LIBRARY_CACHE_TTL_MS = 60_000;

async function fetchLibrarySeats() {
  // lib.snu.ac.kr 좌석 현황 페이지 스크래핑
  const html = await fetchText('https://lib.snu.ac.kr/seat', 0, {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
    'Accept': 'text/html',
    'Referer': 'https://lib.snu.ac.kr/',
  });
  const $ = cheerio.load(html);
  const rooms = [];

  // 여러 가능한 CSS 선택자 시도 (페이지 구조 변경 대응)
  const selectors = [
    'table tbody tr',
    '.reading-room',
    '.room-item',
    '.seat-row',
    '[class*="room"]',
  ];

  let found = false;
  for (const sel of selectors) {
    $(sel).each((_, el) => {
      const cells = $(el).find('td');
      if (cells.length >= 2) {
        const name = $(cells[0]).text().trim();
        const nums = [];
        cells.each((__, td) => {
          const n = parseInt($(td).text().trim());
          if (!isNaN(n)) nums.push(n);
        });
        if (name && nums.length >= 2) {
          rooms.push({ name, available: nums[0], total: nums[nums.length - 1] });
          found = true;
        }
      }
    });
    if (found) break;
  }

  // 파싱 실패 시 빈 배열 반환 (502 대신 graceful)
  return rooms;
}

app.get('/api/library/seats', async (req, res) => {
  const now = Date.now();
  if (librarySeatCache.data && now - librarySeatCache.ts < LIBRARY_CACHE_TTL_MS) {
    return res.json(librarySeatCache.data);
  }
  try {
    const rooms = await fetchLibrarySeats();
    const data = { rooms, updatedAt: new Date().toISOString() };
    librarySeatCache.data = data;
    librarySeatCache.ts = now;
    res.json(data);
  } catch (err) {
    if (librarySeatCache.data) return res.json({ ...librarySeatCache.data, stale: true });
    res.json({ rooms: [], updatedAt: null, error: err.message });
  }
});

// ── 새 과제 감지 FCM 구독 ─────────────────────────────────────────────────────

// fcmTokenStore 확장: { tasks, icalUrl?, canvasToken?, knownEtlIds? }
// knownEtlIds = null → 첫 폴링(기준점 설정만, 알림 X), [] → 이후 diff 비교

app.post('/api/fcm/subscribe-etl', async (req, res) => {
  const { token, icalUrl } = req.body;
  if (!token || !icalUrl) return res.status(400).json({ error: 'token, icalUrl required' });
  try {
    const host = new URL(icalUrl.replace(/^webcal:/i, 'https:')).hostname;
    if (host !== 'myetl.snu.ac.kr') return res.status(400).json({ error: 'invalid icalUrl host' });
  } catch { return res.status(400).json({ error: 'invalid icalUrl' }); }

  const existing = fcmTokenStore.get(token) || { tasks: [] };
  // eTL URL이 바뀌면 기존 baseline을 버리고 재설정 (오탐 방지)
  const urlChanged = existing.icalUrl && existing.icalUrl !== icalUrl;
  // canvasToken은 폴링에서 사용하지 않으므로 저장하지 않음 (보안)
  const { canvasToken: _drop, ...existingClean } = existing;
  const updated = {
    ...existingClean,
    icalUrl,
    knownEtlIds: urlChanged ? null : (existing.knownEtlIds !== undefined ? existing.knownEtlIds : null),
    knownAnnouncementIds: urlChanged ? null : (existing.knownAnnouncementIds !== undefined ? existing.knownAnnouncementIds : null),
  };
  fcmTokenStore.set(token, updated);
  await saveFcmToken(token, updated);
  res.json({ ok: true });

  // knownEtlIds가 null이면 즉시 baseline 설정 (15분 폴링 전 생긴 과제 누락 방지)
  if (updated.knownEtlIds === null) {
    setImmediate(async () => {
      try {
        const httpsUrl = icalUrl.replace(/^webcal:/i, 'https:');
        const text = await fetchText(httpsUrl);
        const events = ical.sync.parseICS(text);
        const baseline = Object.entries(events)
          .filter(([, e]) => e.type === 'VEVENT' && !e.rrule)
          .map(([uid]) => uid);
        const current = fcmTokenStore.get(token);
        if (current && current.knownEtlIds === null) {
          current.knownEtlIds = baseline;
          await saveFcmToken(token, current);
        }
      } catch (err) {
        console.error('[subscribe-etl baseline] 실패:', err.message);
      }
    });
  }
});

app.post('/api/fcm/unsubscribe-etl', async (req, res) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ error: 'token required' });
  const existing = fcmTokenStore.get(token);
  if (existing) {
    const { icalUrl: _u, knownEtlIds: _k, ...rest } = existing;
    fcmTokenStore.set(token, rest);
    await saveFcmToken(token, rest);
  }
  res.json({ ok: true });
});

// 15분마다 새 과제 감지
if (fcmAdmin) {
  setInterval(async () => {
    for (const [token, data] of fcmTokenStore) {
      if (!data.icalUrl) continue;

      try {
        const httpsUrl = data.icalUrl.replace(/^webcal:/i, 'https:');
        const text = await fetchText(httpsUrl);
        const events = ical.sync.parseICS(text);

        // 일회성 VEVENT만 과제로 취급 (RRULE = 수업)
        const currentEtlIds = new Set(
          Object.entries(events)
            .filter(([, e]) => e.type === 'VEVENT' && !e.rrule)
            .map(([uid]) => uid)
        );

        if (data.knownEtlIds === null || data.knownEtlIds === undefined) {
          data.knownEtlIds = [...currentEtlIds];
          await saveFcmToken(token, data);
          continue;
        }

        const prevSet = new Set(data.knownEtlIds);
        const newIds = [...currentEtlIds].filter(id => !prevSet.has(id));

        if (newIds.length > 0) {
          const newEventTitles = newIds
            .map(id => events[id]?.summary)
            .filter(Boolean)
            .slice(0, 2);

          const body = newEventTitles.length > 0
            ? newEventTitles.join(', ')
            : '과제 탭에서 확인하세요';

          await fcmAdmin.send({
            token,
            notification: {
              title: newIds.length === 1
                ? `📚 새 과제: ${newEventTitles[0] || ''}`
                : `📚 새 과제 ${newIds.length}개가 등록되었습니다`,
              body,
            },
            data: { type: 'new_assignment', count: String(newIds.length) },
            android: { priority: 'high' },
          });
          console.log(`[새 과제] ${token.slice(0, 12)}... 에 ${newIds.length}개 알림`);

          data.knownEtlIds = [...currentEtlIds];
          await saveFcmToken(token, data);
        }
      } catch (err) {
        console.error(`[새 과제 폴링] ${token.slice(0, 10)} 실패: ${err.message}`);
      }
    }
  }, 15 * 60 * 1000);
}


// ── 셔틀버스 ──────────────────────────────────────────────────────────────────

const SHUTTLE_ROUTES = [
  {
    id: 61, name: '정문↔순환도로', type: '교내',
    stations: [
      { code: 101, name: '정문' },
      { code: 201, name: '법대입구' },
      { code: 401, name: '자연대500동(행정관)' },
      { code: 501, name: '농생대' },
      { code: 601, name: '공대입구' },
      { code: 701, name: '신소재연구소' },
      { code: 901, name: '302동 공학관' },
      { code: 1001, name: '301동 공학관' },
      { code: 1101, name: '유전공학연구소' },
      { code: 1301, name: '교수회관입구' },
      { code: 1501, name: '기숙사삼거리' },
      { code: 1601, name: '국제대학원' },
      { code: 1701, name: '종합교육연구동' },
      { code: 1801, name: '경영대' },
    ],
  },
  {
    id: 81, name: '호암경유 역방향', type: '교내',
    stations: [
      { code: 100, name: '정문(입구)' },
      { code: 200, name: '법대입구' },
      { code: 401, name: '자연대500동(행정관)' },
      { code: 501, name: '농생대' },
      { code: 601, name: '공대입구' },
      { code: 701, name: '신소재연구소' },
      { code: 711, name: '호암교수회관' },
      { code: 901, name: '302동 공학관' },
      { code: 1001, name: '301동 공학관' },
      { code: 1101, name: '유전공학연구소' },
      { code: 1301, name: '교수회관입구' },
      { code: 1500, name: '기숙사삼거리(입구)' },
      { code: 1501, name: '기숙사삼거리' },
      { code: 1700, name: '종합교육연구동(입구)' },
      { code: 1800, name: '경영대(입구)' },
      { code: 2011, name: '행정관' },
      { code: 2301, name: '국제대학원' },
      { code: 300, name: '공학관' },
    ],
  },
  {
    id: 10, name: '행정관↔입구역', type: '통학',
    stations: [
      { code: 410, name: '서울대본부(행정관)' },
      { code: 2401, name: '서울대입구역(승차)' },
      { code: 2400, name: '서울대입구역(하차)' },
    ],
  },
  {
    id: 40, name: '행정관↔대학동', type: '통학',
    stations: [
      { code: 410, name: '서울대본부(행정관)' },
      { code: 2501, name: '대학동(승차)' },
      { code: 2500, name: '대학동(하차)' },
    ],
  },
  {
    id: 70, name: '입구역→2공학관', type: '통학',
    stations: [
      { code: 2401, name: '서울대입구역(승차)' },
    ],
  },
  {
    id: 92, name: '(야간) 행정관→입구역', type: '야간',
    stations: [
      { code: 410, name: '서울대본부(행정관)' },
    ],
  },
  {
    id: 112, name: '(야간) 행정관→대학동', type: '야간',
    stations: [
      { code: 410, name: '서울대본부(행정관)' },
    ],
  },
  {
    id: 123, name: '심야셔틀', type: '심야',
    stations: [
      { code: 100, name: '정문' },
      { code: 400, name: '자연대(행정관)' },
      { code: 500, name: '농생대' },
      { code: 710, name: '공대' },
      { code: 900, name: '공학관' },
      { code: 1000, name: '301동 공학관' },
      { code: 1500, name: '기숙사삼거리' },
      { code: 1700, name: '종합교육연구동' },
      { code: 1800, name: '경영대' },
      { code: 2011, name: '행정관' },
    ],
  },
  {
    id: 555, name: '낙성대→제1공학관', type: '통학',
    stations: [
      { code: 3101, name: '낙성대역' },
      { code: 3201, name: '낙성대입구' },
      { code: 701, name: '신소재연구소' },
      { code: 901, name: '302동 공학관' },
      { code: 1101, name: '유전공학연구소' },
      { code: 1301, name: '교수회관입구' },
      { code: 1501, name: '기숙사삼거리' },
    ],
  },
  {
    id: 999, name: '사당역→행정관', type: '통학',
    stations: [
      { code: 999901, name: '사당역' },
    ],
  },
];

// 캐시: key="routeId_stationCode", 성공 응답만 캐시 (실패는 캐시 안 함)
const shuttleArrivalCache = new Map();
const SHUTTLE_CACHE_TTL_MS = 15_000;

app.get('/api/shuttle/routes', (req, res) => {
  res.json(SHUTTLE_ROUTES);
});

app.get('/api/shuttle/arrival', async (req, res) => {
  const routeId = req.query.route_id;
  const stationCode = req.query.station_code;
  if (!routeId || !stationCode) {
    return res.status(400).json({ error: 'route_id and station_code are required' });
  }

  const cacheKey = `${routeId}_${stationCode}`;
  const cached = shuttleArrivalCache.get(cacheKey);
  if (cached && Date.now() - cached.ts < SHUTTLE_CACHE_TTL_MS) {
    return res.json(cached.data);
  }

  const url = `http://shuttlebus.snu.ac.kr/mobile/station/stationBusDetail.action`
    + `?bus_route_id=${encodeURIComponent(routeId)}`
    + `&bus_station_code=${encodeURIComponent(stationCode)}`
    + `&type=SHUTTLE`;

  try {
    const html = await fetchText(url);
    const $ = cheerio.load(html);

    const arrivals = [];
    $('ul.busSch li .pos').each((_, el) => {
      const raw = $(el).find('.time strong').text().trim();
      arrivals.push(raw || '운행정보없음');
    });

    const data = {
      first: arrivals[0] ?? '운행정보없음',
      second: arrivals[1] ?? null,
    };
    shuttleArrivalCache.set(cacheKey, { data, ts: Date.now() });
    res.json(data);
  } catch (err) {
    res.status(502).json({ first: null, second: null, error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`✅ SNU 과제 서버 실행 중: http://localhost:${PORT}`);
});
