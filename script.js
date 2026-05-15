const SERVER_URL = location.hostname === "localhost"
  ? "http://localhost:3001"
  : "https://snu-assignment-server.onrender.com";

// Render 무료 플랜 cold start 방지: 10분마다 서버 핑
if (location.hostname !== "localhost") {
  setInterval(() => fetch(`${SERVER_URL}/health`).catch(() => {}), 10 * 60 * 1000);
}
const STORAGE_KEY = "snu_assignment_app_tasks";
const ICAL_URL_KEY = "snu_etl_ical_url";
const CANVAS_TOKEN_KEY = "snu_etl_canvas_token";
const MEMO_KEY = "snu_assignment_app_memos";
const COMPLETED_KEY = "snu_assignment_app_completed";
const CALENDAR_KEY = "snu_calendar_events";
const KAKAO_MAP_APP_KEY = "6905c79ba68d3c49d21fcf41ea34d51e";
const KAKAO_REST_KEY = "80493a22b9dfbe3ba266c2f2421b461b";
const BOMB_COUNTDOWN_MS = 24 * 60 * 60 * 1000;

// 2026년 공휴일 및 대체공휴일
const HOLIDAYS = [
  { title: "신정",             date: "2026-01-01" },
  { title: "설날 연휴",         date: "2026-02-15" },
  { title: "설날",             date: "2026-02-17" },
  { title: "설날 연휴",         date: "2026-02-18" },
  { title: "대체공휴일(설날)",   date: "2026-02-19" },
  { title: "삼일절",           date: "2026-03-01" },
  { title: "대체공휴일(삼일절)", date: "2026-03-02" },
  { title: "어린이날",          date: "2026-05-05" },
  { title: "부처님오신날",       date: "2026-05-24" },
  { title: "현충일",            date: "2026-06-06" },
  { title: "대체공휴일(현충일)", date: "2026-06-08" },
  { title: "광복절",            date: "2026-08-15" },
  { title: "대체공휴일(광복절)", date: "2026-08-17" },
  { title: "추석 연휴",         date: "2026-09-23" },
  { title: "추석 연휴",         date: "2026-09-24" },
  { title: "추석",             date: "2026-09-25" },
  { title: "대체공휴일(추석)",   date: "2026-09-28" },
  { title: "개천절",            date: "2026-10-03" },
  { title: "대체공휴일(개천절)", date: "2026-10-05" },
  { title: "한글날",            date: "2026-10-09" },
  { title: "성탄절",            date: "2026-12-25" },
];

// 2026년 1학기 학사일정
const ACADEMIC_SCHEDULE = [
  { id: "ac_1", title: "봄학기 개강", date: "2026-03-02" },
  { id: "ac_2", title: "수강변경 기간", startDate: "2026-03-02", endDate: "2026-03-13" },
  { id: "ac_3", title: "중간고사", startDate: "2026-04-20", endDate: "2026-04-25" },
  { id: "ac_4", title: "수강취소 기간", startDate: "2026-04-27", endDate: "2026-05-01" },
  { id: "ac_5", title: "기말고사", startDate: "2026-06-15", endDate: "2026-06-20" },
  { id: "ac_6", title: "봄학기 종강", date: "2026-06-19" },
  { id: "ac_7", title: "관악제", startDate: "2026-05-12", endDate: "2026-05-14" },
];

// DOM - 과제
const taskList = document.getElementById("taskList");
const emptyMessage = document.getElementById("emptyMessage");
const completedSection = document.getElementById("completedSection");
const completedList = document.getElementById("completedList");
const completedToggle = document.getElementById("completedToggle");
const completedToggleIcon = document.getElementById("completedToggleIcon");

// DOM - 설정
const settingsBtn = document.getElementById("settingsBtn");
const settingsPanel = document.getElementById("settingsPanel");
const settingsOverlay = document.getElementById("settingsOverlay");
const settingsCloseBtn = document.getElementById("settingsCloseBtn");
const icalForm = document.getElementById("icalForm");
const icalUrlInput = document.getElementById("icalUrlInput");
const icalSaveBtn = document.getElementById("icalSaveBtn");
const etlSetupForm = document.getElementById("etlSetupForm");
const etlConnected = document.getElementById("etlConnected");
const etlSyncBtn = document.getElementById("etlSyncBtn");
const etlDisconnectBtn = document.getElementById("etlDisconnectBtn");
const etlSyncStatus = document.getElementById("etlSyncStatus");
const etlError = document.getElementById("etlError");
const apiTokenInput = document.getElementById("apiTokenInput");
const apiTokenSaveBtn = document.getElementById("apiTokenSaveBtn");

// 데이터
let tasks = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
let memos = JSON.parse(localStorage.getItem(MEMO_KEY)) || {};
let completedTasks = JSON.parse(localStorage.getItem(COMPLETED_KEY)) || [];
let calendarEvents = JSON.parse(localStorage.getItem(CALENDAR_KEY)) || [];
let bombMotionTimer = null;
let icalUrl = localStorage.getItem(ICAL_URL_KEY) || null;
let canvasToken = localStorage.getItem(CANVAS_TOKEN_KEY) || null;

// 달력 상태
let calYear = new Date().getFullYear();
let calMonth = new Date().getMonth();
let calSelectedDate = null;

// ──────────────────────────────────────────
// 날짜 유틸
// ──────────────────────────────────────────

function parseDateValue(value) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function formatDateTime(value, dateOnly = false) {
  const date = parseDateValue(value);
  if (!date) return value;
  const y = date.getFullYear();
  const mo = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  if (dateOnly) return `${y}.${mo}.${d}`;
  const hours = date.getHours();
  const ampm = hours < 12 ? "오전" : "오후";
  const h12 = hours % 12 === 0 ? 12 : hours % 12;
  const mi = String(date.getMinutes()).padStart(2, "0");
  return `${y}.${mo}.${d} ${ampm} ${h12}:${mi}`;
}

function formatCellText(text) {
  const clean = text.replace(/\s+/g, "");
  const lines = [];
  for (let i = 0; i < clean.length; i += 4) lines.push(clean.slice(i, i + 4));
  return lines.join("\n");
}

