const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { createMapRoutes } = require("./mapRoutes");

const POINT = { olat: 37.4607, olng: 126.9526, dlat: 37.4631, dlng: 126.9512 };
const OSRM = { code: "Ok", routes: [{ duration: 277.4, distance: 346.7,
  geometry: { type: "LineString", coordinates: [[126.952606, 37.460709], [126.951025, 37.46297]] } }] };
const TMAP = { features: [
  { geometry: { type: "Point" }, properties: { totalTime: 280, totalDistance: 350, description: "출발" } },
  { geometry: { type: "LineString", coordinates: [[126.9526, 37.4607], [126.9512, 37.4631]] } },
] };
const response = (body, status = 200) => ({ status, ok: status >= 200 && status < 300, json: async () => structuredClone(body) });

function harness(fetcher = async () => response(OSRM), key = "") {
  let clock = 0;
  const calls = [];
  const logs = [];
  const routes = createMapRoutes({
    fetchImpl: async (url, options) => {
      calls.push({ url, options, at: clock });
      return fetcher(url, options);
    },
    tmapKey: () => key,
    now: () => clock,
    sleep: async ms => { clock += ms; },
    logger: message => logs.push(message),
  });
  return { ...routes, calls, logs, advance: ms => { clock += ms; } };
}

async function invoke(h, mode, input = POINT) {
  let status = 200;
  let body;
  const res = { status(value) { status = value; return this; }, json(value) { body = value; } };
  await h.handler(mode)({ body: input }, res);
  return { status, body };
}

test("유한 범위 좌표와 다른 출발·도착지만 허용한다", async () => {
  const h = harness();
  for (const input of [null, {}, { ...POINT, olat: NaN }, { ...POINT, olng: Infinity },
    { ...POINT, dlat: 91 }, { ...POINT, dlng: -181 }, { ...POINT, olat: "37.46" }]) {
    const result = await invoke(h, "walk", input);
    assert.equal(result.status, 400);
    assert.equal(result.body.code, "INVALID_COORDINATES");
  }
  const same = await invoke(h, "walk", { ...POINT, dlat: POINT.olat, dlng: POINT.olng });
  assert.equal(same.status, 400);
  assert.equal(same.body.code, "SAME_LOCATION");
  assert.equal(h.calls.length, 0);
});

test("TMAP 성공 경로를 우선 사용하고 기존 좌표·안내 형식을 보존한다", async () => {
  const h = harness(async () => response(TMAP), "test-only-secret");
  for (const mode of ["walk", "car"]) {
    const route = await h.getRoute(mode, POINT);
    assert.equal(route.source, "TMAP");
    assert.equal(route.duration, 280);
    assert.deepEqual(route.path[0], [37.4607, 126.9526]);
    assert.equal(route.steps[0].description, "출발");
  }
  assert.equal(h.calls.length, 2);
  assert.ok(h.calls.every(call => call.url.startsWith("https://apis.openapi.sk.com/")));
  assert.match(h.calls[0].url, /routes\/pedestrian/);
  assert.match(h.calls[1].url, /routes\?version/);
});

test("TMAP 403·429 뒤 OSRM 실제 모드별 경로를 쓰며 키를 로그에 남기지 않는다", async () => {
  for (const status of [403, 429]) {
    const key = "test-only-secret";
    const h = harness(async url => url.includes("openapi.sk.com")
      ? response({ error: { code: "INVALID_API_KEY", message: `Forbidden ${key}` } }, status)
      : response(OSRM), key);
    const route = await h.getRoute("car", POINT);
    assert.equal(route.source, "OSRM");
    assert.equal(route.duration, 277.4);
    assert.match(route.notice, /실시간 교통.*반영되지/);
    assert.match(h.calls[1].url, /routed-car\/route\/v1\/car/);
    assert.ok(h.logs.some(line => line.includes(`HTTP ${status}`)));
    assert.ok(h.logs.some(line => line.includes("INVALID_API_KEY")));
    assert.ok(h.logs.every(line => !line.includes(key)));
  }
});

test("세 OSRM 모드의 시작 간격은 1초 이상이고 식별 헤더를 보낸다", async () => {
  const h = harness();
  const results = await Promise.all(["walk", "bike", "car"].map(mode => h.getRoute(mode, POINT)));
  assert.deepEqual(h.calls.map(call => call.at), [0, 1000, 2000]);
  assert.match(h.calls[0].url, /routed-foot\/route\/v1\/foot/);
  assert.match(h.calls[1].url, /routed-bike\/route\/v1\/bike/);
  assert.match(h.calls[2].url, /routed-car\/route\/v1\/car/);
  assert.ok(h.calls.every(call => call.options.headers["User-Agent"].startsWith("sharap/")));
  assert.ok(results.every(route => route.source === "OSRM" && route.notice));
  assert.deepEqual(results[0].path[0], [37.460709, 126.952606]);
});

test("동일 요청을 병합하고 60초 동안 성공 결과를 재사용한다", async () => {
  const h = harness();
  await Promise.all(Array.from({ length: 12 }, () => h.getRoute("bike", POINT)));
  assert.equal(h.calls.length, 1);
  h.advance(59000);
  await h.getRoute("bike", POINT);
  assert.equal(h.calls.length, 1);
  h.advance(1001);
  await h.getRoute("bike", POINT);
  assert.equal(h.calls.length, 2);
});

test("실패는 캐시하지 않고 다음 요청에서 정상 복구한다", async () => {
  let attempts = 0;
  const h = harness(async () => ++attempts === 1 ? response({}, 403) : response(OSRM));
  assert.equal((await invoke(h, "bike")).status, 503);
  assert.equal((await invoke(h, "bike")).status, 200);
  assert.equal(h.calls.length, 2);
});

