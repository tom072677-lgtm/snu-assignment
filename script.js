const taskForm = document.getElementById("taskForm");
const taskInput = document.getElementById("taskInput");
const dueDateInput = document.getElementById("dueDateInput");
const taskList = document.getElementById("taskList");
const emptyMessage = document.getElementById("emptyMessage");
const totalCount = document.getElementById("totalCount");
const activeCount = document.getElementById("activeCount");
const completedCount = document.getElementById("completedCount");
const sortBtn = document.getElementById("sortBtn");

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