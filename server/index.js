const express = require("express");
const cors = require("cors");
const ical = require("node-ical");
const https = require("https");

const app = express();
const PORT = 3001;

app.use(cors({ origin: "*" }));
app.use(express.json());

// ──────────────────────────────────────────
// URL fetch (Node.js 내장 https, 리다이렉트 자동 처리)
// ──────────────────────────────────────────
function fetchText(url, redirectCount = 0) {
  return new Promise((resolve, reject) => {
    if (redirectCount > 5) return reject(new Error("리다이렉트가 너무 많습니다."));

    const req = https.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        return fetchText(res.headers.location, redirectCount + 1).then(resolve).catch(reject);
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
  });
}

// ──────────────────────────────────────────
// Canvas iCal 파싱 유틸
// ──────────────────────────────────────────

// SUMMARY: "과제명 [과목명]" → { title, courseName }
function parseSummary(summary) {
  const match = (summary || "").match(/^(.*?)\s*\[([^\]]+)\]\s*$/);
  if (match) return { title: match[1].trim(), courseName: match[2].trim() };
  return { title: (summary || "").trim(), courseName: "" };
}

// Canvas 캘린더 URL → 과제 직접 URL
// "https://myetl.snu.ac.kr/calendar?include_contexts=course_XXX&...#assignment_YYY"
// → "https://myetl.snu.ac.kr/courses/XXX/assignments/YYY"
function buildAssignmentUrl(calendarUrl) {
  if (!calendarUrl) return "";
  const courseMatch = calendarUrl.match(/include_contexts=course_(\d+)/);
  const assignMatch = calendarUrl.match(/#assignment_(\d+)/);
  if (courseMatch && assignMatch) {
    return `https://myetl.snu.ac.kr/courses/${courseMatch[1]}/assignments/${assignMatch[1]}`;
  }
  return calendarUrl;
}

// Canvas DTSTART 파싱
// 두 가지 형식:
//   VALUE=DATE:20260412T000000  → 날짜만 (시간 불명, dateOnly: true)
//   20260415T033000Z            → UTC 명시 (정확한 시간 있음)
function parseEventDate(ev) {
  const start = ev.start;
  if (!start) return { date: null, dateOnly: false };

  // node-ical이 이미 Date 객체로 변환
  if (start instanceof Date) {
    // VALUE=DATE 여부 확인 (datetype 또는 파라미터로 체크)
    const isDateOnly = ev.start.dateOnly === true || (ev.dtstart && ev.dtstart.includes("VALUE=DATE"));
    return { date: start, dateOnly: isDateOnly };
  }

  return { date: null, dateOnly: false };
}

// ──────────────────────────────────────────
// POST /api/sync-ical
// body: { icalUrl: "webcal://..." or "https://..." }
// ──────────────────────────────────────────
app.post("/api/sync-ical", async (req, res) => {
  let { icalUrl } = req.body;

  if (!icalUrl) {
    return res.status(400).json({ error: "icalUrl이 필요합니다." });
  }

  // webcal:// → https:// 변환 (검사 전에 먼저 처리)
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

      // 7일 이상 지난 과제는 제외
      const diffDays = (dueDate - now) / (1000 * 60 * 60 * 24);
      if (diffDays < -7) continue;

      const { title, courseName } = parseSummary(ev.summary);
      if (!title) continue;

      // etlId: UID에서 숫자 ID 추출 (event-assignment-XXXXX)
      const uidMatch = (ev.uid || "").match(/assignment-(\d+)/);
      const etlId = uidMatch ? uidMatch[1] : (ev.uid || key).slice(0, 20);

      const assignmentUrl = buildAssignmentUrl(ev.url);

      assignments.push({
        etlId,
        title,
        courseName,
        dueDate: dueDate.toISOString(),
        dateOnly,       // 프론트에서 날짜만 표시할지 결정
        url: assignmentUrl,
      });
    }

    assignments.sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate));
    console.log(`[sync] 완료: ${assignments.length}개 과제`);
    res.json(assignments);

  } catch (err) {
    console.error(`[sync] 오류: ${err.message}`);
    res.status(500).json({ error: `iCal 불러오기 실패: ${err.message}` });
  }
});

app.listen(PORT, () => {
  console.log(`✅ SNU 과제 서버 실행 중: http://localhost:${PORT}`);
});
