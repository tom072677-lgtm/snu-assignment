// 청년정책 정규화 순수함수 단위 테스트. 실행: `node --test server/opportunities.test.js`
// (설계 §9 — 서버 정규화 테스트. region/마감 파싱은 엣지가 많아 회귀 방지에 가치가 큼.)
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { regionFromZipCd, deadlineFromAplyYmd } = require("./opportunities");

test("regionFromZipCd: 한 시·도의 여러 구 → 그 시·도", () => {
  assert.equal(regionFromZipCd("11110,11140,11170"), "서울");
});

test("regionFromZipCd: 여러 시·도에 걸치면 null(전국)", () => {
  assert.equal(regionFromZipCd("11110,26110"), null); // 서울+부산
});

test("regionFromZipCd: 빈값/공백 → null", () => {
  assert.equal(regionFromZipCd(""), null);
  assert.equal(regionFromZipCd(null), null);
  assert.equal(regionFromZipCd("   "), null);
});

test("regionFromZipCd: 강원/전북 구·신 특별자치도 코드 둘 다 매핑", () => {
  assert.equal(regionFromZipCd("42110"), "강원"); // 구코드
  assert.equal(regionFromZipCd("51110"), "강원"); // 특별자치도
  assert.equal(regionFromZipCd("45110"), "전북");
  assert.equal(regionFromZipCd("52110"), "전북");
});

test("regionFromZipCd: 알 수 없는 코드는 무시", () => {
  assert.equal(regionFromZipCd("99999,11110"), "서울"); // 99 무시 → 서울만
  assert.equal(regionFromZipCd("99999"), null);
});

test("deadlineFromAplyYmd: 'YYYYMMDD ~ YYYYMMDD' → 종료일", () => {
  assert.equal(deadlineFromAplyYmd("20260615 ~ 20260630"), "2026-06-30");
});

test("deadlineFromAplyYmd: 단일 8자리 → 그 날짜", () => {
  assert.equal(deadlineFromAplyYmd("20260630"), "2026-06-30");
});

test("deadlineFromAplyYmd: 빈값/상시/숫자없음 → null", () => {
  assert.equal(deadlineFromAplyYmd(""), null);
  assert.equal(deadlineFromAplyYmd(null), null);
  assert.equal(deadlineFromAplyYmd("상시모집"), null);
});