function toDateStr(y, m, d) {
  return `${y}-${String(m + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

function getBadgeInfo(dateString) {
  const dueDate = parseDateValue(dateString);
  if (!dueDate) return { text: "날짜 확인", className: "due-blue" };
  const diffMs = dueDate - new Date();
  const diffDays = diffMs / (1000 * 60 * 60 * 24);
  if (diffMs < 0) return { text: "마감", className: "due-black" };
  const d = Math.floor(diffDays);
  if (d === 0) return { text: "D-0", className: "due-red" };
  if (d <= 3) return { text: `D-${d}`, className: "due-green" };
  return { text: `D-${d}`, className: "due-blue" };
}

function getBombCountdownInfo(dateString, now = new Date()) {
  const dueDate = parseDateValue(dateString);
  if (!dueDate) return null;

  const diffMs = dueDate - now;
  if (diffMs <= 0 || diffMs > BOMB_COUNTDOWN_MS) return null;

  const progress = 1 - (diffMs / BOMB_COUNTDOWN_MS);
  const totalSeconds = Math.max(0, Math.floor(diffMs / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  return {
    left: 5 + progress * 90,
    label: `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`,
    isCritical: diffMs <= 60 * 60 * 1000,
  };
}

function renderBombSlot(task) {
  if (!parseDateValue(task.dueDate)) return "";
  return `<div class="deadline-bomb hidden"
    data-due="${escapeHtml(task.dueDate)}"
    data-id="${escapeHtml(task.etlId || task.id)}"
    data-title="${escapeHtml(task.title)}"
    data-course="${escapeHtml(task.courseName || "")}"
    data-url="${escapeHtml(task.url || "./")}"></div>`;
}

function ensureBombContent(el) {
  if (el.dataset.ready === "true") return;
  el.innerHTML = `
    <div class="deadline-bomb-top">
      <span class="deadline-bomb-title">💣 마감</span>
      <strong class="deadline-bomb-time"></strong>
    </div>
    <div class="deadline-bomb-track">
      <span class="deadline-bomb-mark start">24h</span>
      <span class="deadline-bomb-line"></span>
      <span class="deadline-bomb-runner">💣</span>
      <span class="deadline-bomb-mark end">0h</span>
    </div>
  `;
  el.dataset.ready = "true";
}

function updateDeadlineBombs() {
  const notified = JSON.parse(localStorage.getItem("bomb_notified") || "{}");
  let changed = false;

  document.querySelectorAll(".deadline-bomb").forEach((el) => {
    const info = getBombCountdownInfo(el.dataset.due);
    if (!info) {
      el.classList.add("hidden");
      return;
    }

    ensureBombContent(el);
    el.classList.remove("hidden");
    el.classList.toggle("critical", info.isCritical);
    el.style.setProperty("--bomb-left", `${info.left.toFixed(2)}%`);

    const titleEl = el.querySelector(".deadline-bomb-title");
    if (titleEl) titleEl.textContent = "💣 마감";

    const timeEl = el.querySelector(".deadline-bomb-time");
    if (timeEl) timeEl.textContent = info.label;

    // 24시간 진입 시 로컬 알림 최초 1회 트리거
    const taskId = el.dataset.id;
    if (taskId && !notified[taskId]) {
      notified[taskId] = true;
      changed = true;
      triggerLocalBombNotification(el, info);
    }
  });

  if (changed) localStorage.setItem("bomb_notified", JSON.stringify(notified));
}

function triggerLocalBombNotification(el, info) {
  if (!("Notification" in window) || Notification.permission !== "granted") return;
  if (!navigator.serviceWorker || !navigator.serviceWorker.controller) return;
  const diffMs = parseDateValue(el.dataset.due) - new Date();
  const diffHours = Math.max(0, diffMs / (1000 * 60 * 60));
  const task = {
    id: el.dataset.id,
    etlId: el.dataset.id,
    title: el.dataset.title,
    courseName: el.dataset.course,
    url: el.dataset.url,
  };
  const label = `${Math.ceil(diffHours)}시간`;
  const payload = buildDeadlineNotification(task, diffHours, label);
  navigator.serviceWorker.controller.postMessage({ type: "LOCAL_NOTIFICATION", ...payload });
}

function startBombMotionTimer() {
  if (bombMotionTimer) return;
  updateDeadlineBombs();
  bombMotionTimer = setInterval(updateDeadlineBombs, 1000);
}

function buildBombProgressBar(diffHours) {
  const totalBlocks = 12;
  const remainingRatio = Math.max(0, Math.min(1, diffHours / 24));
  const filled = Math.max(0, Math.min(totalBlocks, Math.ceil(remainingRatio * totalBlocks)));
  return "█".repeat(filled) + "░".repeat(totalBlocks - filled);
}

function buildDeadlineNotification(task, diffHours, label) {
  const name = cleanCourseName(task.courseName) || task.title;
  const safeHours = Math.max(0, diffHours);
  const wholeHours = Math.floor(safeHours);
  const minutes = Math.floor((safeHours - wholeHours) * 60);
  const timeText = `${String(wholeHours).padStart(2, "0")}:${String(minutes).padStart(2, "0")} 남음`;

  return {
    title: `💣 ${name}`,
    body: `${task.title} 마감 ${label} 전\n${timeText} ${buildBombProgressBar(safeHours)}`,
    icon: "./icon-192.png",
    badge: "./icon-192.png",
    tag: `deadline-bomb-${task.etlId || task.id}`,
    renotify: true,
    requireInteraction: true,
    data: { url: task.url || "./" },
  };
}

function cleanCourseName(name) {
  if (!name) return name;
  return name
    .replace(/^\d{4}-\d+/g, "")   // 앞의 2026-1 제거
    .replace(/\(\d+\)$/g, "")     // 뒤의 (001) 제거
    .trim();
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ──────────────────────────────────────────
// 저장
// ──────────────────────────────────────────

function saveTasks() { localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks)); }
function saveMemos() { localStorage.setItem(MEMO_KEY, JSON.stringify(memos)); }
function saveCompleted() { localStorage.setItem(COMPLETED_KEY, JSON.stringify(completedTasks)); }
function saveCalendarEvents() { localStorage.setItem(CALENDAR_KEY, JSON.stringify(calendarEvents)); }

// ──────────────────────────────────────────
// 탭 전환
// ──────────────────────────────────────────

const alertsTab = document.getElementById("alertsTab");
const calendarTab = document.getElementById("calendarTab");
const restaurantTab = document.getElementById("restaurantTab");
const mapTab = document.getElementById("mapTab");

document.querySelectorAll(".tab-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab-btn").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    const tab = btn.dataset.tab;
    alertsTab.classList.toggle("hidden", tab !== "alerts");
    calendarTab.classList.toggle("hidden", tab !== "calendar");
    restaurantTab.classList.toggle("hidden", tab !== "restaurant");
    mapTab.classList.toggle("hidden", tab !== "map");
    if (tab === "calendar") renderCalendar();
    if (tab === "restaurant") renderRestaurantTab();
    if (tab === "map") renderMapTab();
  });
});

// ──────────────────────────────────────────
// 과제 렌더링
// ──────────────────────────────────────────

function sortTasks() {
  tasks.sort((a, b) => {
    const da = parseDateValue(a.dueDate);
    const db = parseDateValue(b.dueDate);
    if (!da && !db) return 0;
    if (!da) return 1;
    if (!db) return -1;
    return da - db;
  });
}

function renderTasks() {
  sortTasks();
  taskList.innerHTML = "";

  const now = new Date();
  const visible = tasks.filter((t) => {
    const due = parseDateValue(t.dueDate);
    if (!due) return true;
    const diffDays = (due - now) / (1000 * 60 * 60 * 24);
    return diffDays >= 0 && diffDays <= 7;
  });

  emptyMessage.classList.toggle("hidden", visible.length > 0);

  visible.forEach((task) => {
    const badge = getBadgeInfo(task.dueDate);
    const li = document.createElement("li");
    li.className = "task-item";

    const memo = memos[task.id] || "";
    const mainLabel = cleanCourseName(task.courseName) || task.title;
    const subLabel = task.courseName ? task.title : ""  // subLabel은 원본 title 유지;
    const sourceTag = task.source === "etl"
      ? `<span class="source-tag etl-tag">eTL</span>`
      : "";
    const mainLink = task.url
      ? `<a class="task-title" href="${escapeHtml(task.url)}" target="_blank">${escapeHtml(mainLabel)}</a>`
      : `<p class="task-title">${escapeHtml(mainLabel)}</p>`;
    const subLabelHtml = subLabel
      ? `<span class="course-label">${escapeHtml(subLabel)}</span>`
      : "";

    li.innerHTML = `
      <div class="task-main">
        <div class="task-title-row">${sourceTag}${mainLink}</div>
        ${subLabelHtml}
        <div class="task-meta">
          <span class="due-date-text">마감일: ${formatDateTime(task.dueDate, task.dateOnly)}</span>
          <span class="due-badge ${badge.className}">${badge.text}</span>
          <button class="memo-btn" data-id="${task.id}" title="메모">✏️</button>
        </div>
        ${renderBombSlot(task)}
        <textarea class="memo-input${memo ? "" : " hidden"}" placeholder="메모 입력..." data-id="${task.id}">${escapeHtml(memo)}</textarea>
      </div>
      <button class="complete-btn" data-id="${task.id}">완료</button>
    `;

    const memoTextarea = li.querySelector(".memo-input");
    const memoBtn = li.querySelector(".memo-btn");

    function autoResize() {
      memoTextarea.style.height = "36px";
      memoTextarea.style.height = Math.max(36, memoTextarea.scrollHeight) + "px";
    }

    memoBtn.addEventListener("click", () => {
      memoTextarea.classList.toggle("hidden");
      if (!memoTextarea.classList.contains("hidden")) {
        autoResize();
        memoTextarea.focus();
      }
    });

    memoTextarea.addEventListener("input", () => {
      autoResize();
      const val = memoTextarea.value;
      if (val.trim()) {
        memos[task.id] = val;
      } else {
        delete memos[task.id];
      }
      saveMemos();
    });

    if (memo) autoResize();

    li.querySelector(".complete-btn").addEventListener("click", () => {
      completedTasks.unshift({ ...task, completedAt: new Date().toISOString() });
      if (completedTasks.length > 20) completedTasks.pop();
      tasks = tasks.filter((item) => item.id !== task.id);
      saveTasks();
      saveCompleted();
      renderTasks();
      renderCompleted();
      if (!calendarTab.classList.contains("hidden")) renderCalendar();
    });

    taskList.appendChild(li);
  });
  updateDeadlineBombs();
}

function renderCompleted() {
  if (!completedList) return;
  completedList.innerHTML = "";

  if (completedTasks.length === 0) {
    completedSection.classList.add("hidden");
    return;
  }

  completedSection.classList.remove("hidden");

  completedTasks.forEach((task) => {
    const li = document.createElement("li");
    li.className = "task-item completed-task-item";

    const mainLabel = cleanCourseName(task.courseName) || task.title;
    const subLabel = task.courseName ? task.title : ""  // subLabel은 원본 title 유지;
    const titleDisplay = task.url
      ? `<a class="task-title" href="${escapeHtml(task.url)}" target="_blank">${escapeHtml(mainLabel)}</a>`
      : `<p class="task-title">${escapeHtml(mainLabel)}</p>`;
    const subLabelHtml = subLabel
      ? `<span class="course-label">${escapeHtml(subLabel)}</span>`
      : "";

    li.innerHTML = `
      <div class="task-main">
        <div class="task-title-row">${titleDisplay}</div>
        ${subLabelHtml}
        <div class="task-meta">
          <span class="due-date-text">완료: ${formatDateTime(task.completedAt)}</span>
        </div>
      </div>
      <button class="restore-btn" data-id="${task.id}">되돌리기</button>
    `;

    li.querySelector(".restore-btn").addEventListener("click", () => {
      const { completedAt, ...restored } = task;
      tasks.push(restored);
      completedTasks = completedTasks.filter((t) => t.id !== task.id);
      saveTasks();
      saveCompleted();
      renderTasks();
      renderCompleted();
      if (!calendarTab.classList.contains("hidden")) renderCalendar();
    });

    completedList.appendChild(li);
  });
}

if (completedToggle) {
  completedToggle.addEventListener("click", () => {
    const isHidden = completedList.classList.toggle("hidden");
    if (completedToggleIcon) completedToggleIcon.textContent = isHidden ? "▼" : "▲";
  });
}

// ──────────────────────────────────────────
// 달력
// ──────────────────────────────────────────

function getHolidaysForDate(dateStr) {
  return HOLIDAYS.filter((h) => h.date === dateStr);
}

function getAcademicForDate(dateStr) {
  return ACADEMIC_SCHEDULE.filter((ev) => {
    if (ev.startDate && ev.endDate) return dateStr >= ev.startDate && dateStr <= ev.endDate;
    return ev.date === dateStr;
  });
}

function getAssignmentsForDate(dateStr) {
  return tasks.filter((t) => {
    if (!t.dueDate) return false;
    const d = new Date(t.dueDate);
    return toDateStr(d.getFullYear(), d.getMonth(), d.getDate()) === dateStr;
  });
}

function getUserEventsForDate(dateStr) {
  return calendarEvents.filter((ev) => ev.date === dateStr);
}

function renderCalendar() {
  const calDaysEl = document.getElementById("calDays");
  const calTitleEl = document.getElementById("calTitle");
  calTitleEl.textContent = `${calYear}년 ${calMonth + 1}월`;
  calDaysEl.innerHTML = "";

  const firstDay = new Date(calYear, calMonth, 1).getDay();
  const daysInMonth = new Date(calYear, calMonth + 1, 0).getDate();
  const daysInPrevMonth = new Date(calYear, calMonth, 0).getDate();

  const today = new Date();
  const todayStr = toDateStr(today.getFullYear(), today.getMonth(), today.getDate());

  const totalCells = Math.ceil((firstDay + daysInMonth) / 7) * 7;

  for (let i = 0; i < totalCells; i++) {
    let day, year, month, inCurrentMonth;

    if (i < firstDay) {
      day = daysInPrevMonth - firstDay + i + 1;
      year = calMonth === 0 ? calYear - 1 : calYear;
      month = calMonth === 0 ? 11 : calMonth - 1;
      inCurrentMonth = false;
    } else if (i - firstDay < daysInMonth) {
      day = i - firstDay + 1;
      year = calYear;
      month = calMonth;
      inCurrentMonth = true;
    } else {
      day = i - firstDay - daysInMonth + 1;
      year = calMonth === 11 ? calYear + 1 : calYear;
      month = calMonth === 11 ? 0 : calMonth + 1;
      inCurrentMonth = false;
    }

    const dateStr = toDateStr(year, month, day);
    const isToday = dateStr === todayStr;
    const isSelected = dateStr === calSelectedDate;
    const isSun = i % 7 === 0;
    const isSat = i % 7 === 6;

    const holidays = getHolidaysForDate(dateStr);
    const academic = getAcademicForDate(dateStr);
    const assignments = getAssignmentsForDate(dateStr);
    const userEvts = getUserEventsForDate(dateStr);

    const isHol = holidays.length > 0;

    const cell = document.createElement("div");
    cell.className = [
      "cal-day",
      inCurrentMonth ? "" : "other-month",
      isToday ? "today" : "",
      isSelected ? "selected" : "",
      isSun || isHol ? "sunday" : "",
      isSat ? "saturday" : "",
    ].filter(Boolean).join(" ");
    cell.dataset.date = dateStr;

    const allEvents = [
      ...holidays.map((e) => ({ text: e.title, type: "holiday" })),
      ...academic.map((e) => ({ text: e.title, type: "academic" })),
      ...assignments.map((e) => ({ text: cleanCourseName(e.courseName) || e.title, type: "assignment" })),
      ...userEvts.map((e) => ({ text: e.title, type: "user" })),
    ];

    const MAX_VISIBLE = 2;
    const visibleEvents = allEvents.slice(0, MAX_VISIBLE);
    const extraCount = allEvents.length - MAX_VISIBLE;

    const eventsHtml = visibleEvents.map((e) =>
      `<div class="cal-cell-event ${e.type}">${escapeHtml(formatCellText(e.text))}</div>`
    ).join("") + (extraCount > 0 ? `<div class="cal-cell-more">+${extraCount}</div>` : "");

    cell.innerHTML = `
      <span class="cal-day-num">${day}</span>
      <div class="cal-cell-events">${eventsHtml}</div>
    `;

    cell.addEventListener("click", () => {
      calSelectedDate = dateStr;
      renderCalendar();
      renderDayDetail(dateStr);
    });

    calDaysEl.appendChild(cell);
  }
}

function renderDayDetail(dateStr) {
  const detailEl = document.getElementById("calDayDetail");
  const selectedDateEl = document.getElementById("calSelectedDate");
  const eventListEl = document.getElementById("calEventList");

  detailEl.classList.remove("hidden");

  const [y, m, d] = dateStr.split("-").map(Number);
  selectedDateEl.textContent = `${m}월 ${d}일`;

  document.getElementById("calAddBtn").dataset.date = dateStr;

  const holidays = getHolidaysForDate(dateStr);
  const academic = getAcademicForDate(dateStr);
  const assignments = getAssignmentsForDate(dateStr);
  const userEvts = getUserEventsForDate(dateStr);

  eventListEl.innerHTML = "";

  if (holidays.length === 0 && academic.length === 0 && assignments.length === 0 && userEvts.length === 0) {
    eventListEl.innerHTML = '<li class="cal-no-events">일정이 없습니다.</li>';
    return;
  }

  holidays.forEach((ev) => {
    const li = document.createElement("li");
    li.className = "cal-event-item";
    li.innerHTML = `
      <span class="cal-event-dot holiday"></span>
      <span class="cal-event-title">${escapeHtml(ev.title)}</span>
      <span class="cal-event-tag holiday-tag">공휴일</span>
    `;
    eventListEl.appendChild(li);
  });

  academic.forEach((ev) => {
    const li = document.createElement("li");
    li.className = "cal-event-item";
    li.innerHTML = `
      <span class="cal-event-dot academic"></span>
      <span class="cal-event-title">${escapeHtml(ev.title)}</span>
      <span class="cal-event-tag academic-tag">학사</span>
    `;
    eventListEl.appendChild(li);
  });

  assignments.forEach((task) => {
    const li = document.createElement("li");
    li.className = "cal-event-item";
    const badge = getBadgeInfo(task.dueDate);
    const calLabel = cleanCourseName(task.courseName) || task.title;
    const titleEl = task.url
      ? `<a class="cal-event-title link" href="${escapeHtml(task.url)}" target="_blank">${escapeHtml(calLabel)}</a>`
      : `<span class="cal-event-title">${escapeHtml(calLabel)}</span>`;
    li.innerHTML = `
      <span class="cal-event-dot assignment"></span>
      ${titleEl}
      <span class="due-badge ${badge.className}" style="font-size:11px;padding:2px 8px">${badge.text}</span>
    `;
    eventListEl.appendChild(li);
  });

  userEvts.forEach((ev) => {
    const li = document.createElement("li");
    li.className = "cal-event-item";
    const timeLabel = ev.time ? `<span class="due-date-text" style="font-size:12px">${formatDateTime(ev.time)}</span>` : "";
    li.innerHTML = `
      <span class="cal-event-dot user"></span>
      <span class="cal-event-title">${escapeHtml(ev.title)}</span>
      ${timeLabel}
      <button class="cal-delete-btn" data-id="${ev.id}">✕</button>
    `;
    li.querySelector(".cal-delete-btn").addEventListener("click", () => {
      calendarEvents = calendarEvents.filter((e) => e.id !== ev.id);
      saveCalendarEvents();
      renderCalendar();
      renderDayDetail(dateStr);
    });
    eventListEl.appendChild(li);
  });
}

// 달력 네비게이션
document.getElementById("calPrev").addEventListener("click", () => {
  calMonth--;
  if (calMonth < 0) { calMonth = 11; calYear--; }
  calSelectedDate = null;
  document.getElementById("calDayDetail").classList.add("hidden");
  renderCalendar();
});

document.getElementById("calNext").addEventListener("click", () => {
  calMonth++;
  if (calMonth > 11) { calMonth = 0; calYear++; }
  calSelectedDate = null;
  document.getElementById("calDayDetail").classList.add("hidden");
  renderCalendar();
});

// 일정 추가 모달
const calModal = document.getElementById("calModal");
let calModalSelectedDate = null;

// 시간 피커 초기화
(function initTimePicker() {
  const hourInner = document.getElementById("hourInner");
  const minInner = document.getElementById("minInner");
  for (let h = 1; h <= 12; h++) {
    const el = document.createElement("div");
    el.className = "time-item";
    el.dataset.val = String(h);
    el.textContent = String(h);
    hourInner.appendChild(el);
  }
  for (let m = 0; m < 60; m += 5) {
    const el = document.createElement("div");
    el.className = "time-item";
    el.dataset.val = String(m).padStart(2, "0");
    el.textContent = String(m).padStart(2, "0");
    minInner.appendChild(el);
  }
})();

function scrollPickerTo(colId, index) {
  const col = document.getElementById(colId);
  col.scrollTop = index * 44;
}

function getPickerIndex(colId) {
  const col = document.getElementById(colId);
  const items = col.querySelectorAll(".time-item").length;
  return Math.max(0, Math.min(Math.round(col.scrollTop / 44), items - 1));
}

function openCalModal(date) {
  calModalSelectedDate = date;
  const [y, mo, d] = date.split("-").map(Number);
  document.getElementById("calModalDateLabel").textContent = `${mo}월 ${d}일`;
  document.getElementById("calModalTitle").value = "";
  calModal.classList.remove("hidden");
  // hidden 해제 후에 scrollTop 적용 (display:none 상태에서는 무시됨)
  requestAnimationFrame(() => {
    scrollPickerTo("ampmCol", 1); // 오후
    scrollPickerTo("hourCol", 5); // index 5 = 6시
    scrollPickerTo("minCol", 0);  // index 0 = 00분
  });
  document.getElementById("calModalTitle").focus();
}

document.getElementById("calAddBtn").addEventListener("click", () => {
  const date = document.getElementById("calAddBtn").dataset.date || toDateStr(calYear, calMonth, new Date().getDate());
  openCalModal(date);
});

document.getElementById("calModalCancel").addEventListener("click", () => {
  calModal.classList.add("hidden");
});

document.getElementById("calModalOverlay").addEventListener("click", () => {
  calModal.classList.add("hidden");
});

document.getElementById("calModalSave").addEventListener("click", () => {
  const title = document.getElementById("calModalTitle").value.trim();
  if (!title || !calModalSelectedDate) return;

  const ampmIdx = getPickerIndex("ampmCol");
  const hourIdx = getPickerIndex("hourCol");
  const minIdx = getPickerIndex("minCol");
  const isAm = ampmIdx === 0;
  const hour12 = hourIdx + 1;
  const min = minIdx * 5;
  let hour24;
  if (isAm) {
    hour24 = hour12 === 12 ? 0 : hour12;
  } else {
    hour24 = hour12 === 12 ? 12 : hour12 + 12;
  }

  const [y, mo, d] = calModalSelectedDate.split("-").map(Number);
  const dt = new Date(y, mo - 1, d, hour24, min);

  calendarEvents.push({
    id: `user_${Date.now()}`,
    title,
    date: calModalSelectedDate,
    time: dt.toISOString(),
  });
  saveCalendarEvents();
  subscribePush();
  checkDeadlines();
  calModal.classList.add("hidden");
  calSelectedDate = calModalSelectedDate;
  renderCalendar();
  renderDayDetail(calModalSelectedDate);
});

document.getElementById("calModalTitle").addEventListener("keydown", (e) => {
  if (e.key === "Enter") document.getElementById("calModalSave").click();
});

// ──────────────────────────────────────────
// 학교 소식
// ──────────────────────────────────────────

const newsToggle = document.getElementById("newsToggle");
const newsToggleIcon = document.getElementById("newsToggleIcon");
const newsBody = document.getElementById("newsBody");
const newsSchedule = document.getElementById("newsSchedule");
const newsNotices = document.getElementById("newsNotices");
const newsLoading = document.getElementById("newsLoading");
const newsError = document.getElementById("newsError");

newsToggle.addEventListener("click", () => {
  const hidden = newsBody.classList.toggle("hidden");
  newsToggleIcon.textContent = hidden ? "▼" : "▲";
});

document.querySelectorAll(".news-tab").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".news-tab").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    const tab = btn.dataset.tab;
    newsSchedule.classList.toggle("hidden", tab !== "schedule");
    newsNotices.classList.toggle("hidden", tab !== "notices");
  });
});

function formatNewsDate(isoString) {
  if (!isoString) return "";
  const d = new Date(isoString);
  if (isNaN(d)) return isoString;
  return `${String(d.getMonth() + 1).padStart(2, "0")}.${String(d.getDate()).padStart(2, "0")}`;
}

function renderSchedule(schedule) {
  const now = new Date();
  newsSchedule.innerHTML = "";
  schedule.forEach((item) => {
    const start = new Date(item.date || item.startDate);
    const end = item.endDate ? new Date(item.endDate) : null;
    const isPast = end ? end < now : start < now;
    const div = document.createElement("div");
    div.className = `news-item schedule-item${isPast ? " past" : ""}`;
    const dateText = item.endDate
      ? `${formatNewsDate(item.startDate || item.date)} ~ ${formatNewsDate(item.endDate)}`
      : formatNewsDate(item.date);
    div.innerHTML = `
      <span class="news-source-tag snu-tag">공식</span>
      <span class="news-title">${escapeHtml(item.title)}</span>
      <span class="news-date">${dateText}</span>
    `;
    newsSchedule.appendChild(div);
  });
}

function renderNotices(notices) {
  newsNotices.innerHTML = "";
  if (notices.length === 0) {
    newsNotices.innerHTML = `<p class="news-empty">불러온 공지가 없습니다.</p>`;
    return;
  }
  notices.forEach((item) => {
    const div = document.createElement("div");
    div.className = "news-item";
    const sourceClass = item.source === "wesnu" ? "wesnu-tag" : "dongari-tag";
    const sourceLabel = item.source === "wesnu" ? "총학" : "동아리";
    div.innerHTML = `
      <span class="news-source-tag ${sourceClass}">${sourceLabel}</span>
      ${item.url
        ? `<a class="news-title" href="${escapeHtml(item.url)}" target="_blank">${escapeHtml(item.title)}</a>`
        : `<span class="news-title">${escapeHtml(item.title)}</span>`}
      <span class="news-date">${formatNewsDate(item.date)}</span>
    `;
    newsNotices.appendChild(div);
  });
}

let newsLoaded = false;
async function loadEvents() {
  if (newsLoaded) return;
  newsLoading.classList.remove("hidden");
  newsError.classList.add("hidden");
  try {
    const res = await fetch(`${SERVER_URL}/api/events`);
    const data = await res.json();
    newsLoading.classList.add("hidden");
    newsLoaded = true;
    renderSchedule(data.schedule || []);
    renderNotices(data.notices || []);
  } catch {
    newsLoading.classList.add("hidden");
    newsError.textContent = "학교 소식을 불러오지 못했습니다.";
    newsError.classList.remove("hidden");
  }
}

// ──────────────────────────────────────────
// 설정 패널
// ──────────────────────────────────────────

function openSettings() {
  settingsPanel.classList.add("open");
  settingsOverlay.classList.add("open");
}
function closeSettings() {
  settingsPanel.classList.remove("open");
  settingsOverlay.classList.remove("open");
}

settingsBtn.addEventListener("click", openSettings);
settingsCloseBtn.addEventListener("click", closeSettings);
settingsOverlay.addEventListener("click", closeSettings);

function showEtlError(msg) {
  etlError.textContent = msg;
  etlError.classList.remove("hidden");
}
function hideEtlError() {
  etlError.classList.add("hidden");
}
function setConnectedUI() {
  etlSetupForm.classList.add("hidden");
  etlConnected.classList.remove("hidden");
}
function setDisconnectedUI() {
  etlSetupForm.classList.remove("hidden");
  etlConnected.classList.add("hidden");
  etlSyncStatus.textContent = "";
}

icalForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  hideEtlError();
  const url = icalUrlInput.value.trim();
  if (!url) { showEtlError("URL을 입력해주세요."); return; }
  if (!url.startsWith("webcal://") && !url.startsWith("https://")) {
    showEtlError("webcal:// 또는 https:// 로 시작하는 URL을 입력해주세요."); return;
  }
  if (!url.includes("etl.snu.ac.kr") && !url.includes("myetl.snu.ac.kr")) {
    showEtlError("eTL 캘린더 URL이 맞는지 확인해주세요."); return;
  }
  icalSaveBtn.disabled = true;
  icalSaveBtn.textContent = "가져오는 중...";
  icalUrl = url;
  localStorage.setItem(ICAL_URL_KEY, url);
  const ok = await syncIcal();
  if (ok) { setConnectedUI(); closeSettings(); }
  icalSaveBtn.disabled = false;
  icalSaveBtn.textContent = "저장 & 과제 가져오기";
});

etlSyncBtn.addEventListener("click", async () => {
  hideEtlError();
  etlSyncBtn.disabled = true;
  etlSyncBtn.textContent = "새로고침 중...";
  await syncIcal();
  etlSyncBtn.disabled = false;
  etlSyncBtn.textContent = "지금 새로고침";
});

etlDisconnectBtn.addEventListener("click", () => {
  icalUrl = null;
  localStorage.removeItem(ICAL_URL_KEY);
  tasks = tasks.filter((t) => t.source !== "etl");
  saveTasks();
  renderTasks();
  setDisconnectedUI();
  hideEtlError();
  icalUrlInput.value = "";
  openSettings();
});

if (apiTokenSaveBtn) {
  apiTokenSaveBtn.addEventListener("click", async () => {
    const token = apiTokenInput.value.trim();
    canvasToken = token || null;
    if (token) {
      localStorage.setItem(CANVAS_TOKEN_KEY, token);
      apiTokenSaveBtn.textContent = "저장됨 ✓";
    } else {
      localStorage.removeItem(CANVAS_TOKEN_KEY);
      apiTokenSaveBtn.textContent = "삭제됨";
    }
    setTimeout(() => { apiTokenSaveBtn.textContent = "저장"; }, 2000);
    if (icalUrl) await syncIcal();
  });
}

async function syncIcal(retrying = false) {
  if (!icalUrl) return false;
  if (retrying) etlSyncStatus.textContent = "서버 준비 중... 재시도 중";
  try {
    const res = await fetch(`${SERVER_URL}/api/sync-ical`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ icalUrl, apiToken: canvasToken || undefined }),
    });
    const data = await res.json();
    if (!res.ok) {
      showEtlError(data.error || "과제 불러오기 실패");
      etlSyncStatus.textContent = "동기화 실패";
      return false;
    }
    tasks = tasks.filter((t) => t.source !== "etl");
    data.forEach((a) => {
      tasks.push({
        id: `etl_${a.etlId}`,
        etlId: a.etlId,
        title: a.title,
        courseName: a.courseName,
        dueDate: a.dueDate,
        dateOnly: a.dateOnly || false,
        url: a.url || null,
        source: "etl",
      });
    });
    saveTasks();
    renderTasks();
    if (!calendarTab.classList.contains("hidden")) renderCalendar();
    checkDeadlines();
    subscribePush();
    lastSyncTime = Date.now();
    const now = new Date();
    const t = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
    etlSyncStatus.textContent = `마지막 동기화: ${t} (${data.length}개)`;
    return true;
  } catch {
    if (!retrying) {
      etlSyncStatus.textContent = "서버 깨우는 중... (최대 30초)";
      hideEtlError();
      setTimeout(() => syncIcal(true), 10000);
      return false;
    }
    showEtlError("서버에 연결할 수 없습니다. 잠시 후 다시 시도해주세요.");
    etlSyncStatus.textContent = "동기화 실패";
    return false;
  }
}

// 자동 sync: 30분마다 + 탭 복귀 시
let lastSyncTime = 0;
setInterval(() => {
  if (icalUrl) syncIcal();
}, 30 * 60 * 1000);

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && icalUrl) {
    const now = Date.now();
    if (now - lastSyncTime > 60 * 1000) { // 마지막 sync 후 1분 이상 지났을 때만
      lastSyncTime = now;
      syncIcal();
    }
  }
});

// ──────────────────────────────────────────
// 알림 (Web Push)
// ──────────────────────────────────────────

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = atob(base64);
  return Uint8Array.from([...rawData].map((c) => c.charCodeAt(0)));
}

async function subscribePush() {
  if (!("PushManager" in window) || !("serviceWorker" in navigator)) return;
  if (Notification.permission !== "granted") return;

  try {
    const reg = await navigator.serviceWorker.ready;
    const keyRes = await fetch(`${SERVER_URL}/api/push/vapid-public-key`);
    const { key } = await keyRes.json();

    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(key),
    });

    const etlTasks = tasks.filter((t) => t.source === "etl").map((t) => ({
      etlId: t.etlId || t.id,
      dueDate: t.dueDate,
      title: t.title,
      courseName: cleanCourseName(t.courseName),
      url: t.url || null,
    }));

    const userEventTasks = calendarEvents
      .filter((e) => e.time)
      .map((e) => ({
        etlId: e.id,
        dueDate: e.time,
        title: e.title,
        courseName: null,
        targets: [24, 12, 6, 3, 1],
      }));

    await fetch(`${SERVER_URL}/api/push/subscribe`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ subscription: sub, tasks: [...etlTasks, ...userEventTasks] }),
    });
  } catch (err) {
    console.warn("[push] 구독 실패:", err.message);
  }
}

async function requestNotificationPermission() {
  if (!("Notification" in window)) return;
  const result = await Notification.requestPermission();
  if (result === "granted") await subscribePush();
}

function checkDeadlines() {
  if (Notification.permission !== "granted") return;

  // ETL 과제: 24h부터 1h까지 매시간 (±1분 창에 들어올 때만 발송)
  const WINDOW_H = 1 / 60;
  const etlTasks = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
  etlTasks.forEach((task) => {
    const dueDate = parseDateValue(task.dueDate);
    if (!dueDate) return;
    const diffHours = (dueDate - new Date()) / (1000 * 60 * 60);
    if (diffHours < 0) return;
    Array.from({ length: 24 }, (_, i) => 24 - i).forEach((h) => {
      const key = `notified_${h}h_${task.id}`;
      if (diffHours <= h + WINDOW_H && diffHours > h - WINDOW_H && !localStorage.getItem(key)) {
        navigator.serviceWorker.ready.then((reg) => {
          reg.showNotification(
            `💣 마감 ${h}시간 전`,
            buildDeadlineNotification(task, diffHours, `${h}시간`)
          );
        });
        localStorage.setItem(key, "true");
      }
    });
  });

  // 사용자 직접 추가 일정: 24h / 5h (±1분 창에 들어올 때만 발송)
  const userEvents = JSON.parse(localStorage.getItem(CALENDAR_KEY)) || [];
  userEvents.filter((e) => e.time).forEach((ev) => {
    const dueDate = parseDateValue(ev.time);
    if (!dueDate) return;
    const diffHours = (dueDate - new Date()) / (1000 * 60 * 60);
    if (diffHours < 0) return;
    [24, 12, 6, 3, 1].forEach((h) => {
      const key = `notified_${h}h_${ev.id}`;
      if (diffHours <= h + WINDOW_H && diffHours > h - WINDOW_H && !localStorage.getItem(key)) {
        navigator.serviceWorker.ready.then((reg) => {
          reg.showNotification(`💣 일정 ${h}시간 전`, {
            body: `"${ev.title}" ${h}시간 전\n${String(h).padStart(2, "0")}:00 남음 ${buildBombProgressBar(h)}`,
            icon: "./icon-192.png",
            badge: "./icon-192.png",
            tag: `event-bomb-${ev.id}`,
            renotify: true,
            requireInteraction: true,
          });
        });
        localStorage.setItem(key, "true");
      }
    });
  });
}

// ──────────────────────────────────────────
// 식당 탭
// ──────────────────────────────────────────

const restaurantListEl = document.getElementById("restaurantList");
const FAVE_REST_KEY = "snu_fave_restaurant";
let restaurantDataCache = null;   // { list, snucoData, gangyeoData }
let restaurantFetching = false;
let selectedRestId = null;        // 현재 선택된 식당 id
let selectedMeal = null;          // "breakfast" | "lunch" | "dinner"
let faveRestId = localStorage.getItem(FAVE_REST_KEY) || null;

function toggleFave(id) {
  faveRestId = (faveRestId === id) ? null : id;
  if (faveRestId) localStorage.setItem(FAVE_REST_KEY, faveRestId);
  else            localStorage.removeItem(FAVE_REST_KEY);
  // 순서가 바뀌므로 사이드바 전체 재렌더
  if (restaurantDataCache) renderRestaurantLayout();
}

function getDefaultMeal() {
  const h = new Date().getHours();
  if (h < 9)  return "breakfast";
  if (h < 15) return "lunch";
  return "dinner";
}

// ─── 가나다 정렬 (숫자 시작은 맨 뒤) ───
function koreanSort(a, b) {
  const startsWithNum = s => /^\d/.test(s);
  const an = startsWithNum(a), bn = startsWithNum(b);
  if (an !== bn) return an ? 1 : -1;
  return a.localeCompare(b, "ko");
}

// ─── 사이드바 항목 빌드 ───
// snuco는 세부 식당 여러 개를 각각 항목으로 노출
function buildSidebarItems(list, snucoData) {
  const allItems = [];

  for (const info of list) {
    if (info.type === "snuco") {
      allItems.push({ id: "snuco_header", label: "SNU 학생식당", isHeader: true, isOpen: info.isOpen });
      if (snucoData && snucoData.restaurants) {
        const sorted = snucoData.restaurants
          .map((r, i) => ({ r, i, name: r.name.replace(/\s*\([\d-]+\)\s*$/, "").trim() }))
          .sort((a, b) => koreanSort(a.name, b.name));
        sorted.forEach(({ i, name }) => {
          allItems.push({ id: `snuco_${i}`, label: name, isHeader: false, isOpen: null });
        });
      }
    } else {
      allItems.push({ id: info.id, label: info.name, isHeader: false, isOpen: info.isOpen });
    }
  }

  // 즐겨찾기 항목을 맨 위로 이동
  if (faveRestId) {
    const faveItem = allItems.find(i => i.id === faveRestId && !i.isHeader);
    if (faveItem) {
      return [
        { id: "__fave_header", label: "즐겨찾기", isHeader: true, isFaveHeader: true },
        faveItem,
        { id: "__divider", label: "전체 식당", isHeader: true },
        ...allItems.filter(i => i.id !== faveRestId),
      ];
    }
  }
  return allItems;
}

// ─── 식사 메뉴 텍스트 → HTML ───
function formatMealLines(val) {
  const lines = val.split("\n").map(l => l.trim()).filter(Boolean);
  return lines.map(line => {
    if (/:\s*[\d,]+원/.test(line))              return `<span class="rest-menu-row">${escapeHtml(line)}</span>`;
    if (/운영시간|예약|문의|※|\d{1,2}:\d{2}/.test(line)) return `<span class="rest-menu-time">${escapeHtml(line)}</span>`;
    return `<span class="rest-menu-item">${escapeHtml(line)}</span>`;
  }).join("");
}

// ──────────────────────────────────────────
// 지도 탭
// ──────────────────────────────────────────

// SNU 주요 위치 데이터
// type: "restaurant" | "cafe" | "building"
// restId: 식당 탭 ID와 연결 (있을 때)
const SNU_LOCATIONS = [
  // ── 학생식당 (SNUCO) ──
  { id: "loc_hakgwan_rest",   name: "학생회관 식당",    type: "restaurant", lat: 37.4614, lng: 126.9493, note: "220동 1·2층", aliases: ["학생회관", "학생회관식당", "학관", "220동"] },
  { id: "loc_zahayeon_rest",  name: "자하연 식당",      type: "restaurant", lat: 37.4592, lng: 126.9453, note: "규장각 인근", aliases: ["자하연", "자하연식당", "109동"] },
  { id: "loc_sodam",          name: "소담마루",          type: "restaurant", lat: 37.4548, lng: 126.9510, note: "301동 인근", aliases: ["소담", "소담마루", "301동", "301동식당", "공대간이", "공대간이식당"] },
  { id: "loc_dure_rest",      name: "두레미담",          type: "restaurant", lat: 37.4607, lng: 126.9511, note: "63-1동", aliases: ["두레", "두레미담", "3식당", "제3식당", "제3학생식당", "75-1동", "농생대"] },
  { id: "loc_gongdae_rest",   name: "공대 식당",         type: "restaurant", lat: 37.4537, lng: 126.9506, note: "302동 인근", aliases: ["공대", "공대식당", "302동"] },
  { id: "loc_yesul_rest",     name: "예술계 식당",       type: "restaurant", lat: 37.4621, lng: 126.9500, note: "50동 인근", aliases: ["예술계", "예술계식당", "예술", "50동", "74동"] },
  { id: "loc_gamgol",         name: "감골식당",          type: "restaurant", lat: 37.4582, lng: 126.9461, note: "사범대 인근", aliases: ["감골", "감골식당", "사범대", "11동"] },
  { id: "loc_byeolmee",       name: "별미네",            type: "restaurant", lat: 37.4600, lng: 126.9504, note: "학교 내 식당", aliases: ["별미네"] },
  { id: "loc_dongwon_rest",   name: "동원관식당",        type: "restaurant", lat: 37.4623, lng: 126.9523, note: "113동 인근", aliases: ["동원관", "동원관식당", "113동"] },
  { id: "loc_dorm_rest",      name: "기숙사식당",        type: "restaurant", lat: 37.4629, lng: 126.9570, note: "919동 1층", aliases: ["기숙사", "기숙사식당", "919동"] },
  { id: "loc_boodang",        name: "불당",              type: "restaurant", lat: 37.4628, lng: 126.9581, note: "대학원 기숙사 인근", restId: "boodang", aliases: ["불당", "대학원기숙사", "대학원 기숙사"] },
  // ── 외부 식당 ──
  { id: "loc_burger",         name: "버거운버거",         type: "restaurant", lat: 37.4793, lng: 126.9513, note: "서울대입구역 상권", restId: "burgerwoober", aliases: ["버거운버거"] },
  { id: "loc_gangyeo",        name: "강여사집밥",          type: "restaurant", lat: 37.4800, lng: 126.9519, note: "서울대입구역 상권", restId: "gangyeo", aliases: ["강여사", "강여사집밥"] },
  // ── 카페 ──
  { id: "loc_cafe_library",   name: "스누리 카페",        type: "cafe", lat: 37.4639, lng: 126.9487, note: "중앙도서관 1층" },
  { id: "loc_cafe_hakgwan",   name: "학생회관 카페",       type: "cafe", lat: 37.4611, lng: 126.9493, note: "220동 1층" },
  { id: "loc_starbucks",      name: "스타벅스 서울대점",   type: "cafe", lat: 37.4616, lng: 126.9499, note: "학생회관 앞" },
  { id: "loc_cafe_inmun",     name: "인문대 카페",         type: "cafe", lat: 37.4609, lng: 126.9469, note: "인문대 1동" },
  // ── 건물 ──
  { id: "loc_library",        name: "중앙도서관",          type: "building", lat: 37.4639, lng: 126.9487, note: "62동" },
  { id: "loc_hakgwan_bld",    name: "학생회관",            type: "building", lat: 37.4614, lng: 126.9493, note: "220동" },
  { id: "loc_bonkwan",        name: "본관 (행정관)",       type: "building", lat: 37.4616, lng: 126.9476, note: "60동" },
  { id: "loc_dure_bld",       name: "두레문예관",          type: "building", lat: 37.4607, lng: 126.9509, note: "학생 문화공간" },
  { id: "loc_gate",           name: "SNU 정문",            type: "building", lat: 37.4596, lng: 126.9516, note: "관악캠퍼스 정문" },
  { id: "loc_gongdae_bld",    name: "공과대학",            type: "building", lat: 37.4535, lng: 126.9505, note: "301·302동 일대" },
  { id: "loc_inmun_bld",      name: "인문대학",            type: "building", lat: 37.4609, lng: 126.9468, note: "1·2동 일대" },
  { id: "loc_sahoe_bld",      name: "사회과학대학",        type: "building", lat: 37.4601, lng: 126.9522, note: "16동" },
  { id: "loc_gyeong_bld",     name: "경영대학",            type: "building", lat: 37.4623, lng: 126.9523, note: "58동" },
  { id: "loc_jawoon_bld",     name: "자연과학대학",        type: "building", lat: 37.4573, lng: 126.9496, note: "500동 일대" },
  { id: "loc_sabum_bld",      name: "사범대학",            type: "building", lat: 37.4581, lng: 126.9461, note: "11동 일대" },
  { id: "loc_subway",         name: "서울대입구역",        type: "building", lat: 37.4811, lng: 126.9531, note: "지하철 2호선" },
];

// 카카오맵 길찾기 URL
function kakaoNavUrl(lat, lng, name) {
  return `https://map.kakao.com/link/to/${encodeURIComponent(name)},${lat},${lng}`;
}

