// 동아리 seed 데이터 검증 스크립트
// 사용: node scripts/validate_clubs.js
// 검사: JSON 유효성, 필수 필드, id 유일성, tier/category enum, 단과대 코드 존재.
const fs = require("fs");
const path = require("path");

const FILE = path.join(__dirname, "..", "assets", "data", "clubs.json");

const TIERS = new Set(["central", "college", "dorm"]);
const CATEGORIES = new Set([
  "학술", "봉사·종교", "운동", "음악·공연", "취미", "기타",
]);
// snu_departments.dart 의 단과대 코드와 일치해야 함.
const COLLEGES = new Set([
  "liberal_arts", "social_sciences", "natural_sciences", "nursing",
  "engineering", "agriculture", "business", "education", "fine_arts",
  "music", "law", "veterinary", "medicine", "dentistry", "pharmacy",
  "home_economics", "humanities",
]);

const errors = [];
const warnings = [];

let raw;
try {
  raw = fs.readFileSync(FILE, "utf8");
} catch (e) {
  console.error(`[FAIL] cannot read ${FILE}: ${e.message}`);
  process.exit(1);
}

let data;
try {
  data = JSON.parse(raw);
} catch (e) {
  console.error(`[FAIL] invalid JSON: ${e.message}`);
  process.exit(1);
}

if (!Array.isArray(data)) {
  console.error("[FAIL] root must be a JSON array");
  process.exit(1);
}

const ids = new Set();
data.forEach((c, i) => {
  const where = `#${i} (${c && c.name ? c.name : "?"})`;
  if (!c || typeof c !== "object") { errors.push(`${where}: not an object`); return; }
  for (const f of ["id", "name", "tier", "category"]) {
    if (!c[f] || typeof c[f] !== "string") errors.push(`${where}: missing/invalid '${f}'`);
  }
  if (c.id) {
    if (ids.has(c.id)) errors.push(`${where}: duplicate id '${c.id}'`);
    ids.add(c.id);
  }
  if (c.tier && !TIERS.has(c.tier)) errors.push(`${where}: bad tier '${c.tier}'`);
  if (c.category && !CATEGORIES.has(c.category)) errors.push(`${where}: bad category '${c.category}'`);
  if (!Array.isArray(c.colleges)) {
    errors.push(`${where}: 'colleges' must be an array`);
  } else {
    c.colleges.forEach((code) => {
      if (!COLLEGES.has(code)) errors.push(`${where}: unknown college code '${code}'`);
    });
    if (c.tier === "college" && c.colleges.length === 0)
      warnings.push(`${where}: tier=college but colleges is empty`);
    if (c.tier !== "college" && c.colleges.length > 0)
      warnings.push(`${where}: tier=${c.tier} but has colleges`);
  }
  if (c.registration != null && c.registration !== "정" && c.registration !== "가")
    errors.push(`${where}: bad registration '${c.registration}'`);
});

const MIN = 240;
if (data.length < MIN) warnings.push(`only ${data.length} clubs (expected ~261, min ${MIN})`);

console.log(`clubs: ${data.length}, unique ids: ${ids.size}`);
const byTier = data.reduce((m, c) => ((m[c.tier] = (m[c.tier] || 0) + 1), m), {});
console.log("by tier:", JSON.stringify(byTier));
const byCat = data.reduce((m, c) => ((m[c.category] = (m[c.category] || 0) + 1), m), {});
console.log("by category:", JSON.stringify(byCat));

warnings.forEach((w) => console.warn(`[WARN] ${w}`));
if (errors.length) {
  errors.forEach((e) => console.error(`[ERROR] ${e}`));
  console.error(`\n[FAIL] ${errors.length} error(s).`);
  process.exit(1);
}
console.log(`\n[OK] validation passed (${warnings.length} warning(s)).`);
