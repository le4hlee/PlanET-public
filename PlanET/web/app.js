/**
 * Mirrors Swift TaskItem (ContentView.swift):
 * id, title, deadline, isCompleted, completedDate, recurrenceRule,
 * hasGeneratedNext, category, isNotificationEnabled
 *
 * In memory we keep deadline/completedDate as ISO strings (JSON-safe).
 */

const STORAGE_KEY = "planet_tasks";

const TIME_KEYWORDS = {
  morning: 8,
  noon: 12,
  afternoon: 14,
  dinner: 18,
  tonight: 23,
};

// translate time keywords to hours
const TIME_KEYWORD_ORDER = [
  "morning",
  "noon",
  "afternoon",
  "dinner",
  "tonight",
];

function parseTimeKeyword(text, baseDate = new Date()) {
  let clean = text;
  for (const keyword of TIME_KEYWORD_ORDER) {
    const hour = TIME_KEYWORDS[keyword];
    const re = new RegExp(`\\b${keyword}\\b`, "i");
    if (!re.test(clean)) continue;
    clean = clean.replace(re, "").replace(/\s+/g, " ").trim();
    const d = new Date(baseDate);
    d.setHours(hour, keyword === "tonight" ? 59 : 0, 0, 0);
    return { deadline: d, title: clean };
  }
  return null;
}

function startOfLocalDay(d) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

/** Port of TaskManager.finalCleanup — strips filler words after parsing dates/times */
function finalCleanup(text) {
  let clean = text.replace(/\s+/g, " ").replace(/ and /gi, " ");
  let previous = "";
  while (clean !== previous) {
    previous = clean;
    clean = clean.trim();
    const lower = clean.toLowerCase();
    if (lower.endsWith(" by")) clean = clean.slice(0, -3);
    else if (lower.endsWith(" in")) clean = clean.slice(0, -3);
    else if (lower.endsWith(" at")) clean = clean.slice(0, -3);
    else if (lower.endsWith(" on")) clean = clean.slice(0, -3);
    else if (lower.endsWith(" for")) clean = clean.slice(0, -4);
    else if (lower.startsWith("by ")) clean = clean.slice(3);
    else if (lower.startsWith("in ")) clean = clean.slice(3);
    else if (lower.startsWith("at ")) clean = clean.slice(3);
    else if (lower.startsWith("on ")) clean = clean.slice(3);
    else if (lower.startsWith("for ")) clean = clean.slice(4);
  }
  return clean.trim();
}

/**
 * today | tomorrow | tmr | tmrw → calendar day for time keywords & defaults.
 * Returns start-of-day as base for morning/afternoon, and remaining title text.
 */
function parseDayRelative(text) {
  const re = /\b(today|tomorrow|tmr|tmrw)\b/i;
  const m = text.match(re);
  if (!m) return null;
  const word = m[1].toLowerCase();
  const rest = text.replace(re, "").replace(/\s+/g, " ").trim();
  const now = new Date();
  let baseStart;
  if (word === "today") {
    baseStart = startOfLocalDay(now);
  } else {
    const t = startOfLocalDay(now);
    t.setDate(t.getDate() + 1);
    baseStart = t;
  }
  return { baseStart, rest };
}

function endOfLocalDay(dayStart) {
  const d = new Date(dayStart);
  d.setHours(23, 59, 59, 999);
  return d;
}

// turn single line input into title and deadline
function parseTaskInput(raw) {
  const trimmed = raw.trim() || "Untitled Task";

  const day = parseDayRelative(trimmed);
  const working = day ? day.rest : trimmed;
  const baseDate = day ? day.baseStart : new Date();

  const fromTimeWord = parseTimeKeyword(working, baseDate);
  if (fromTimeWord) {
    const title = finalCleanup(fromTimeWord.title) || "Untitled Task";
    return { title, deadline: fromTimeWord.deadline };
  }

  if (day) {
    const title = finalCleanup(day.rest) || "Untitled Task";
    return { title, deadline: endOfLocalDay(day.baseStart) };
  }

  return {
    title: finalCleanup(trimmed),
    deadline: new Date(Date.now() + 3600_000),
  };
}

/**
 * @returns {object} New task with Swift-matching field names and defaults.
 */

function createTask({
  title = "Untitled Task",
  deadline = new Date(Date.now() + 3600_000),
  isCompleted = false,
  completedDate = null,
  recurrenceRule = null,
  hasGeneratedNext = false,
  category = null,
  isNotificationEnabled = true,
} = {}) {
  const deadlineIso =
    typeof deadline === "string" ? deadline : deadline.toISOString();
  return {
    id: crypto.randomUUID(),
    title,
    deadline: deadlineIso,
    isCompleted,
    completedDate:
      completedDate == null
        ? null
        : typeof completedDate === "string"
          ? completedDate
          : completedDate.toISOString(),
    recurrenceRule,
    hasGeneratedNext,
    category,
    isNotificationEnabled,
  };
}

function parseStoredTasks(json) {
  const raw = JSON.parse(json);
  if (!Array.isArray(raw)) return [];
  return raw.map((row) => ({
    id: row.id,
    title: row.title ?? "Untitled Task",
    deadline: row.deadline,
    isCompleted: Boolean(row.isCompleted),
    completedDate: row.completedDate ?? null,
    recurrenceRule: row.recurrenceRule ?? null,
    hasGeneratedNext: Boolean(row.hasGeneratedNext),
    category: row.category ?? null,
    isNotificationEnabled:
      row.isNotificationEnabled !== undefined
        ? row.isNotificationEnabled
        : true,
  }));
}

/** @deprecated name kept for clarity — use parseTaskInput + createTask in callers */
function addTask(task) {
  tasks.push(task);
  saveTasks(tasks);
  renderTaskList(tasks);
}

function loadTasks() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    return parseStoredTasks(raw);
  } catch {
    return [];
  }
}

function saveTasks(tasks) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
}

function renderTaskList(tasks) {
  const ul = document.getElementById("task-list");
  if (!ul) return;
  ul.innerHTML = "";
  for (const task of tasks) {
    const li = document.createElement("li");
    const when = new Date(task.deadline);
    li.textContent = `${task.title} — ${when.toLocaleString()}`;
    ul.appendChild(li);
  }
}

function getTasksForBucket(tasks, bucket) {
  console.log(`Getting tasks for bucket: ${bucket.name}`);
  console.log(`Number of tasks: ${tasks.length}`);
  console.log(`Tasks: ${tasks.map(task => task.title).join(", ")}`);



  currenttime = Date.now();
  if (currenttime - tasks.deadline > bucket.timeLimitInSeconds) {
    console.log("No tasks found");
    return [];
  } else if (currenttime - tasks.deadline <= bucket.timeLimitInSeconds) {
    return [tasks];
  }

  const filteredTasks = tasks.filter(task => task.deadline <= bucket.timeLimitInSeconds);
  console.log(`Filtered tasks: ${filteredTasks.map(task => task.title).join(", ")}`);
  console.log(`Number of filtered tasks: ${filteredTasks.length}`);
  return filteredTasks;
}

let tasks = loadTasks();

document.getElementById("task-form")?.addEventListener("submit", (e) => {
  e.preventDefault();
  const input = document.getElementById("task-input");
  const text = (input?.value ?? "").trim() || "Untitled Task";
  const { title, deadline } = parseTaskInput(text);
  const task = createTask({ title, deadline });
  tasks.push(task);
  saveTasks(tasks);
  renderTaskList(tasks);
  if (input) input.value = "";
});

renderTaskList(tasks);
