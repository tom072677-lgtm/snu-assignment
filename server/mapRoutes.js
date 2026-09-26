const REQUEST_TIMEOUT_MS = 10000;
const CACHE_TTL_MS = 60000;
const MAX_CACHE_ENTRIES = 100;
const MAX_OSRM_PENDING = 6;
const MAX_OSRM_WAIT_MS = 15000;
const USER_AGENT = "sharap/1.0 (+https://snu-assignment-server.onrender.com)";

class RouteError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

function validPoint(lat, lng) {
  return typeof lat === "number" && Number.isFinite(lat) && Math.abs(lat) <= 90
    && typeof lng === "number" && Number.isFinite(lng) && Math.abs(lng) <= 180;
}

function validateInput(input) {
  const { olat, olng, dlat, dlng } = input || {};
  if (!validPoint(olat, olng) || !validPoint(dlat, dlng)) {
    throw new RouteError(400, "INVALID_COORDINATES", "출발지와 도착지 좌표를 확인해 주세요.");
  }
  if (olat === dlat && olng === dlng) {
    throw new RouteError(400, "SAME_LOCATION", "출발지와 도착지가 같습니다.");
  }
  return { olat, olng, dlat, dlng };
}

function validateRoute(route) {
  if (!Number.isFinite(route.duration) || route.duration <= 0
      || !Number.isFinite(route.distance) || route.distance <= 0
      || !Array.isArray(route.path) || route.path.length < 2
      || !route.path.every(p => Array.isArray(p) && p.length === 2 && validPoint(p[0], p[1]))) {
    throw new RouteError(502, "INVALID_ROUTE_RESPONSE", "경로 데이터가 올바르지 않습니다. 다시 시도해 주세요.");
  }
  return route;
}

function parseTmap(data) {
  const features = Array.isArray(data?.features) ? data.features : [];
  const summary = features.find(f => f?.properties?.totalTime != null
    && f.properties.totalDistance != null)?.properties;
  const path = [];
  const steps = [];
  for (const feature of features) {
    if (feature?.geometry?.type === "LineString" && Array.isArray(feature.geometry.coordinates)) {
      for (const point of feature.geometry.coordinates) path.push([point?.[1], point?.[0]]);
    } else if (feature?.geometry?.type === "Point" && typeof feature.properties?.description === "string") {
      const p = feature.properties;
      steps.push({ description: p.description,
        distance: Number.isFinite(p.distance) ? p.distance : 0,
        turnType: Number.isFinite(p.turnType) ? p.turnType : 0 });
    }
  }
  return validateRoute({ duration: summary?.totalTime, distance: summary?.totalDistance, path, steps });
}

function parseOsrm(data) {
  if (data?.code === "NoRoute" || data?.code === "NoSegment") {
    throw new RouteError(404, "NO_ROUTE", "이 구간의 경로를 찾지 못했습니다. 출발지나 도착지를 변경해 주세요.");
  }
  const route = data?.code === "Ok" ? data.routes?.[0] : null;
  const coords = route?.geometry?.type === "LineString" ? route.geometry.coordinates : null;
  return validateRoute({ duration: route?.duration, distance: route?.distance,
    path: Array.isArray(coords) ? coords.map(p => [p?.[1], p?.[0]]) : [], steps: [] });
}