function normalizeRestaurantName(value) {
  return String(value || "")
    .replace(/\s*\([\d-]+\)\s*$/, "")
    .replace(/\s+/g, "")
    .replace(/식당$/g, "")
    .trim();
}

// 식당 id / name → SNU_LOCATIONS 매칭
function getRestaurantLoc(id, name) {
  const byRestId = SNU_LOCATIONS.find(l => l.restId === id);
  if (byRestId) return byRestId;

  const cleanName = normalizeRestaurantName(name);
  if (!cleanName) return null;

  const byName = SNU_LOCATIONS.find(l => {
    if (l.type !== "restaurant") return false;
    const candidates = [l.name, ...(l.aliases || [])].map(normalizeRestaurantName);
    return candidates.some(candidate => {
      if (!candidate) return false;
      if (candidate === cleanName) return true;
      if (candidate.length < 3 || cleanName.length < 3) return false;
      return candidate.includes(cleanName) || cleanName.includes(candidate);
    });
  });
  if (byName) return byName;

  // 건물 번호로 note/alias 매칭 (예: "220동 식당" → note "220동 1·2층")
  const dongMatch = cleanName.match(/(\d{2,3})동/);
  if (dongMatch) {
    return SNU_LOCATIONS.find(l =>
      l.type === "restaurant" &&
      `${l.note || ""} ${(l.aliases || []).join(" ")}`.includes(dongMatch[0])
    ) || null;
  }

  return null;
}

