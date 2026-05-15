const express = require("express");
const cors = require("cors");
const ical = require("node-ical");
const https = require("https");
const webpush = require("web-push");
const { MongoClient } = require("mongodb");

// VAPID 설정 (없으면 Push 비활성화, 나머지 기능은 정상 동작)
const VAPID_PUBLIC = process.env.VAPID_PUBLIC;
const VAPID_PRIVATE = process.env.VAPID_PRIVATE;
const pushEnabled = !!(VAPID_PUBLIC && VAPID_PRIVATE);
if (pushEnabled) {
  webpush.setVapidDetails("mailto:admin@snu-app.com", VAPID_PUBLIC, VAPID_PRIVATE);
} else {
  console.warn("VAPID 환경변수 없음 — Push 알림 비활성화");
}

const path = require("path");

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors({ origin: "*" }));
app.use(express.json());

// 정적 파일 서빙 (로컬: localhost:3001로 앱 접근 가능)
app.use(express.static(path.join(__dirname, "..")));

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

    const req = https.request(options, (res) => {
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
// body: { icalUrl, apiToken? }
// ──────────────────────────────────────────
app.post("/api/sync-ical", async (req, res) => {
  let { icalUrl, apiToken } = req.body;

  if (!icalUrl) {
    return res.status(400).json({ error: "icalUrl이 필요합니다." });
  }

  icalUrl = icalUrl.trim().replace(/^webcal:\/\//i, "https://");

  if (!icalUrl.startsWith("https://")) {
    return res.status(400).json({ error: "유효한 eTL iCal URL을 입력해주세요." });
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
      if (diffDays < 0 || diffDays > 7) continue;

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

    // courseId/assignmentId는 클라이언트에 불필요하므로 제거
    const output = filtered.map(({ courseId, assignmentId, ...rest }) => rest);

    output.sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate));
    console.log(`[sync] 완료: ${output.length}개 과제`);
    res.json(output);

  } catch (err) {
    console.error(`[sync] 오류: ${err.message}`);
    res.status(500).json({ error: `iCal 불러오기 실패: ${err.message}` });
  }
});

// ──────────────────────────────────────────
// 학교 소식 크롤링
// ──────────────────────────────────────────

const cheerio = require("cheerio");

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

// OSRM 도보/자전거 경로 프록시
app.get("/api/route/osrm", async (req, res) => {
  const { profile, olat, olng, dlat, dlng } = req.query;
  if (!profile || !olat || !olng || !dlat || !dlng)
    return res.status(400).json({ error: "파라미터 필요" });
  try {
    const url = `https://router.project-osrm.org/route/v1/${profile}/${olng},${olat};${dlng},${dlat}?overview=full&geometries=geojson`;
    const text = await fetchText(url, 0);
    const data = JSON.parse(text);
    const route = data.routes?.[0];
    if (!route) throw new Error("경로 없음");
    const path = route.geometry.coordinates.map(([lng, lat]) => [lat, lng]);
    res.json({ duration: route.duration, distance: route.distance, path });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 장소 검색 (카카오 로컬 API 프록시)
app.get("/api/search-place", async (req, res) => {
  const { q, x, y } = req.query;
  if (!q) return res.status(400).json({ error: "q 필요" });
  try {
    let url = `https://dapi.kakao.com/v2/local/search/keyword.json?query=${encodeURIComponent(q)}&size=15`;
    if (x && y) url += `&x=${x}&y=${y}&radius=20000&sort=accuracy`;
    const text = await fetchText(url, 0, { Authorization: `KakaoAK ${KAKAO_REST_KEY}` });
    const data = JSON.parse(text);
    res.json((data.documents || []).map((d) => ({
      name: d.place_name,
      address: d.road_address_name || d.address_name,
      lat: parseFloat(d.y),
      lng: parseFloat(d.x),
      category: d.category_group_name || "",
    })));
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

    console.log("[ig] 액세스 토큰 발급 완료!");
    console.log("[ig] 토큰 (Render 환경변수 IG_ACCESS_TOKEN에 저장하세요):", longToken);
    res.send(`
      <h2>✅ Instagram 연결 완료!</h2>
      <p>아래 토큰을 Render 환경변수 <b>IG_ACCESS_TOKEN</b>에 저장하세요.</p>
      <textarea rows="4" cols="80">${longToken}</textarea>
    `);
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
const KAKAO_REST_KEY = "80493a22b9dfbe3ba266c2f2421b461b";

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

app.listen(PORT, () => {
  console.log(`✅ SNU 과제 서버 실행 중: http://localhost:${PORT}`);
});
