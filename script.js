const taskForm = document.getElementById("taskForm");
const taskInput = document.getElementById("taskInput");
const dueDateInput = document.getElementById("dueDateInput");
const taskList = document.getElementById("taskList");
const emptyMessage = document.getElementById("emptyMessage");
const totalCount = document.getElementById("totalCount");
const activeCount = document.getElementById("activeCount");
const completedCount = document.getElementById("completedCount");
const sortBtn = document.getElementById("sortBtn");
const testAlertBtn = document.getElementById("testAlertBtn");
testAlertBtn.addEventListener("click", sendTestNotification);

const STORAGE_KEY = "snu_assignment_app_tasks";
const COMPLETED_COUNT_KEY = "snu_assignment_app_completed_count";

let tasks = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
let completedCounter = Number(localStorage.getItem(COMPLETED_COUNT_KEY)) || 0;

function saveTasks() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
}

function saveCompletedCounter() {
  localStorage.setItem(COMPLETED_COUNT_KEY, String(completedCounter));
}

function parseDateValue(value) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date;
}

function formatDateTime(value) {
  const date = parseDateValue(value);

  if (!date) {
    return value;
  }

  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  const hour = String(date.getHours()).padStart(2, "0");
  const minute = String(date.getMinutes()).padStart(2, "0");

  return `${year}.${month}.${day} ${hour}:${minute}`;
}

function getBadgeInfo(dateString) {
  const dueDate = parseDateValue(dateString);

  if (!dueDate) {
    return {
      text: "날짜 확인",
      className: "due-blue"
    };
  }

  const now = new Date();
  const diffMs = dueDate - now;
  const diffHours = diffMs / (1000 * 60 * 60);
  const diffDays = diffMs / (1000 * 60 * 60 * 24);

  if (diffMs < 0) {
    return {
      text: "마감 지남",
      className: "due-black"
    };
  }

  if (diffHours <= 24) {
    return {
      text: "24시간 이하",
      className: "due-red"
    };
  }

  if (diffDays <= 3) {
    return {
      text: "1~3일 남음",
      className: "due-green"
    };
  }

  return {
    text: "3일 초과",
    className: "due-blue"
  };
}

function updateCounts() {
  totalCount.textContent = tasks.length + completedCounter;
  activeCount.textContent = tasks.length;
  completedCount.textContent = completedCounter;
}

function sortTasks() {
  tasks.sort((a, b) => {
    const dateA = parseDateValue(a.dueDate);
    const dateB = parseDateValue(b.dueDate);

    if (!dateA && !dateB) return 0;
    if (!dateA) return 1;
    if (!dateB) return -1;

    return dateA - dateB;
  });
}

function renderTasks() {
  sortTasks();
  taskList.innerHTML = "";

  if (tasks.length === 0) {
    emptyMessage.classList.remove("hidden");
  } else {
    emptyMessage.classList.add("hidden");
  }

  tasks.forEach((task) => {
    const badge = getBadgeInfo(task.dueDate);

    const li = document.createElement("li");
    li.className = "task-item";

    li.innerHTML = `
      <div class="task-main">
        <p class="task-title">${task.title}</p>
        <div class="task-meta">
          <span class="due-date-text">마감일: ${formatDateTime(task.dueDate)}</span>
          <span class="due-badge ${badge.className}">${badge.text}</span>
        </div>
      </div>
      <button class="complete-btn" data-id="${task.id}">완료</button>
    `;

    const completeBtn = li.querySelector(".complete-btn");
    completeBtn.addEventListener("click", () => {
      tasks = tasks.filter((item) => item.id !== task.id);
      completedCounter += 1;

      saveTasks();
      saveCompletedCounter();
      renderTasks();
    });

    taskList.appendChild(li);
  });

  updateCounts();
}

taskForm.addEventListener("submit", (event) => {
  event.preventDefault();

  const title = taskInput.value.trim();
  const dueDate = dueDateInput.value;

  if (!title || !dueDate) {
    alert("과제 이름과 마감 날짜/시간을 모두 입력해줘.");
    return;
  }

  const newTask = {
    id: Date.now(),
    title,
    dueDate
  };

  tasks.push(newTask);
  saveTasks();
  renderTasks();

  taskForm.reset();
  taskInput.focus();
});

sortBtn.addEventListener("click", () => {
  sortTasks();
  renderTasks();
});

renderTasks();

// 알림 권한 요청
async function requestNotificationPermission() {
  if (!("Notification" in window)) {
    alert("이 브라우저는 알림을 지원하지 않아요.");
    return;
  }

  const permission = await Notification.requestPermission();

  if (permission === "granted") {
    console.log("알림 허용됨!");
  } else {
    console.log("알림 거부됨");
  }
}

// 테스트 알림 보내기
function sendTestNotification() {
  if (Notification.permission === "granted") {
    navigator.serviceWorker.ready.then((registration) => {
      registration.showNotification("SNU 과제 알림 테스트", {
        body: "알림이 정상적으로 작동하고 있어요!",
        icon: "./icon-192.png"
      });
    });
  }
}

// 앱 시작할 때 알림 권한 요청
requestNotificationPermission();

function checkDeadlines() {
  // localStorage에서 과제 목록 꺼내오기
  const tasks = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
  
  tasks.forEach((task) => {
    const dueDate = parseDateValue(task.dueDate);
    if (!dueDate) return;
    
    const now = new Date();
    const diffHours = (dueDate - now) / (1000 * 60 * 60);
    
    // 이미 지난 과제는 무시
    if (diffHours < 0) return;
    
    // 24시간 이내
    if (diffHours <= 24) {
      const key = `notified_24h_${task.id}`;
      if (!localStorage.getItem(key)) {
        sendDeadlineNotification(task.title, "24시간 이내에 마감!");
        localStorage.setItem(key, "true");
      }
    }
    
    // 5시간 이내
    if (diffHours <= 5) {
      const key = `notified_5h_${task.id}`;
      if (!localStorage.getItem(key)) {
        sendDeadlineNotification(task.title, "5시간 이내에 마감!");
        localStorage.setItem(key, "true");
      }
    }
    
    // 1시간 이내
    if (diffHours <= 1) {
      const key = `notified_1h_${task.id}`;
      if (!localStorage.getItem(key)) {
        sendDeadlineNotification(task.title, "1시간 이내에 마감!");
        localStorage.setItem(key, "true");
      }
    }
  });
}

function sendDeadlineNotification(title, message) {
  if (Notification.permission === "granted") {
    navigator.serviceWorker.ready.then((registration) => {
      registration.showNotification("⚠️ " + title, {
        body: message,
        icon: "./icon-192.png"
      });
    });
  }
}

// 1분마다 마감 확인
setInterval(checkDeadlines, 60000);

// 앱 열자마자 한 번 바로 확인
checkDeadlines();