// 카카오맵 상태
let kakaoMap = null;
let mapOriginLoc = null; // null = 현재 위치
let mapDestLoc = null;
let locationOverlay = null;
let accuracyCircle = null;
let orientationListenerAdded = false;
let onOrientationHandler = null;
let latestPosition = null;
let destOverlay = null;
let kakaoMapsLoadPromise = null;
let smoothedHeading = null;
let lastHeadingUpdateAt = 0;

const HEADING_DEADBAND_DEG = 6;
const HEADING_MIN_UPDATE_MS = 120;
const HEADING_SMOOTHING = 0.18;

function isKakaoMapsReady() {
  return !!(window.kakao && kakao.maps && kakao.maps.Map);
}

function getKakaoMapSetupMessage() {
  return `카카오 지도 인증에 실패했습니다. Kakao Developers에서 JavaScript SDK 도메인에 ${location.origin} 을 등록하고, 제품 설정의 카카오맵 API가 켜져 있는지 확인해주세요.`;
}

function normalizeHeading(deg) {
  return ((deg % 360) + 360) % 360;
}

function getShortestHeadingDelta(from, to) {
  return ((to - from + 540) % 360) - 180;
}

function smoothHeading(current, next) {
  const normalizedNext = normalizeHeading(next);
  if (current === null) return normalizedNext;

  const delta = getShortestHeadingDelta(current, normalizedNext);
  if (Math.abs(delta) < HEADING_DEADBAND_DEG) return current;

  return normalizeHeading(current + delta * HEADING_SMOOTHING);
}