function createMapRoutes({ fetchImpl = fetch, tmapKey = () => process.env.TMAP_API_KEY,
  now = Date.now, sleep = ms => new Promise(resolve => setTimeout(resolve, ms)),
  logger = message => console.warn(message) } = {}) {
  const cache = new Map();
  const inFlight = new Map();
  let osrmTail = Promise.resolve();
  let osrmPending = 0;
  let lastOsrmStart = -Infinity;

  // 이 프로세스의 모든 모드가 큐를 공유한다. 여러 서버 인스턴스에서는 별도 공유 한도가 필요하다.
  function scheduleOsrm(run) {
    if (osrmPending >= MAX_OSRM_PENDING) {
      return Promise.reject(new RouteError(503, "ROUTE_BUSY", "경로 요청이 많습니다. 잠시 후 다시 시도해 주세요."));
    }
    osrmPending++;
    const queuedAt = now();
    const result = osrmTail.then(async () => {
      const wait = Math.max(0, 1000 - (now() - lastOsrmStart));
      if (now() - queuedAt + wait > MAX_OSRM_WAIT_MS) {
        throw new RouteError(503, "ROUTE_BUSY", "경로 요청이 많습니다. 잠시 후 다시 시도해 주세요.");
      }
      if (wait) await sleep(wait);
      lastOsrmStart = now();
      return run();
    }).finally(() => { osrmPending--; });
    osrmTail = result.catch(() => {});
    return result;
  }

  function safeText(value, secret = "") {
    let text = String(value ?? "");
    if (secret) text = text.split(secret).join("[redacted]");
    return text.replace(/(?:appkey|api[_-]?key|token|authorization)\s*[=:]\s*[^\s,;]+/gi, "[redacted]").slice(0, 180);
  }

  async function requestJson(provider, url, options, secret = "") {
    let response;
    try {
      response = await fetchImpl(url, { ...options, signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });
    } catch (error) {
      logger(`[mapRoutes] ${provider} ${safeText(error?.name, secret)}: ${safeText(error?.message, secret)}`);
      if (error?.name === "TimeoutError" || error?.name === "AbortError") {
        throw new RouteError(504, "ROUTE_TIMEOUT", "경로 조회가 지연되고 있습니다. 다시 시도해 주세요.");
      }
      throw new RouteError(502, "ROUTE_NETWORK_ERROR", "경로 서비스에 연결하지 못했습니다. 다시 시도해 주세요.");
    }
    let data;
    try { data = await response.json(); } catch (error) {
      logger(`[mapRoutes] ${provider} HTTP ${response.status}: ${safeText(error?.name)} ${safeText(error?.message, secret)}`);
      if (error?.name === "TimeoutError" || error?.name === "AbortError") {
        throw new RouteError(504, "ROUTE_TIMEOUT", "경로 조회가 지연되고 있습니다. 다시 시도해 주세요.");
      }
    }
    if (provider === "OSRM" && ["NoRoute", "NoSegment"].includes(data?.code)) return data;
    if (!response.ok || data?.error) {
      const detail = data?.error || data;
      logger(`[mapRoutes] ${provider} HTTP ${response.status}: ${JSON.stringify({
        code: safeText(detail?.code ?? detail?.id, secret), message: safeText(detail?.message, secret),
      })}`);
      throw new RouteError(503, "ROUTE_PROVIDER_UNAVAILABLE", "경로 제공 서비스가 일시적으로 응답하지 않습니다. 다시 시도해 주세요.");
    }
    return data;
  }

  async function tmapRoute(mode, point, key) {
    const url = `https://apis.openapi.sk.com/tmap/routes${mode === "walk" ? "/pedestrian" : ""}?version=1`;
    const data = await requestJson("TMAP", url, {
      method: "POST", headers: { "Content-Type": "application/json", appKey: key },
      body: JSON.stringify({ startX: String(point.olng), startY: String(point.olat),
        endX: String(point.dlng), endY: String(point.dlat), reqCoordType: "WGS84GEO",
        resCoordType: "WGS84GEO", startName: "start", endName: "end" }),
    }, key);
    return { ...parseTmap(data), source: "TMAP", notice: "예상 소요시간은 실제 이동 상황에 따라 달라질 수 있습니다." };
  }

  async function osrmRoute(mode, point) {
    const profile = mode === "walk" ? "foot" : mode;
    const url = `https://routing.openstreetmap.de/routed-${profile}/route/v1/${profile}`
      + `/${point.olng},${point.olat};${point.dlng},${point.dlat}?overview=full&geometries=geojson`;
    const data = await scheduleOsrm(() => requestJson("OSRM", url, { headers: { "User-Agent": USER_AGENT } }));
    return { ...parseOsrm(data), source: "OSRM", notice: mode === "car"
      ? "지도 데이터 기반 예상 경로이며 실시간 교통은 반영되지 않습니다."
      : "지도 데이터 기반 예상 경로입니다. 실제 통행 가능 여부와 소요시간은 달라질 수 있습니다." };
  }

  async function getRoute(mode, input) {
    if (!["walk", "bike", "car"].includes(mode)) {
      throw new RouteError(400, "INVALID_MODE", "지원하지 않는 이동수단입니다.");
    }
    const point = validateInput(input);
    const cacheKey = `${mode}:${point.olat},${point.olng}:${point.dlat},${point.dlng}`;
    const cached = cache.get(cacheKey);
    if (cached && now() - cached.at < CACHE_TTL_MS) return cached.route;
    if (inFlight.has(cacheKey)) return inFlight.get(cacheKey);
    const promise = (async () => {
      let route;
      const key = tmapKey();
      if (mode !== "bike" && key) {
        try { route = await tmapRoute(mode, point, key); } catch (error) {
          logger(`[mapRoutes] TMAP ${mode} 대체 경로 사용: ${safeText(error?.code)} ${safeText(error?.message, key)}`);
        }
      }
      if (!route) route = await osrmRoute(mode, point);
      cache.delete(cacheKey);
      if (cache.size >= MAX_CACHE_ENTRIES) cache.delete(cache.keys().next().value);
      cache.set(cacheKey, { at: now(), route });
      return route;
    })().finally(() => inFlight.delete(cacheKey));
    inFlight.set(cacheKey, promise);
    return promise;
  }

  function handler(mode) {
    return async (req, res) => {
      try { res.json(await getRoute(mode, req.body)); } catch (error) {
        logger(`[mapRoutes] ${mode}: ${safeText(error?.code)} ${safeText(error?.message, tmapKey())}`);
        const known = error instanceof RouteError;
        res.status(known ? error.status : 502).json({
          code: known ? error.code : "ROUTE_ERROR",
          error: known ? error.message : "경로를 불러오지 못했습니다. 다시 시도해 주세요.",
        });
      }
    };
  }
  return { getRoute, handler };
}

module.exports = { createMapRoutes };
