/**
 * collect_venues.js
 * Google Places API (New) 로 서울대입구·낙성대·대학동 식당 데이터 수집
 * 수집 결과를 기존 venues.json (교내 데이터)에 병합하여 저장
 *
 * 실행: node scripts/collect_venues.js
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

// 키는 환경변수로만 (리포에 박지 않음). 실행: GOOGLE_PLACES_KEY=... node scripts/collect_venues.js
const API_KEY = process.env.GOOGLE_PLACES_KEY;
if (!API_KEY) throw new Error('GOOGLE_PLACES_KEY 환경변수가 필요합니다');

// ── 수집 대상 지역 ────────────────────────────────────────────────────
// 낙성대 → 서울대입구로 통합 (샤로수길 상권 전체)
// 대학동 → 서울대 정문·대학길 주변으로 재정의
const NEARBY_AREAS = [
  // 서울대입구 (샤로수길 + 낙성대역 포함 상권 전체, 9개 소구역)
  { name: '서울대입구', lat: 37.4811, lng: 126.9527, radius: 350 }, // 역 중심
  { name: '서울대입구', lat: 37.4780, lng: 126.9520, radius: 350 }, // 샤로수길 남
  { name: '서울대입구', lat: 37.4843, lng: 126.9510, radius: 350 }, // 봉천동 북
  { name: '서울대입구', lat: 37.4811, lng: 126.9565, radius: 350 }, // 관악로 동
  { name: '서울대입구', lat: 37.4811, lng: 126.9490, radius: 350 }, // 봉천동 서
  { name: '서울대입구', lat: 37.4755, lng: 126.9540, radius: 350 }, // 샤로수길 끝
  { name: '서울대입구', lat: 37.4766, lng: 126.9648, radius: 350 }, // 낙성대역 중심
  { name: '서울대입구', lat: 37.4740, lng: 126.9640, radius: 300 }, // 낙성대 남
  { name: '서울대입구', lat: 37.4792, lng: 126.9655, radius: 300 }, // 낙성대 북
  // 대학동 (서울대 정문·대학길 주변, 4개 소구역)
  { name: '대학동', lat: 37.4683, lng: 126.9378, radius: 300 }, // 대학길 중심 (오삼숙이)
  { name: '대학동', lat: 37.4660, lng: 126.9376, radius: 300 }, // 대학길 남
  { name: '대학동', lat: 37.4700, lng: 126.9395, radius: 300 }, // 대학길 북
  { name: '대학동', lat: 37.4683, lng: 126.9430, radius: 300 }, // 동쪽 인근
];

// Nearby Search 타입 목록 (치킨집·해산물·국수 등 추가)
const TYPE_MAP = [
  { googleType: 'restaurant',              category: 'restaurant' },
  { googleType: 'korean_restaurant',       category: 'restaurant' },
  { googleType: 'japanese_restaurant',     category: 'restaurant' },
  { googleType: 'chinese_restaurant',      category: 'restaurant' },
  { googleType: 'ramen_restaurant',        category: 'restaurant' },
  { googleType: 'sushi_restaurant',        category: 'restaurant' },
  { googleType: 'fast_food_restaurant',    category: 'restaurant' },
  { googleType: 'pizza_restaurant',        category: 'restaurant' },
  { googleType: 'chicken_restaurant',      category: 'restaurant' }, // 치킨집 추가
  { googleType: 'seafood_restaurant',      category: 'restaurant' }, // 해산물
  // noodle_restaurant — Google Places API 미지원 타입, 제거
  { googleType: 'steak_house',             category: 'restaurant' }, // 스테이크
  { googleType: 'brunch_restaurant',       category: 'restaurant' }, // 브런치
  { googleType: 'bar',                     category: 'restaurant' },
  { googleType: 'wine_bar',               category: 'restaurant' },
  { googleType: 'cocktail_bar',           category: 'restaurant' },
  { googleType: 'pub',                    category: 'restaurant' }, // 펍 추가
  { googleType: 'cafe',                   category: 'cafe' },
  { googleType: 'bakery',                 category: 'cafe' },
  { googleType: 'ice_cream_shop',         category: 'cafe' },
  { googleType: 'dessert_shop',           category: 'cafe' },
  { googleType: 'tea_house',              category: 'cafe' },
  { googleType: 'convenience_store',      category: 'convenience' },
];

// Text Search 쿼리 — 낙성대 → 서울대입구 통합, 대학동 좌표 교정
const TEXT_QUERIES = [
  // 서울대입구 (샤로수길 + 낙성대 통합)
  { query: '샤로수길 맛집',         area: '서울대입구', lat: 37.4795, lng: 126.9530, radius: 800 },
  { query: '샤로수길 카페',         area: '서울대입구', lat: 37.4795, lng: 126.9530, radius: 800 },
  { query: '샤로수길 디저트',       area: '서울대입구', lat: 37.4795, lng: 126.9530, radius: 800 },
  { query: '서울대입구역 맛집',     area: '서울대입구', lat: 37.4811, lng: 126.9527, radius: 800 },
  { query: '서울대입구역 술집',     area: '서울대입구', lat: 37.4811, lng: 126.9527, radius: 800 },
  { query: '서울대입구역 치킨',     area: '서울대입구', lat: 37.4811, lng: 126.9527, radius: 800 },
  { query: '봉천동 맛집',           area: '서울대입구', lat: 37.4830, lng: 126.9510, radius: 600 },
  { query: '봉천동 카페',           area: '서울대입구', lat: 37.4830, lng: 126.9510, radius: 600 },
  { query: '낙성대 맛집',           area: '서울대입구', lat: 37.4766, lng: 126.9648, radius: 600 },
  { query: '낙성대 카페',           area: '서울대입구', lat: 37.4766, lng: 126.9648, radius: 600 },
  { query: '낙성대 술집',           area: '서울대입구', lat: 37.4766, lng: 126.9648, radius: 600 },
  { query: '낙성대 치킨',           area: '서울대입구', lat: 37.4766, lng: 126.9648, radius: 600 },
  { query: '낙성대역 편의점',       area: '서울대입구', lat: 37.4766, lng: 126.9648, radius: 600 },
  // 대학동 (서울대 정문·대학길 주변)
  { query: '관악구 대학길 맛집',    area: '대학동',    lat: 37.4683, lng: 126.9378, radius: 500 },
  { query: '관악구 대학길 카페',    area: '대학동',    lat: 37.4683, lng: 126.9378, radius: 500 },
  { query: '서울대 정문 맛집',      area: '대학동',    lat: 37.4683, lng: 126.9378, radius: 500 },
  { query: '녹두거리 맛집',         area: '대학동',    lat: 37.4686, lng: 126.9378, radius: 400 },
];

// 요청할 필드 (Field Mask)
const NEARBY_FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.formattedAddress',
  'places.location',
  'places.nationalPhoneNumber',
  'places.regularOpeningHours',
  'places.priceLevel',
  'places.primaryType',
].join(',');

// Text Search는 nextPageToken도 포함
const TEXT_FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.formattedAddress',
  'places.location',
  'places.nationalPhoneNumber',
  'places.regularOpeningHours',
  'places.priceLevel',
  'places.primaryType',
  'nextPageToken',
].join(',');

// ── API 호출 함수 ──────────────────────────────────────────────────────

function httpsPost(path, body, fieldMask) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'places.googleapis.com',
      path,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': API_KEY,
        'X-Goog-FieldMask': fieldMask,
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error('JSON parse error: ' + data.slice(0, 200))); }
      });
    });
    req.on('error', reject);
    req.write(JSON.stringify(body));
    req.end();
  });
}

// Place Details — 한국어 이름 단건 조회
function fetchKoreanName(placeId) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'places.googleapis.com',
      path: `/v1/places/${placeId}?languageCode=ko`,
      method: 'GET',
      headers: {
        'X-Goog-Api-Key': API_KEY,
        'X-Goog-FieldMask': 'displayName',
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { resolve(null); }
      });
    });
    req.on('error', () => resolve(null));
    req.end();
  });
}

// Nearby Search (New)
function nearbySearch(lat, lng, radius, googleType) {
  return httpsPost('/v1/places:searchNearby', {
    includedTypes: [googleType],
    maxResultCount: 20,
    languageCode: 'ko',   // 한국어 이름 우선 반환
    locationRestriction: {
      circle: { center: { latitude: lat, longitude: lng }, radius },
    },
  }, NEARBY_FIELD_MASK);
}

// Text Search (New) — 최대 3페이지(60개)까지 수집
async function textSearchAll(query, lat, lng, radius) {
  const results = [];
  let pageToken = null;

  for (let page = 0; page < 3; page++) {
    const body = {
      textQuery: query,
      pageSize: 20,
      languageCode: 'ko',
      locationBias: {
        circle: { center: { latitude: lat, longitude: lng }, radius },
      },
    };
    if (pageToken) body.pageToken = pageToken;

    const result = await httpsPost('/v1/places:searchText', body, TEXT_FIELD_MASK);
    if (result.error) {
      console.error(`  ❌ Text Search 오류: ${result.error.message}`);
      break;
    }
    const places = result.places ?? [];
    results.push(...places);
    if (!result.nextPageToken || places.length === 0) break;
    pageToken = result.nextPageToken;
    await sleep(500); // 페이지 간 딜레이
  }
  return results;
}

// ── 변환 함수 ──────────────────────────────────────────────────────────

function parsePriceLevel(priceLevel) {
  const map = {
    PRICE_LEVEL_FREE: 1,
    PRICE_LEVEL_INEXPENSIVE: 1,
    PRICE_LEVEL_MODERATE: 2,
    PRICE_LEVEL_EXPENSIVE: 3,
    PRICE_LEVEL_VERY_EXPENSIVE: 3,
  };
  return map[priceLevel] ?? null;
}

function parseHours(regularOpeningHours) {
  if (!regularOpeningHours || !regularOpeningHours.periods) {
    return {
      weekday:  { ranges: [], closed: true },
      saturday: { ranges: [], closed: true },
      sunday:   { ranges: [], closed: true },
    };
  }
  const dayRanges = { 0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: [] };
  for (const p of regularOpeningHours.periods) {
    if (!p.open || !p.close) continue;
    const day = p.open.day;
    const open  = `${String(p.open.hour).padStart(2,'0')}:${String(p.open.minute ?? 0).padStart(2,'0')}`;
    const close = `${String(p.close.hour).padStart(2,'0')}:${String(p.close.minute ?? 0).padStart(2,'0')}`;
    dayRanges[day].push({ open, close });
  }
  const weekdayRanges = [1,2,3,4,5].map(d => dayRanges[d]);
  const allSame = weekdayRanges.every(r => JSON.stringify(r) === JSON.stringify(weekdayRanges[0]));
  const weekday = allSame && weekdayRanges[0].length > 0
    ? { ranges: weekdayRanges[0], closed: false }
    : weekdayRanges.find(r => r.length > 0)
      ? { ranges: weekdayRanges.find(r => r.length > 0), closed: false }
      : { ranges: [], closed: true };
  const sat = dayRanges[6];
  const sun = dayRanges[0];
  return {
    weekday,
    saturday: sat.length > 0 ? { ranges: sat, closed: false } : { ranges: [], closed: true },
    sunday:   sun.length > 0 ? { ranges: sun, closed: false } : { ranges: [], closed: true },
  };
}

// 검색 편의를 위한 토큰 생성
// 한국어 이름, 영문 이름, 주소 일부를 합쳐 저장 → 앱에서 searchTokens 필드로 검색 가능
function buildSearchTokens(name, address) {
  const tokens = new Set();
  tokens.add(name.toLowerCase());
  // 공백 제거 버전도 추가 (예: "킷샤서울" → "kitsa seoul" 역방향은 불가하지만)
  tokens.add(name.replace(/\s/g, '').toLowerCase());
  // 주소에서 동 이름 추출
  const dongMatch = address.match(/([가-힣]+동)/);
  if (dongMatch) tokens.add(dongMatch[1]);
  return [...tokens].join(' ');
}

function convertPlace(place, areaName, category) {
  const name = place.displayName?.text ?? '이름 없음';
  const address = place.formattedAddress ?? '';
  return {
    id: place.id,
    name,
    category,
    type: 'static',
    building: areaName,
    address,
    lat: place.location?.latitude ?? 0,
    lng: place.location?.longitude ?? 0,
    phone: place.nationalPhoneNumber ?? null,
    tags: [],
    snucoName: null,
    instagramHandle: null,
    area: areaName,
    cuisineType: null,
    priceLevel: parsePriceLevel(place.priceLevel),
    hours: parseHours(place.regularOpeningHours),
    searchTokens: buildSearchTokens(name, address), // 검색 편의 필드
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── 메인 ──────────────────────────────────────────────────────────────

async function main() {
  const refreshOnly = process.argv.includes('--refresh-only');
  console.log(refreshOnly
    ? '🔄 한국어 이름 갱신 모드 (신규 수집 건너뜀)\n'
    : '📍 Google Places API 데이터 수집 시작\n');

  const venuesPath = path.join(__dirname, '../assets/data/venues.json');
  const raw = fs.readFileSync(venuesPath, 'utf8').replace(/^﻿/, '');
  const existing = JSON.parse(raw);
  const existingIds = new Set(existing.map(v => v.id));
  console.log(`✅ 기존 데이터: ${existing.length}개 로드됨\n`);

  const collected = [];
  let totalCalls = 0;

  if (refreshOnly) {
    // Step 1·2 건너뛰고 바로 Step 3으로
    const fakeSampleIds = new Set([
      'sillim-shabu', 'nakseongdae-jjajang', 'daehakdong-pasta',
      'sillim-cafe-hello', 'nakseongdae-gs',
    ]);
    const merged = existing.filter(v => !fakeSampleIds.has(v.id));
    const latinOnly = /^[^가-힣ㄱ-ㆎ]+$/;
    const needKorean = merged.filter(v => v.area !== '교내' && latinOnly.test(v.name));
    console.log(`=== 한국어 이름 재조회 (영문명 ${needKorean.length}개) ===\n`);
    let refreshed = 0;
    for (const venue of needKorean) {
      try {
        const result = await fetchKoreanName(venue.id);
        const korName = result?.displayName?.text;
        if (korName && korName !== venue.name) {
          process.stdout.write(`  🌏 "${venue.name}" → "${korName}"\n`);
          venue.name = korName;
          refreshed++;
        }
        totalCalls++;
      } catch (_) {}
      await sleep(100);
    }
    for (const venue of merged) {
      venue.searchTokens = buildSearchTokens(venue.name, venue.address ?? '');
    }
    fs.writeFileSync(venuesPath, JSON.stringify(merged, null, 2), 'utf8');
    console.log(`\n✅ 완료! API 호출: ${totalCalls}회, 이름 갱신: ${refreshed}개`);
    return;
  }

  // ── Step 1: Nearby Search ──────────────────────────────────────────
  console.log('=== [1/2] Nearby Search ===\n');
  for (const area of NEARBY_AREAS) {
    for (const { googleType, category } of TYPE_MAP) {
      process.stdout.write(`🔍 [${area.name}] ${googleType} ... `);
      try {
        const result = await nearbySearch(area.lat, area.lng, area.radius, googleType);
        totalCalls++;
        if (result.error) {
          console.log(`❌ ${result.error.message}`);
          continue;
        }
        const places = result.places ?? [];
        const newOnes = places.filter(p => !existingIds.has(p.id));
        console.log(`${places.length}개 발견, ${newOnes.length}개 신규`);
        for (const place of newOnes) {
          const venue = convertPlace(place, area.name, category);
          collected.push(venue);
          existingIds.add(place.id);
        }
      } catch (e) {
        console.log(`❌ ${e.message}`);
      }
      await sleep(200);
    }
  }

  // ── Step 2: Text Search (한국어 쿼리, 페이지네이션) ───────────────
  console.log('\n=== [2/2] Text Search (Korean queries) ===\n');
  for (const { query, area: areaName, lat, lng, radius } of TEXT_QUERIES) {
    process.stdout.write(`🔍 "${query}" ... `);
    try {
      const places = await textSearchAll(query, lat, lng, radius);
      totalCalls += Math.ceil(places.length / 20) || 1;
      const newOnes = places.filter(p => !existingIds.has(p.id));
      console.log(`${places.length}개 발견, ${newOnes.length}개 신규`);
      for (const place of newOnes) {
        // Text Search로 가져온 장소는 지역명 기준으로 area 설정
        const venue = convertPlace(place, areaName, guessCategory(place));
        collected.push(venue);
        existingIds.add(place.id);
      }
    } catch (e) {
      console.log(`❌ ${e.message}`);
    }
    await sleep(300);
  }

  // 가짜 샘플 제거
  const fakeSampleIds = new Set([
    'sillim-shabu', 'nakseongdae-jjajang', 'daehakdong-pasta',
    'sillim-cafe-hello', 'nakseongdae-gs',
  ]);
  const cleaned = existing.filter(v => !fakeSampleIds.has(v.id));
  const merged = [...cleaned, ...collected];

  // ── Step 3: 전체 venues searchTokens 채우기 + 영문 이름 한국어 re-fetch ──
  // 영문만으로 된 이름 판별 (한국어 문자 없음)
  const latinOnly = /^[^가-힣ㄱ-ㆎ]+$/;
  const offCampus = merged.filter(v => v.area !== '교내');
  const needKorean = offCampus.filter(v => latinOnly.test(v.name));

  console.log(`\n=== [3/3] 한국어 이름 재조회 (영문명 ${needKorean.length}개) ===\n`);
  let refreshed = 0;
  for (const venue of needKorean) {
    try {
      const result = await fetchKoreanName(venue.id);
      const korName = result?.displayName?.text;
      if (korName && korName !== venue.name) {
        process.stdout.write(`  🌏 "${venue.name}" → "${korName}"\n`);
        venue.name = korName;
        refreshed++;
      }
      totalCalls++;
    } catch (_) {}
    await sleep(100);
  }
  console.log(`  → ${refreshed}개 이름 갱신\n`);

  // searchTokens: 전체 merged에서 없거나 이름이 바뀐 것 모두 재생성
  for (const venue of merged) {
    venue.searchTokens = buildSearchTokens(venue.name, venue.address ?? '');
  }

  fs.writeFileSync(venuesPath, JSON.stringify(merged, null, 2), 'utf8');

  console.log('─'.repeat(50));
  console.log(`✅ 완료!`);
  console.log(`   API 호출 수: ${totalCalls}회`);
  console.log(`   새로 수집:   ${collected.length}개`);
  console.log(`   한국어 이름 갱신: ${refreshed}개`);
  console.log(`   최종 총합:   ${merged.length}개`);
  console.log(`\n⚠️  cuisineType은 수동 입력 필요`);
}

// Text Search 결과의 카테고리 추정 (primaryType 기반)
function guessCategory(place) {
  const type = place.primaryType ?? '';
  if (type.includes('convenience')) return 'convenience';
  if (type.includes('cafe') || type.includes('bakery') || type.includes('ice_cream')
      || type.includes('dessert') || type.includes('tea')) return 'cafe';
  return 'restaurant';
}

main().catch(console.error);