function loadKakaoMapsSdk() {
  if (isKakaoMapsReady()) return Promise.resolve();
  if (kakaoMapsLoadPromise) return kakaoMapsLoadPromise;

  kakaoMapsLoadPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    const timeoutId = setTimeout(() => {
      fail(new Error("Kakao Maps SDK load timeout"));
    }, 10000);

    function done() {
      clearTimeout(timeoutId);
      resolve();
    }

    function fail(err) {
      clearTimeout(timeoutId);
      reject(err);
    }

    function finishLoad() {
      if (!window.kakao || !kakao.maps || typeof kakao.maps.load !== "function") {
        fail(new Error("Kakao Maps SDK authorization failed"));
        return;
      }
      kakao.maps.load(() => {
        if (isKakaoMapsReady()) {
          done();
        } else {
          fail(new Error("Kakao Maps SDK initialized without Map"));
        }
      });
    }

    script.src = `https://dapi.kakao.com/v2/maps/sdk.js?appkey=${KAKAO_MAP_APP_KEY}&autoload=false&libraries=services`;
    script.async = true;
    script.dataset.kakaoMapSdk = "true";
    script.onload = finishLoad;
    script.onerror = () => fail(new Error("Kakao Maps SDK network or authorization error"));

    document.head.appendChild(script);
  }).catch((err) => {
    kakaoMapsLoadPromise = null;
    throw err;
  });

  return kakaoMapsLoadPromise;
}

function getMapStatusEl() {
  const container = document.getElementById("mapContainer");
  if (!container) return null;
  let el = document.getElementById("mapStatus");
  if (!el) {
    el = document.createElement("div");
    el.id = "mapStatus";
    container.appendChild(el);
  }
  return el;
}

function showMapStatus(msg) {
  const el = getMapStatusEl();
  if (!el) return;
  el.textContent = msg;
  el.style.display = msg ? "block" : "none";
}

function hideMapStatus() {
  const el = document.getElementById("mapStatus");
  if (el) {
    el.textContent = "";
    el.style.display = "none";
  }
}

