const SERVER_URL = "https://snu-assignment-server.onrender.com";
const STORAGE_KEY = "snu_assignment_app_tasks";
const ICAL_URL_KEY = "snu_etl_ical_url";
const CANVAS_TOKEN_KEY = "snu_etl_canvas_token";

// DOM
const taskList = document.getElementById("taskList");
const emptyMessage = document.getElementById("emptyMessage");
const activeCount = document.getElementById("activeCount");

// eTL DOM
const etlToggle = document.getElementById("etlToggle");
const etlBody = document.getElementById("etlBody");
const etlToggleIcon = document.getElementById("etlToggleIcon");
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

let tasks = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
let icalUrl = localStorage.getItem(ICAL_URL_KEY) || null;
let canvasToken = localStorage.getItem(CANVAS_TOKEN_KEY) || null;

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
  const h = String(date.getHours()).padStart(2, "0");
  const mi = String(date.getMinutes()).padStart(2, "0");
  return `${y}.${mo}.${d} ${h}:${mi}`;
}

function getBadgeInfo(dateString) {
  const dueDate = parseDateValue(dateString);
  if (!dueDate) return { text: "날짜 확인", className: "due-blue" };
  const diffMs = dueDate - new Date();
  const diffHours = diffMs / (1000 * 60 * 60);
  const diffDays = diffMs / (1000 * 60 * 60 * 24);
  if (diffMs < 0) return { text: "마감 지남", className: "due-black" };
  if (diffHours <= 24) return { text: "24시간 이하", className: "due-red" };
  if (diffDays <= 3) return { text: "1~3일 남음", className: "due-green" };
  return { text: "3일 초과", className: "due-blue" };
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ──────────────────────────────────────────
// 저장 / 렌더링
// ──────────────────────────────────────────

function saveTasks() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
}

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
  emptyMessage.classList.toggle("hidden", tasks.length > 0);

  activeCount.textContent = tasks.length;

  tasks.forEach((task) => {
    const badge = getBadgeInfo(task.dueDate);
    const li = document.createElement("li");
    li.className = "task-item";

    const courseLabel = task.courseName
      ? `<span class="course-label">${escapeHtml(task.courseName)}</span>`
      : "";
    const sourceTag = task.source === "etl"
      ? `<span class="source-tag etl-tag">eTL</span>`
      : "";
    const titleLink = task.url
      ? `<a class="task-title" href="${escapeHtml(task.url)}" target="_blank">${escapeHtml(task.title)}</a>`
      : `<p class="task-title">${escapeHtml(task.title)}</p>`;

    li.innerHTML = `
      <div class="task-main">
        <div class="task-title-row">${sourceTag}${titleLink}</div>
        ${courseLabel}
        <div class="task-meta">
          <span class="due-date-text">마감일: ${formatDateTime(task.dueDate, task.dateOnly)}</span>
          <span class="due-badge ${badge.className}">${badge.text}</span>
        </div>
      </div>
      <button class="complete-btn" data-id="${task.id}">완료</button>
    `;

    li.querySelector(".complete-btn").addEventListener("click", () => {
      tasks = tasks.filter((item) => item.id !== task.id);
      saveTasks();
      renderTasks();
    });

    taskList.appendChild(li);
  });
}


// ──────────────────────────────────────────
// eTL 섹션 토글
// ──────────────────────────────────────────

etlToggle.addEventListener("click", () => {
  const isOpen = !etlBody.classList.contains("collapsed");
  etlBody.classList.toggle("collapsed", isOpen);
  etlToggleIcon.textContent = isOpen ? "▶" : "▼";
});

// ──────────────────────────────────────────
// iCal 연동
// ──────────────────────────────────────────

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
  if (!url) {
    showEtlError("URL을 입력해주세요.");
    return;
  }
  if (!url.startsWith("webcal://") && !url.startsWith("https://")) {
    showEtlError("webcal:// 또는 https:// 로 시작하는 URL을 입력해주세요.");
    return;
  }
  if (!url.includes("etl.snu.ac.kr") && !url.includes("myetl.snu.ac.kr")) {
    showEtlError("eTL 캘린더 URL이 맞는지 확인해주세요.");
    return;
  }

  icalSaveBtn.disabled = true;
  icalSaveBtn.textContent = "가져오는 중...";

  icalUrl = url;
  localStorage.setItem(ICAL_URL_KEY, url);

  const ok = await syncIcal();
  if (ok) {
    setConnectedUI();
    document.querySelector(".etl-section").classList.add("hidden");
  }

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
  document.querySelector(".etl-section").classList.remove("hidden");
  etlBody.classList.remove("collapsed");
  etlToggleIcon.textContent = "▼";
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

  if (retrying) {
    etlSyncStatus.textContent = "서버 준비 중... 재시도 중";
  }

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

    // 기존 eTL 과제 제거 후 새 데이터로 교체
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
    checkDeadlines();

    const now = new Date();
    const t = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
    etlSyncStatus.textContent = `마지막 동기화: ${t} (${data.length}개)`;
    return true;
  } catch {
    if (!retrying) {
      // cold start 대응: 10초 후 1회 자동 재시도
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
// 알림
// ──────────────────────────────────────────

async function requestNotificationPermission() {
  if (!("Notification" in window)) return;
  await Notification.requestPermission();
}


function sendDeadlineNotification(title, message) {
  if (Notification.permission !== "granted") return;
  navigator.serviceWorker.ready.then((reg) => {
    reg.showNotification(`⚠️ ${title}`, { body: message, icon: "./icon-192.png" });
  });
}

function checkDeadlines() {
  const current = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
  current.forEach((task) => {
    const dueDate = parseDateValue(task.dueDate);
    if (!dueDate) return;
    const diffHours = (dueDate - new Date()) / (1000 * 60 * 60);
    if (diffHours < 0) return;

    [
      { max: 24, min: 5,  key: `notified_24h_${task.id}`, msg: "24시간 이내에 마감!" },
      { max: 5,  min: 1,  key: `notified_5h_${task.id}`,  msg: "5시간 이내에 마감!" },
      { max: 1,  min: -1, key: `notified_1h_${task.id}`,  msg: "1시간 이내에 마감!" },
    ].forEach(({ max, min, key, msg }) => {
      if (diffHours <= max && diffHours > min && !localStorage.getItem(key)) {
        sendDeadlineNotification(task.title, msg);
        localStorage.setItem(key, "true");
      }
    });
  });
}


// ──────────────────────────────────────────
// 초기화
// ──────────────────────────────────────────

requestNotificationPermission();
renderTasks();
checkDeadlines();
setInterval(checkDeadlines, 60000);

// iCal URL이 저장돼 있으면 연동 상태 복원 + 자동 동기화
if (icalUrl) {
  document.querySelector(".etl-section").classList.add("hidden");
  if (canvasToken && apiTokenInput) apiTokenInput.value = canvasToken;
  syncIcal();
}

// 10분마다 자동 동기화
setInterval(() => {
  if (icalUrl) syncIcal();
}, 10 * 60 * 1000);

// 14분마다 서버 ping (Render free tier cold start 방지)
setInterval(() => {
  fetch(`${SERVER_URL}/health`).catch(() => {});
}, 14 * 60 * 1000);
