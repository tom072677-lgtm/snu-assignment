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

document.querySelectorAll(".tab-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab-btn").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    const tab = btn.dataset.tab;
    alertsTab.classList.toggle("hidden", tab !== "alerts");
    calendarTab.classList.toggle("hidden", tab !== "calendar");
    restaurantTab.classList.toggle("hidden", tab !== "restaurant");
    if (tab === "calendar") renderCalendar();
    if (tab === "restaurant") renderRestaurantTab();
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
    }));

    const userEventTasks = calendarEvents
      .filter((e) => e.time)
      .map((e) => ({
        etlId: e.id,
        dueDate: e.time,
        title: e.title,
        courseName: null,
        targets: [24, 5],
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

  // ETL 과제: 24h / 5h / 1h (±6분 창에 들어올 때만 발송)
  const WINDOW_H = 1 / 60;
  const etlTasks = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
  etlTasks.forEach((task) => {
    const dueDate = parseDateValue(task.dueDate);
    if (!dueDate) return;
    const diffHours = (dueDate - new Date()) / (1000 * 60 * 60);
    if (diffHours < 0) return;
    [
      { h: 24, key: `notified_24h_${task.id}` },
      { h: 5,  key: `notified_5h_${task.id}` },
      { h: 1,  key: `notified_1h_${task.id}` },
    ].forEach(({ h, key }) => {
      if (diffHours <= h + WINDOW_H && diffHours > h - WINDOW_H && !localStorage.getItem(key)) {
        navigator.serviceWorker.ready.then((reg) => {
          const name = cleanCourseName(task.courseName) || task.title;
          reg.showNotification(`📚 마감 ${h}시간 전`, {
            body: `${name} 과제 마감이 ${h}시간 후입니다.`,
            icon: "./icon-192.png",
          });
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
    [
      { h: 24, key: `notified_24h_${ev.id}` },
      { h: 5,  key: `notified_5h_${ev.id}` },
    ].forEach(({ h, key }) => {
      if (diffHours <= h + WINDOW_H && diffHours > h - WINDOW_H && !localStorage.getItem(key)) {
        navigator.serviceWorker.ready.then((reg) => {
          reg.showNotification(`📅 일정 ${h}시간 전`, {
            body: `"${ev.title}" 일정이 ${h}시간 후입니다.`,
            icon: "./icon-192.png",
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
let restaurantDataCache = null;   // { list, snucoData, gangyeoData }
let restaurantFetching = false;
let selectedRestId = null;        // 현재 선택된 식당 id
let selectedMeal = null;          // "breakfast" | "lunch" | "dinner"

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
  const items = [];

  for (const info of list) {
    if (info.type === "snuco") {
      // 학생식당 그룹 헤더
      items.push({ id: "snuco_header", label: "SNU 학생식당", isHeader: true, isOpen: info.isOpen });
      // 세부 식당 — 가나다 정렬, 숫자 시작은 뒤로
      if (snucoData && snucoData.restaurants) {
        const sorted = snucoData.restaurants
          .map((r, i) => ({ r, i, name: r.name.replace(/\s*\([\d-]+\)\s*$/, "").trim() }))
          .sort((a, b) => koreanSort(a.name, b.name));
        sorted.forEach(({ r, i, name }) => {
          items.push({ id: `snuco_${i}`, label: name, isHeader: false, isOpen: null });
        });
      }
    } else {
      items.push({ id: info.id, label: info.name, isHeader: false, isOpen: info.isOpen });
    }
  }
  return items;
}

// ─── 식사 메뉴 텍스트 → HTML ───
function formatMealLines(val) {
  const lines = val.split(" ").join("\n").split("\n").map(l => l.trim()).filter(Boolean);
  return lines.map(line => {
    if (/:\s*[\d,]+원/.test(line))         return `<span class="rest-menu-row">${escapeHtml(line)}</span>`;
    if (/운영시간|예약|문의|※/.test(line)) return `<span class="rest-menu-time">${escapeHtml(line)}</span>`;
    return `<span class="rest-menu-item">${escapeHtml(line)}</span>`;
  }).join("");
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

    return `
      <div class="rest-detail-title">${escapeHtml(name)}</div>
      ${phone ? `<p class="rest-detail-phone">📞 ${escapeHtml(phone)}</p>` : ""}
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

  let html = `<div class="rest-detail-title">${escapeHtml(info.name)}</div>`;

  const openBadge = info.isOpen === true
    ? `<span class="rest-open">영업중</span>`
    : info.isOpen === false
    ? `<span class="rest-closed">영업종료</span>`
    : "";
  if (openBadge) html += `<div style="margin-bottom:10px">${openBadge}</div>`;

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

  // 기본 선택: 첫 번째 비헤더 항목
  if (!selectedRestId || !items.find(i => i.id === selectedRestId)) {
    selectedRestId = items.find(i => !i.isHeader)?.id || items[0]?.id;
  }
  if (!selectedMeal) selectedMeal = getDefaultMeal();

  const sidebarHtml = items.map(item => {
    if (item.isHeader) {
      const dot = item.isOpen === true  ? `<span class="rest-dot open"></span>`
                : item.isOpen === false ? `<span class="rest-dot closed"></span>`
                : "";
      return `<div class="rest-sidebar-group">${dot}${escapeHtml(item.label)}</div>`;
    }
    const dot = item.isOpen === true  ? `<span class="rest-dot open"></span>`
              : item.isOpen === false ? `<span class="rest-dot closed"></span>`
              : "";
    const activeClass = item.id === selectedRestId ? " active" : "";
    return `<div class="rest-sidebar-item${activeClass}" data-id="${escapeHtml(item.id)}">${dot}<span>${escapeHtml(item.label)}</span></div>`;
  }).join("");

  restaurantListEl.innerHTML = `
    <div class="rest-layout">
      <div class="rest-sidebar" id="restSidebar">${sidebarHtml}</div>
      <div class="rest-detail" id="restDetailPanel">${buildDetailHtml(selectedRestId, list, snucoData, gangyeoData)}</div>
    </div>`;

  // 사이드바 클릭
  document.getElementById("restSidebar").addEventListener("click", e => {
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