function renderMapTab() {
  const container = document.getElementById("mapContainer");
  if (!container) return;

  if (!isKakaoMapsReady()) {
    showMapStatus("카카오 지도를 불러오는 중...");
    loadKakaoMapsSdk()
      .then(() => {
        if (!mapTab.classList.contains("hidden")) renderMapTab();
      })
      .catch(() => showMapStatus(getKakaoMapSetupMessage()));
    return;
  }

  hideMapStatus();

  if (!kakaoMap) {
    const saved = JSON.parse(localStorage.getItem("map_last_pos") || "null");
    const initCenter = saved
      ? new kakao.maps.LatLng(saved.lat, saved.lng)
      : new kakao.maps.LatLng(37.4651, 126.9507);
    kakaoMap = new kakao.maps.Map(container, {
      center: initCenter,
      level: 3,
    });

    startLocationWatch();

    const btn = document.createElement("button");
    btn.className = "map-locate-btn";
    btn.innerHTML = "📍";
    btn.title = "내 위치";
    btn.addEventListener("click", () => {
      if (locationOverlay) {
        kakaoMap.setCenter(locationOverlay.getPosition());
        kakaoMap.setLevel(3);
      }
      requestOrientationPermission();
    });
    container.appendChild(btn);
  }

  setTimeout(() => {
    resizeMapContainer();
  }, 80);

  initMapRouteSearch();
}

// 지도 컨테이너 높이를 실제 남은 공간에 맞게 동적 조정
function resizeMapContainer() {
  const el = document.getElementById("mapContainer");
  if (!el || mapTab.classList.contains("hidden")) return;
  const top = el.getBoundingClientRect().top + window.scrollY;
  el.style.height = `${Math.max(200, window.innerHeight - top - 4)}px`;
  if (kakaoMap) {
    const center = kakaoMap.getCenter();
    kakaoMap.relayout();
    kakaoMap.setCenter(center);
  }
}
window.addEventListener("resize", resizeMapContainer);

// 교통수단별 경로 데이터 { duration, distance, path: [[lat,lng],...], estimated? }
let routeData = {};
let currentPolyline = null;
let currentRouteMode = "car";

const MODE_COLORS = { car: "#2563eb", transit: "#7c3aed", walk: "#16a34a", bike: "#ea580c" };
const MODE_STROKE = { car: "solid", transit: "dash", walk: "solid", bike: "shortdash" };

function haversineM(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function formatDuration(seconds) {
  const m = Math.round(seconds / 60);
  if (m < 60) return `${m}분`;
  const h = Math.floor(m / 60);
  const rem = m % 60;
  return rem > 0 ? `${h}시간 ${rem}분` : `${h}시간`;
}

function formatDistance(m) {
  return m >= 1000 ? `${(m / 1000).toFixed(1)}km` : `${Math.round(m)}m`;
}

async function fetchOsrmRoute(origin, dest, profile) {
  const url = `${SERVER_URL}/api/route/osrm?profile=${profile}&olat=${origin.lat}&olng=${origin.lng}&dlat=${dest.lat}&dlng=${dest.lng}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error("OSRM 실패");
  return res.json();
}

async function fetchAllRoutes(origin, dest) {
  routeData = {};
  showMapMessage("경로를 불러오는 중...");

  // 목적지 마커
  if (destOverlay) { destOverlay.setMap(null); destOverlay = null; }
  const destEl = document.createElement("div");
  destEl.className = "map-dest-marker";
  destEl.innerHTML = `<div class="map-dest-pin">📍</div><div class="map-dest-label">${escapeHtml(dest.name || "")}</div>`;
  destOverlay = new kakao.maps.CustomOverlay({
    position: new kakao.maps.LatLng(dest.lat, dest.lng),
    content: destEl, yAnchor: 1.2, zIndex: 9,
  });
  destOverlay.setMap(kakaoMap);

  // 탭 로딩 상태
  document.querySelectorAll(".map-route-mode-btn").forEach((b) => {
    b.classList.add("loading");
    b.querySelector(".mode-time").textContent = "...";
  });
  document.getElementById("mapRouteInfo").classList.remove("hidden");
  resizeMapContainer();

  // 버스: 거리 기반 추정
  const straight = haversineM(origin.lat, origin.lng, dest.lat, dest.lng);
  routeData.transit = {
    duration: straight * 1.5 / (18000 / 3600) + 8 * 60,
    distance: straight * 1.5,
    path: null,
    estimated: true,
  };

  // 자동차, 도보, 자전거 병렬 호출
  const [carRes, walkRes, bikeRes] = await Promise.allSettled([
    (async () => {
      const res = await fetch(`${SERVER_URL}/api/directions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ origin, destination: { lat: dest.lat, lng: dest.lng } }),
      });
      const data = await res.json();
      const route = data.routes?.[0];
      if (!route || route.result_code !== 0) throw new Error("자동차 경로 없음");
      const path = [];
      for (const section of route.sections || []) {
        for (const road of section.roads || []) {
          const v = road.vertexes;
          for (let i = 0; i < v.length - 1; i += 2) path.push([v[i + 1], v[i]]);
        }
      }
      return { duration: route.summary?.duration, distance: route.summary?.distance, path };
    })(),
    fetchOsrmRoute(origin, dest, "foot"),
    fetchOsrmRoute(origin, dest, "bicycle"),
  ]);

  if (carRes.status === "fulfilled") routeData.car = carRes.value;
  else routeData.car = { duration: straight / (40000 / 3600), distance: straight, path: null, estimated: true };
  if (walkRes.status === "fulfilled") routeData.walk = walkRes.value;
  else routeData.walk = { duration: straight * 1.3 / (4000 / 3600), distance: straight * 1.3, path: null, estimated: true };
  if (bikeRes.status === "fulfilled") routeData.bike = bikeRes.value;
  else routeData.bike = { duration: straight * 1.2 / (15000 / 3600), distance: straight * 1.2, path: null, estimated: true };

  // 모든 탭 시간 업데이트
  ["car", "transit", "walk", "bike"].forEach((mode) => {
    const el = document.getElementById(`modeTime_${mode}`);
    const btn = document.querySelector(`.map-route-mode-btn[data-mode="${mode}"]`);
    if (el && routeData[mode]) el.textContent = formatDuration(routeData[mode].duration);
    if (btn) btn.classList.remove("loading");
  });

  // 지도 bounds 맞추기
  const bounds = new kakao.maps.LatLngBounds();
  bounds.extend(new kakao.maps.LatLng(origin.lat, origin.lng));
  bounds.extend(new kakao.maps.LatLng(dest.lat, dest.lng));
  kakaoMap.setBounds(bounds, 60);

  setActiveMode(currentRouteMode);
  showMapMessage("");
}

function setActiveMode(mode) {
  currentRouteMode = mode;
  document.querySelectorAll(".map-route-mode-btn").forEach((b) => b.classList.toggle("active", b.dataset.mode === mode));

  if (currentPolyline) { currentPolyline.setMap(null); currentPolyline = null; }

  const data = routeData[mode];
  const timeEl = document.getElementById("mapRouteTime");
  const distEl = document.getElementById("mapRouteDist");
  if (data) {
    if (timeEl) timeEl.textContent = (data.estimated ? "약 " : "") + formatDuration(data.duration);
    if (distEl) distEl.textContent = formatDistance(data.distance);

    if (data.path && data.path.length && kakaoMap) {
      currentPolyline = new kakao.maps.Polyline({
        path: data.path.map(([lat, lng]) => new kakao.maps.LatLng(lat, lng)),
        strokeWeight: 5,
        strokeColor: MODE_COLORS[mode] || "#2563eb",
        strokeOpacity: 0.9,
        strokeStyle: MODE_STROKE[mode] || "solid",
      });
      currentPolyline.setMap(kakaoMap);
    }
  }
}

function searchSNULocations(q) {
  const norm = q.trim().toLowerCase();
  if (!norm) return [];
  return SNU_LOCATIONS.filter((l) => {
    const candidates = [l.name, ...(l.aliases || [])];
    return candidates.some((n) => n.toLowerCase().includes(norm));
  }).slice(0, 5);
}

let routeSearchTimer = null;