test("OSRM 대기 큐 초과는 요청을 보내지 않고 ROUTE_BUSY를 반환한다", async () => {
  let unblock;
  const blocked = new Promise(resolve => { unblock = resolve; });
  const h = harness(async () => { await blocked; return response(OSRM); });
  const pending = Array.from({ length: 6 }, (_, i) => h.getRoute("bike", { ...POINT, dlat: POINT.dlat + i / 1000 }));
  const overflow = await invoke(h, "bike", { ...POINT, dlat: 37.5 });
  assert.equal(overflow.status, 503);
  assert.equal(overflow.body.code, "ROUTE_BUSY");
  unblock();
  await Promise.all(pending);
  assert.equal(h.calls.length, 6);
});

test("대기 시간이 너무 길면 오래된 요청을 외부 서비스에 보내지 않는다", async () => {
  let unblock;
  const blocked = new Promise(resolve => { unblock = resolve; });
  const h = harness(async () => { await blocked; return response(OSRM); });
  const first = h.getRoute("bike", POINT);
  const later = invoke(h, "car");
  await Promise.resolve();
  h.advance(16000);
  unblock();
  await first;
  assert.equal((await later).body.code, "ROUTE_BUSY");
  assert.equal(h.calls.length, 1);
});

test("OSRM 무경로 응답은 공급자 장애와 구분한다", async () => {
  for (const [code, status] of [["NoRoute", 200], ["NoSegment", 400]]) {
    const h = harness(async () => response({ code }, status));
    const result = await invoke(h, "walk");
    assert.equal(result.status, 404);
    assert.equal(result.body.code, "NO_ROUTE");
  }
});

test("시간·거리·경로 좌표가 잘못된 응답은 성공으로 제공하지 않는다", async () => {
  for (const changed of [
    { duration: 0 }, { duration: NaN }, { distance: Infinity }, { distance: -1 },
    { geometry: { type: "LineString", coordinates: [[126, 37]] } },
    { geometry: { type: "LineString", coordinates: [[126, 37], [126, 91]] } },
  ]) {
    const h = harness(async () => response({ code: "Ok", routes: [{ ...OSRM.routes[0], ...changed }] }));
    const result = await invoke(h, "bike");
    assert.equal(result.status, 502);
    assert.equal(result.body.code, "INVALID_ROUTE_RESPONSE");
  }
});

test("TMAP 경로가 손상돼도 OSRM으로 복구한다", async () => {
  const h = harness(async url => response(url.includes("openapi.sk.com") ? { features: [] } : OSRM), "test-only-secret");
  assert.equal((await h.getRoute("walk", POINT)).source, "OSRM");
  assert.equal(h.calls.length, 2);
});

test("공급자 타임아웃과 HTTP 오류는 안전한 한국어 응답으로 끝난다", async () => {
  for (const name of ["TimeoutError", "AbortError"]) {
    const h = harness(async () => { const error = new Error("request timed out"); error.name = name; throw error; });
    const result = await invoke(h, "bike");
    assert.equal(result.status, 504);
    assert.equal(result.body.code, "ROUTE_TIMEOUT");
    assert.ok(h.logs.some(line => line.includes("request timed out")));
  }
  for (const status of [403, 429]) {
    const h = harness(async () => response({ message: "upstream unavailable" }, status));
    const result = await invoke(h, "bike");
    assert.equal(result.status, 503);
    assert.equal(result.body.code, "ROUTE_PROVIDER_UNAVAILABLE");
    assert.doesNotMatch(result.body.error, /upstream/);
  }
});

async function invokeOdsayHandler(data, upstreamStatus = 200) {
  const source = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  const start = source.indexOf('app.get("/api/route/odsay/transit",');
  const end = source.indexOf('// 장소 검색 (카카오 로컬 API 프록시)', start);
  assert.ok(start >= 0 && end > start);
  let handler;
  vm.runInNewContext(source.slice(start, end), {
    app: { get: (_, callback) => { handler = callback; } },
    process: { env: { ODSAY_API_KEY: "test-only-key" } },
    URLSearchParams, AbortSignal,
    fetch: async () => ({ ...response(data, upstreamStatus), text: async () => JSON.stringify(data) }),
  });
  let status = 200;
  let body;
  await handler({ query: { olat: "37.45016", olng: "126.95259", dlat: "37.44887", dlng: "126.95265" } }, {
    status(value) { status = value; return this; },
    json(value) { body = JSON.parse(JSON.stringify(value)); },
  });
  return { status, body };
}

test("실제 ODSAY handler는 확인된 근거리 -98 응답을 정상 빈 경로로 처리한다", async () => {
  const result = await invokeOdsayHandler({ error: { msg: "출, 도착지가 700m이내입니다.", code: "-98" } });
  assert.deepEqual(result, { status: 200, body: { routes: [] } });
});

test("실제 ODSAY handler는 다른 공급자 오류와 HTTP 실패를 숨기지 않는다", async () => {
  const providerError = await invokeOdsayHandler({ error: { code: "MOCK_FAILURE", msg: "모의 공급자 장애" } });
  assert.equal(providerError.status, 500);
  assert.match(providerError.body.error, /MOCK_FAILURE/);
  const httpError = await invokeOdsayHandler({ message: "모의 호출 제한" }, 429);
  assert.equal(httpError.status, 500);
  assert.match(httpError.body.error, /ODSAY HTTP 429/);
});
