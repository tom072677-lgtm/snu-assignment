const express = require("express");
const cors = require("cors");
const ical = require("node-ical");
const https = require("https");
const webpush = require("web-push");

// VAPID 설정
const VAPID_PUBLIC = process.env.VAPID_PUBLIC || "BNHX2y_hSe3MDv1TelFE8LSK6Kg2DY8Aa7gFAjvX9OAIyJu72OerTOMA7PNW3dVf-6lM9DNUFkI9FOoAh_TTZOg";
const VAPID_PRIVATE = process.env.VAPID_PRIVATE || "zf1hxNgT-YzntEwS5CycYS9oynMTZeDIqmPlWUMrbU0";
webpush.setVapidDetails("mailto:admin@snu-app.com", VAPID_PUBLIC, VAPID_PRIVATE);

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors({ origin: "*" }));
app.use(express.json());

// ──────────────────────────────────────────
// URL fetch (헤더 지원, 리다이렉트 자동 처리)
// ──────────────────────────────────────────
function fetchText(url, redirectCount = 0, extraHeaders = {}) {
  return new Promise((resolve, reject) => {
    if (redirectCount > 5) return reject(new Error("리다이렉트가 너무 많습니다."));

    const parsed = new URL(url);
    const options = {
      hostname: parsed.hostname,
      path: parsed.pathname + parsed.search,
      method: "GET",
      headers: extraHeaders,
    };

    const req = https.request(options, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        return fetchText(res.headers.location, redirectCount + 1, extraHeaders).then(resolve).catch(reject);
      }
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error(`HTTP ${res.statusCode}`));
      }
      res.setEncoding("utf8");
      let data = "";
      res.on("data", (chunk) => { data += chunk; });
      res.on("end", () => resolve(data));
    });

    req.on("error", reject);
    req.setTimeout(15000, () => req.destroy(new Error("요청 시간 초과 (15초)")));
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

app.get("/api/push/vapid-public-key", (req, res) => {
  res.json({ key: VAPID_PUBLIC });
});

app.post("/api/push/subscribe", (req, res) => {
  const { subscription, tasks } = req.body;
  if (!subscription?.endpoint) return res.status(400).json({ error: "subscription 필요" });
  pushStore.set(subscription.endpoint, { subscription, tasks: tasks || [] });
  console.log(`[push] 구독 등록: ${pushStore.size}개`);
  res.json({ ok: true });
});

// 5분마다 알림 체크 (과제: 24h/5h/1h, 사용자 일정: task.targets 사용)
const DEFAULT_TARGETS = [24, 5, 1];
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

          const label = h === 1 ? "1시간" : h === 5 ? "5시간" : "24시간";
          const name = task.courseName || task.title;
          const isUserEvent = !!task.targets;
          try {
            await webpush.sendNotification(subscription, JSON.stringify({
              title: isUserEvent ? `📅 일정 ${label} 전` : `📚 마감 ${label} 전`,
              body: isUserEvent
                ? `"${name}" 일정이 ${label} 후입니다.`
                : `${name} 과제 마감이 ${label} 후입니다.`,
            }));
            console.log(`[push] 알림 발송: ${name} (${h}h)`);
          } catch (err) {
            console.error(`[push] 발송 실패:`, err.message);
            if (err.statusCode === 410) pushStore.delete(endpoint);
          }
        }
      }
    }
  }
}, 5 * 60 * 1000);

// ──────────────────────────────────────────
// Instagram 최신 게시물 (쿠키 세션 방식)
// ──────────────────────────────────────────

const igCache = new Map(); // username → { posts, fetchedAt }
let igCookies = ""; // 홈페이지에서 받은 세션 쿠키

const IG_HEADERS = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Accept-Language": "ko-KR,ko;q=0.9",
};

function fetchWithResponse(url, extraHeaders = {}) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const req = https.request({
      hostname: parsed.hostname,
      path: parsed.pathname + parsed.search,
      method: "GET",
      headers: { ...IG_HEADERS, ...extraHeaders },
    }, (res) => {
      const setCookies = res.headers["set-cookie"] || [];
      res.setEncoding("utf8");
      let data = "";
      res.on("data", (c) => { data += c; });
      res.on("end", () => resolve({ text: data, status: res.statusCode, setCookies }));
    });
    req.on("error", reject);
    req.setTimeout(15000, () => req.destroy(new Error("timeout")));
    req.end();
  });
}

async function refreshIgCookies() {
  const { setCookies } = await fetchWithResponse("https://www.instagram.com/");
  igCookies = setCookies.map((c) => c.split(";")[0]).join("; ");
  console.log("[ig] 쿠키 갱신 완료");
}

async function fetchInstagramPosts(username) {
  const cached = igCache.get(username);
  if (cached && Date.now() - cached.fetchedAt < 30 * 60 * 1000) {
    console.log(`[ig] 캐시 사용: ${username}`);
    return cached.posts;
  }

  if (!igCookies) await refreshIgCookies();

  console.log(`[ig] Instagram 요청: ${username}`);
  const { text, status } = await fetchWithResponse(
    `https://www.instagram.com/api/v1/users/web_profile_info/?username=${username}`,
    {
      "X-Ig-App-Id": "936619743392459",
      "Accept": "*/*",
      "Referer": "https://www.instagram.com/",
      "Cookie": igCookies,
    }
  );

  if (status === 429) {
    // 쿠키 만료 → 갱신 후 재시도
    console.log("[ig] 429 → 쿠키 갱신 후 재시도");
    await refreshIgCookies();
    throw new Error("rate_limited");
  }

  if (status !== 200) throw new Error(`HTTP ${status}`);

  const data = JSON.parse(text);
  const edges = data?.data?.user?.edge_owner_to_timeline_media?.edges || [];

  const posts = edges.slice(0, 5).map((e) => {
    const node = e.node;
    return {
      id: node.shortcode,
      url: `https://www.instagram.com/p/${node.shortcode}/`,
      imageUrl: node.thumbnail_src || node.display_url,
      caption: node.edge_media_to_caption?.edges?.[0]?.node?.text || "",
      timestamp: node.taken_at_timestamp,
      date: new Date(node.taken_at_timestamp * 1000).toISOString(),
    };
  });

  igCache.set(username, { posts, fetchedAt: Date.now() });
  console.log(`[ig] ${username} 게시물 ${posts.length}개 수집`);
  return posts;
}

// 서버 시작 시 쿠키 미리 받아두기
refreshIgCookies().catch(() => {});

app.get("/api/instagram/:username", async (req, res) => {
  try {
    const posts = await fetchInstagramPosts(req.params.username);
    res.json(posts);
  } catch (err) {
    console.error(`[ig] 오류: ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

app.get("/health", (req, res) => res.json({ ok: true }));

app.listen(PORT, () => {
  console.log(`✅ SNU 과제 서버 실행 중: http://localhost:${PORT}`);
});