function initMapRouteSearch() {
  const originInput = document.getElementById("mapOriginInput");
  const destInput = document.getElementById("mapDestInput");
  const suggestions = document.getElementById("mapRouteSuggestions");
  const swapBtn = document.getElementById("mapRouteSwapBtn");
  const goBtn = document.getElementById("mapRouteGoBtn");
  const clearBtn = document.getElementById("mapRouteClearBtn");
  const infoEl = document.getElementById("mapRouteInfo");

  if (!originInput || originInput.dataset.routeInit) return;
  originInput.dataset.routeInit = "true";

  // 교통수단 모드 버튼
  document.querySelectorAll(".map-route-mode-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      if (!routeData[btn.dataset.mode]) return;
      setActiveMode(btn.dataset.mode);
    });
  });

  function renderSuggestions(results, forInput, loading = false) {
    suggestions.innerHTML = "";
    if (loading) {
      const li = document.createElement("li");
      li.className = "map-route-suggestion-item suggestion-loading";
      li.textContent = "검색 중...";
      suggestions.appendChild(li);
      suggestions.classList.remove("hidden");
      return;
    }
    if (!results.length) { suggestions.classList.add("hidden"); return; }

    results.forEach((loc) => {
      const li = document.createElement("li");
      li.className = "map-route-suggestion-item";
      const catIcon = loc.type === "restaurant" ? "🍽️"
        : loc.type === "cafe" ? "☕"
        : loc.category?.includes("음식") ? "🍽️"
        : loc.category?.includes("카페") ? "☕"
        : loc.category?.includes("편의") ? "🏪"
        : loc.category?.includes("병원") ? "🏥"
        : loc.category?.includes("학교") ? "🏫"
        : loc.category?.includes("지하철") || loc.category?.includes("교통") ? "🚇"
        : "📍";
      const sub = escapeHtml(loc.address || loc.note || "");
      const cat = escapeHtml(loc.category || "");
      li.innerHTML = `
        <span class="suggestion-icon">${catIcon}</span>
        <span class="suggestion-body">
          <span class="suggestion-name">${escapeHtml(loc.name)}</span>
          ${sub ? `<span class="suggestion-addr">${sub}</span>` : ""}
        </span>
        ${cat ? `<span class="suggestion-cat">${cat}</span>` : ""}
      `;
      li.addEventListener("mousedown", (e) => {
        e.preventDefault();
        if (forInput === "origin") { mapOriginLoc = loc; originInput.value = loc.name; }
        else { mapDestLoc = loc; destInput.value = loc.name; }
        suggestions.classList.add("hidden");
      });
      suggestions.appendChild(li);
    });
    suggestions.classList.remove("hidden");
  }

  async function kakaoSearchPlaces(q) {
    const lat = latestPosition?.lat || 37.4651;
    const lng = latestPosition?.lng || 126.9507;

    // 1순위: Kakao Maps SDK Places (카카오맵과 동일한 검색 엔진)
    try {
      if (!window.kakao?.maps?.services?.Places) {
        await loadKakaoMapsSdk();
      }
      if (window.kakao?.maps?.services?.Places) {
        return await new Promise((resolve, reject) => {
          const ps = new kakao.maps.services.Places();
          ps.keywordSearch(q, (result, status) => {
            if (status === kakao.maps.services.Status.OK) {
              resolve(result.map((d) => ({
                name: d.place_name,
                address: d.road_address_name || d.address_name,
                lat: parseFloat(d.y),
                lng: parseFloat(d.x),
                category: d.category_group_name || d.category_name?.split(">")[0]?.trim() || "",
                type: "kakao",
              })));
            } else if (status === kakao.maps.services.Status.ZERO_RESULT) {
              resolve([]);
            } else {
              reject(new Error("Places 검색 실패: " + status));
            }
          }, {
            location: new kakao.maps.LatLng(lat, lng),
            radius: 20000,
            sort: kakao.maps.services.SortBy.ACCURACY,
          });
        });
      }
    } catch (e) {
      console.warn("[search] SDK 실패, 서버 프록시로:", e.message);
    }

    // 2순위: 서버 프록시 폴백
    const params = new URLSearchParams({ q, x: lng, y: lat });
    const res = await fetch(`${SERVER_URL}/api/search-place?${params}`);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error("서버 검색 실패: " + (body.error || res.status));
    }
    return (await res.json()).map((d) => ({ ...d, type: "kakao" }));
  }

  async function fetchAndShow(q, forInput) {
    if (q.trim().length < 1) { suggestions.classList.add("hidden"); return; }

    // 즉시 로컬 SNU 결과 표시
    const local = searchSNULocations(q);
    if (local.length) renderSuggestions(local, forInput);
    else renderSuggestions([], forInput, true); // 로딩 표시

    clearTimeout(routeSearchTimer);
    routeSearchTimer = setTimeout(async () => {
      try {
        const remote = await kakaoSearchPlaces(q);
        const localNames = new Set(local.map((l) => l.name));
        const merged = [...local, ...remote.filter((r) => !localNames.has(r.name))];
        renderSuggestions(merged, forInput);
      } catch (e) {
        if (local.length) renderSuggestions(local, forInput);
        else suggestions.classList.add("hidden");
      }
    }, 300);
  }

  originInput.addEventListener("focus", () => { if (originInput.value === "현재 위치") originInput.value = ""; });
  originInput.addEventListener("blur", () => {
    if (!originInput.value.trim()) { originInput.value = "현재 위치"; mapOriginLoc = null; }
    setTimeout(() => suggestions.classList.add("hidden"), 200);
  });
  originInput.addEventListener("input", () => fetchAndShow(originInput.value, "origin"));

  destInput.addEventListener("blur", () => setTimeout(() => suggestions.classList.add("hidden"), 200));
  destInput.addEventListener("input", () => fetchAndShow(destInput.value, "dest"));

  swapBtn.addEventListener("click", () => {
    const tmpLoc = mapOriginLoc;
    const tmpVal = originInput.value;
    mapOriginLoc = mapDestLoc;
    originInput.value = mapDestLoc ? mapDestLoc.name : "현재 위치";
    mapDestLoc = tmpLoc;
    destInput.value = tmpVal === "현재 위치" ? "" : tmpVal;
  });

  goBtn.addEventListener("click", async () => {
    const originPos = mapOriginLoc ? { lat: mapOriginLoc.lat, lng: mapOriginLoc.lng } : latestPosition;
    if (!originPos) { showMapMessage("현재 위치를 찾는 중입니다."); return; }
    if (!mapDestLoc) { showMapMessage("도착지를 선택해주세요."); return; }
    clearBtn.classList.remove("hidden");
    currentRouteMode = "car";
    await fetchAllRoutes(originPos, { lat: mapDestLoc.lat, lng: mapDestLoc.lng, name: mapDestLoc.name });
  });

  clearBtn.addEventListener("click", () => {
    if (currentPolyline) { currentPolyline.setMap(null); currentPolyline = null; }
    if (destOverlay) { destOverlay.setMap(null); destOverlay = null; }
    clearBtn.classList.add("hidden");
    infoEl.classList.add("hidden");
    routeData = {};
    showMapMessage("");
    resizeMapContainer();
  });
}

function startLocationWatch() {
  if (!navigator.geolocation) {
    showMapMessage("이 브라우저에서는 위치 권한을 사용할 수 없습니다.");
    return;
  }
  if (!window.isSecureContext && location.hostname !== "localhost" && location.hostname !== "127.0.0.1") {
    showMapMessage("현재 위치는 HTTPS에서만 사용할 수 있습니다.");
    return;
  }

  let firstFix = true;

  const dotEl = document.createElement("div");
  dotEl.className = "map-location-icon";
  dotEl.innerHTML = `<svg viewBox="-16 -28 32 44" width="32" height="44" overflow="visible">
    <path class="map-heading-cone" d="M0,-26 L-10,-6 L10,-6 Z"
      fill="rgba(37,99,235,0.5)" stroke="none" display="none"/>
    <circle cx="0" cy="0" r="8" fill="#2563eb" stroke="white" stroke-width="2.5"/>
  </svg>`;

  navigator.geolocation.watchPosition(
    (pos) => {
      const { latitude: lat, longitude: lng, accuracy } = pos.coords;
      const position = new kakao.maps.LatLng(lat, lng);
      latestPosition = { lat, lng };
      localStorage.setItem("map_last_pos", JSON.stringify({ lat, lng }));
      const cappedRadius = Math.min(accuracy, 14);

      if (!locationOverlay) {
        locationOverlay = new kakao.maps.CustomOverlay({
          position,
          content: dotEl,
          zIndex: 10,
        });
        locationOverlay.setMap(kakaoMap);

        accuracyCircle = new kakao.maps.Circle({
          center: position,
          radius: cappedRadius,
          strokeWeight: 1,
          strokeColor: "#2563eb",
          strokeOpacity: 0.35,
          fillColor: "#2563eb",
          fillOpacity: 0.06,
        });
        accuracyCircle.setMap(kakaoMap);
      } else {
        locationOverlay.setPosition(position);
        accuracyCircle.setOptions({ center: position, radius: cappedRadius });
      }

      if (firstFix) {
        kakaoMap.setCenter(position);
        kakaoMap.setLevel(3);
        firstFix = false;
      }
    },
    (err) => {
      const denied = err && err.code === err.PERMISSION_DENIED;
      showMapMessage(denied
        ? "위치 권한이 꺼져 있어 현재 위치 없이 지도를 표시합니다."
        : "현재 위치를 가져오지 못했습니다.");
    },
    { enableHighAccuracy: true, maximumAge: 5000, timeout: 10000 }
  );

  onOrientationHandler = function (e) {
    let heading = null;
    if (typeof e.webkitCompassHeading === "number") {
      heading = e.webkitCompassHeading;
    } else if (typeof e.alpha === "number") {
      heading = (360 - e.alpha) % 360;
    }
    if (heading === null) return;

    const now = window.performance ? performance.now() : Date.now();
    if (smoothedHeading !== null && now - lastHeadingUpdateAt < HEADING_MIN_UPDATE_MS) return;

    const nextHeading = smoothHeading(smoothedHeading, heading);
    if (smoothedHeading !== null && nextHeading === smoothedHeading) return;

    smoothedHeading = nextHeading;
    lastHeadingUpdateAt = now;

    const svg = dotEl.querySelector("svg");
    const cone = dotEl.querySelector(".map-heading-cone");
    if (!svg || !cone) return;
    cone.removeAttribute("display");
    svg.style.transform = `rotate(${smoothedHeading.toFixed(1)}deg)`;
  };

  if (typeof DeviceOrientationEvent === "undefined" ||
      typeof DeviceOrientationEvent.requestPermission !== "function") {
    window.addEventListener("deviceorientationabsolute", onOrientationHandler, true);
    window.addEventListener("deviceorientation", onOrientationHandler, true);
    orientationListenerAdded = true;
  }
}

function requestOrientationPermission() {
  if (orientationListenerAdded) return;
  if (typeof DeviceOrientationEvent === "undefined") return;
  if (typeof DeviceOrientationEvent.requestPermission !== "function") return;
  DeviceOrientationEvent.requestPermission()
    .then(state => {
      if (state === "granted" && onOrientationHandler) {
        window.addEventListener("deviceorientation", onOrientationHandler);
        orientationListenerAdded = true;
      }
    })
    .catch(() => {});
}

// ─── 인앱 길찾기 ───
async function showRestaurantRoute(loc, originPos) {
  document.querySelector('.tab-btn[data-tab="map"]').click();
  const origin = originPos || latestPosition;
  if (!origin) {
    setTimeout(() => showMapMessage("위치를 확인 중입니다. 잠시 후 다시 시도해주세요."), 400);
    return;
  }
  // 도착지 입력창 업데이트
  const destInput = document.getElementById("mapDestInput");
  if (destInput) destInput.value = loc.name || "";
  mapDestLoc = { lat: loc.lat, lng: loc.lng, name: loc.name };
  currentRouteMode = "car";
  document.getElementById("mapRouteClearBtn")?.classList.remove("hidden");
  await fetchAllRoutes(origin, { lat: loc.lat, lng: loc.lng, name: loc.name });
}

function showMapMessage(msg) {
  const container = document.getElementById("mapContainer");
  if (!container) return;
  let el = document.getElementById("mapMessage");
  if (!el) {
    el = document.createElement("div");
    el.id = "mapMessage";
    container.appendChild(el);
  }
  el.textContent = msg;
  el.style.display = msg ? "block" : "none";
}

// ─── 디테일 패널 HTML ───
function buildDetailHtml(id, list, snucoData, gangyeoData) {
  // snuco 세부 식당
  if (id && id.startsWith("snuco_") && id !== "snuco_header") {
    const idx = parseInt(id.replace("snuco_", ""), 10);
    if (!snucoData || !snucoData.restaurants) return `<p class="rest-detail-empty">메뉴 정보 없음</p>`;
    const r = snucoData.restaurants[idx];
    if (!r) return `<p class="rest-detail-empty">메뉴 정보 없음</p>`;

    const name  = r.name.replace(/\s*\([\d-]+\)\s*$/, "").trim();
    const phone = (r.name.match(/\(([\d-]+)\)/) || [])[1] || "";

    // 있는 식사 항목 중 내용이 다른 것만 추출 (중복 내용은 탭 안 만듦)
    const MEAL_DEFS = [
      { key: "breakfast", label: "조식" },
      { key: "lunch",     label: "점심" },
      { key: "dinner",    label: "저녁" },
    ];
    const seen = new Set();
    const available = MEAL_DEFS.filter(m => {
      const val = r[m.key];
      if (!val || val === "정보 없음") return false;
      if (seen.has(val)) return false;
      seen.add(val);
      return true;
    });

    // 표시할 식사 결정 (기본값: 시간 기반, 없으면 첫 번째)
    let meal = selectedMeal;
    if (!available.find(m => m.key === meal)) {
      meal = available[0]?.key || "lunch";
    }

    const val = r[meal] || "";
    const content = val
      ? `<div class="rest-detail-lines">${formatMealLines(val)}</div>`
      : `<p class="rest-detail-empty">정보 없음</p>`;

    // 식사 구분이 2개 이상일 때만 탭 표시
    const tabsHtml = available.length >= 2
      ? `<div class="rest-meal-tabs">${
          available.map(m =>
            `<button class="rest-meal-tab${meal === m.key ? " active" : ""}" data-meal="${m.key}">${m.label}</button>`
          ).join("")
        }</div>`
      : "";

    const snucoLoc = getRestaurantLoc(id, name);
    const snucoNavBtn = snucoLoc
      ? `<button class="rest-nav-btn" data-lat="${snucoLoc.lat}" data-lng="${snucoLoc.lng}" data-name="${escapeHtml(name)}">🗺️ 길찾기</button>`
      : "";

    return `
      <div class="rest-detail-title">${escapeHtml(name)}</div>
      ${phone ? `<p class="rest-detail-phone">📞 ${escapeHtml(phone)}</p>` : ""}
      ${snucoNavBtn}
      ${tabsHtml}
      <div class="rest-meal-content">${content}</div>`;
  }

  // snuco_header 클릭 — 안내 메시지
  if (id === "snuco_header") {
    return `<p class="rest-detail-empty">왼쪽에서 세부 식당을 선택하세요.</p>`;
  }

  // 일반 식당 (강여사집밥, 불당 등)
  const info = list.find(r => r.id === id);
  if (!info) return `<p class="rest-detail-empty">정보 없음</p>`;

  const extLoc = getRestaurantLoc(id, info.name);
  const extNavBtn = extLoc
    ? `<button class="rest-nav-btn" data-lat="${extLoc.lat}" data-lng="${extLoc.lng}" data-name="${escapeHtml(info.name)}">🗺️ 길찾기</button>`
    : "";

  let html = `<div class="rest-detail-title">${escapeHtml(info.name)}</div>`;

  const openBadge = info.isOpen === true
    ? `<span class="rest-open">영업중</span>`
    : info.isOpen === false
    ? `<span class="rest-closed">영업종료</span>`
    : "";
  if (openBadge) html += `<div style="margin-bottom:10px">${openBadge}</div>`;
  if (extNavBtn) html += `<div style="margin-bottom:10px">${extNavBtn}</div>`;

  const tags = (info.tags || []).map(t => `<span class="rest-tag">${escapeHtml(t)}</span>`).join("");
  if (tags) html += `<div class="rest-tags" style="margin-bottom:10px">${tags}</div>`;

  if (info.address) html += `<p class="rest-detail-phone">📍 ${escapeHtml(info.address)}</p>`;

  // 운영 시간
  if (info.hours) {
    const hoursLines = Object.entries(info.hours).map(([k, v]) => {
      const label = k === "weekday" ? "평일" : k === "weekend" ? "주말"
                  : k === "breakfast" ? "조식" : k === "lunch" ? "점심"
                  : k === "dinner" ? "저녁" : k;
      return `<span class="rest-menu-time">${label}: ${escapeHtml(v)}</span>`;
    }).join("");
    html += `
      <div class="rest-detail-section">
        <p class="rest-detail-label">운영 시간</p>
        <div class="rest-detail-lines">${hoursLines}</div>
      </div>`;
  }

  if (info.note) html += `<p class="rest-note" style="margin-top:8px">${escapeHtml(info.note)}</p>`;

  // Instagram 게시물
  if (info.type === "instagram") {
    if (!gangyeoData || gangyeoData.needsAuth) {
      html += `<p class="rest-menu-error" style="margin-top:12px">사장님 Instagram 연동 필요</p>`;
    } else if (gangyeoData.error) {
      html += `<p class="rest-menu-error" style="margin-top:12px">메뉴 불러오기 실패</p>`;
    } else if (gangyeoData.posts && gangyeoData.posts.length > 0) {
      const post = gangyeoData.posts[0];
      const caption = post.caption || "";
      html += `
        <div class="rest-detail-section">
          <p class="rest-detail-label">오늘의 메뉴</p>
          <div class="rest-ig-post">
            ${post.imageUrl ? `<img class="rest-ig-img" src="${escapeHtml(post.imageUrl)}" alt="오늘의 메뉴" loading="lazy">` : ""}
            <p class="rest-ig-caption">${escapeHtml(caption)}</p>
            <a class="rest-ig-link" href="${escapeHtml(post.url)}" target="_blank" rel="noopener">Instagram에서 보기 →</a>
          </div>
        </div>`;
    }
  }

  return html;
}

// ─── 식사 탭 클릭 처리 ───
function selectMeal(meal) {
  selectedMeal = meal;
  const { list, snucoData, gangyeoData } = restaurantDataCache;
  // 탭 active 업데이트
  document.querySelectorAll(".rest-meal-tab").forEach(b => {
    b.classList.toggle("active", b.dataset.meal === meal);
  });
  // 메뉴 내용만 교체
  const idx = parseInt(selectedRestId.replace("snuco_", ""), 10);
  const r = snucoData.restaurants[idx];
  const val = r?.[meal] || "";
  const content = val
    ? `<div class="rest-detail-lines">${formatMealLines(val)}</div>`
    : `<p class="rest-detail-empty">정보 없음</p>`;
  document.querySelector(".rest-meal-content").innerHTML = content;
}

// ─── 사이드바 선택 처리 ───
function selectRestaurant(id) {
  selectedRestId = id;
  selectedMeal = getDefaultMeal(); // 식당 바뀌면 시간 기반 기본값으로 리셋
  // 사이드바 active 표시
  document.querySelectorAll(".rest-sidebar-item").forEach(el => {
    el.classList.toggle("active", el.dataset.id === id);
  });
  // 디테일 업데이트
  const { list, snucoData, gangyeoData } = restaurantDataCache;
  document.getElementById("restDetailPanel").innerHTML = buildDetailHtml(id, list, snucoData, gangyeoData);
  // 길찾기 버튼 이벤트 연결
  const navBtn = document.querySelector("#restDetailPanel .rest-nav-btn");
  if (navBtn) {
    navBtn.addEventListener("click", () => showRestaurantRoute({
      lat: parseFloat(navBtn.dataset.lat),
      lng: parseFloat(navBtn.dataset.lng),
      name: navBtn.dataset.name,
    }));
  }
}

// ─── 탭 렌더링 ───
async function renderRestaurantTab() {
  if (restaurantFetching) return;

  // 캐시 있으면 재렌더만
  if (restaurantDataCache) {
    renderRestaurantLayout();
    return;
  }

  restaurantFetching = true;
  restaurantListEl.innerHTML = `<div class="restaurant-loading">불러오는 중...</div>`;

  try {
    const [listRes, snucoRes, gangyeoRes] = await Promise.allSettled([
      fetch(`${SERVER_URL}/api/restaurant/list`).then(r => r.json()),
      fetch(`${SERVER_URL}/api/restaurant/snuco`).then(r => r.json()),
      fetch(`${SERVER_URL}/api/restaurant/gangyeo`).then(r => r.json()),
    ]);

    const list       = listRes.status    === "fulfilled" ? listRes.value    : [];
    const snucoData  = snucoRes.status   === "fulfilled" ? snucoRes.value   : { error: "실패" };
    const gangyeoData = gangyeoRes.status === "fulfilled" ? gangyeoRes.value : { error: "실패" };

    if (list.length === 0) {
      restaurantListEl.innerHTML = `<p class="restaurant-error">식당 정보를 불러오지 못했습니다.</p>`;
      return;
    }

    restaurantDataCache = { list, snucoData, gangyeoData };
    renderRestaurantLayout();
  } catch (err) {
    restaurantListEl.innerHTML = `<p class="restaurant-error">오류: ${escapeHtml(err.message)}</p>`;
  } finally {
    restaurantFetching = false;
  }
}

function renderRestaurantLayout() {
  const { list, snucoData, gangyeoData } = restaurantDataCache;
  const items = buildSidebarItems(list, snucoData);

  // 즐겨찾기가 있으면 우선 선택, 없으면 첫 번째 비헤더
  const validFave = faveRestId && items.find(i => i.id === faveRestId && !i.isHeader);
  if (!selectedRestId || !items.find(i => i.id === selectedRestId)) {
    selectedRestId = validFave ? faveRestId : (items.find(i => !i.isHeader)?.id || items[0]?.id);
  }
  if (!selectedMeal) selectedMeal = getDefaultMeal();

  const sidebarHtml = items.map(item => {
    if (item.isHeader) {
      const dot = item.isOpen === true  ? `<span class="rest-dot open"></span>`
                : item.isOpen === false ? `<span class="rest-dot closed"></span>`
                : "";
      const icon = item.isFaveHeader ? "★ " : "";
      return `<div class="rest-sidebar-group${item.isFaveHeader ? " fave-group" : ""}">${dot}${icon}${escapeHtml(item.label)}</div>`;
    }
    const dot = item.isOpen === true  ? `<span class="rest-dot open"></span>`
              : item.isOpen === false ? `<span class="rest-dot closed"></span>`
              : "";
    const activeClass = item.id === selectedRestId ? " active" : "";
    const isFave = item.id === faveRestId;
    const faveBtn = `<button class="rest-fave-btn${isFave ? " active" : ""}" data-id="${escapeHtml(item.id)}" title="${isFave ? "즐겨찾기 해제" : "즐겨찾기"}">${isFave ? "★" : "☆"}</button>`;
    return `<div class="rest-sidebar-item${activeClass}" data-id="${escapeHtml(item.id)}">${dot}<span class="rest-sidebar-label">${escapeHtml(item.label)}</span>${faveBtn}</div>`;
  }).join("");

  restaurantListEl.innerHTML = `
    <div class="rest-layout">
      <div class="rest-sidebar" id="restSidebar">${sidebarHtml}</div>
      <div class="rest-detail" id="restDetailPanel">${buildDetailHtml(selectedRestId, list, snucoData, gangyeoData)}</div>
    </div>`;

  // 사이드바 클릭 (즐겨찾기 버튼 / 식당 선택 분리)
  document.getElementById("restSidebar").addEventListener("click", e => {
    const faveBtn = e.target.closest(".rest-fave-btn");
    if (faveBtn) { toggleFave(faveBtn.dataset.id); return; }
    const item = e.target.closest(".rest-sidebar-item");
    if (item) selectRestaurant(item.dataset.id);
  });

  // 식사 탭 클릭 (이벤트 위임)
  document.getElementById("restDetailPanel").addEventListener("click", e => {
    const tab = e.target.closest(".rest-meal-tab");
    if (tab) selectMeal(tab.dataset.meal);
  });
}

// ──────────────────────────────────────────
// 다크 모드
// ──────────────────────────────────────────

const darkModeBtn = document.getElementById("darkModeBtn");

function applyDarkMode(dark) {
  document.body.classList.toggle("dark", dark);
  darkModeBtn.textContent = dark ? "☀️ 라이트 모드" : "🌙 다크 모드";
}

const savedDark = localStorage.getItem("darkMode") === "true"
  || (localStorage.getItem("darkMode") === null && window.matchMedia("(prefers-color-scheme: dark)").matches);
applyDarkMode(savedDark);

darkModeBtn.addEventListener("click", () => {
  const isDark = !document.body.classList.contains("dark");
  applyDarkMode(isDark);
  localStorage.setItem("darkMode", isDark);
});

// ──────────────────────────────────────────
// 초기화
// ──────────────────────────────────────────

requestNotificationPermission();
// 권한이 이미 있으면 서버 재시작 후 구독 복구
if (Notification.permission === "granted") subscribePush();
renderTasks();
startBombMotionTimer();
renderCompleted();
checkDeadlines();
setInterval(checkDeadlines, 60000);

if (icalUrl) {
  setConnectedUI();
  if (canvasToken && apiTokenInput) apiTokenInput.value = canvasToken;
  syncIcal();
} else {
  openSettings();
}

setInterval(() => { if (icalUrl) syncIcal(); }, 10 * 60 * 1000);
setInterval(() => { fetch(`${SERVER_URL}/health`).catch(() => {}); }, 14 * 60 * 1000);
