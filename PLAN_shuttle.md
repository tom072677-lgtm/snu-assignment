# PLAN — Shuttle + transit routing improvements (priorities 1–6)

All changes are in `server/index.js`, in the tightly-coupled region lines ~1653–2040
(`STATION_COORDS`, timing constants, `computeShuttleRoutes`, `callOdsay`, the
`/api/route/shuttle` handler, dedup). Because they all touch the same ~400 lines and
overlap semantically, this is implemented as ONE sequential pass, one git commit per
improvement (not parallel agents — concurrent edits on one function would corrupt it).

## Verification level (honesty, global rule 10)
Deliverable = code-reviewed + `node -c server/index.js` syntax-checked + a local pure-function
smoke test for the offline parts (#4, #6). Live behavior of TMAP / ODSAY / the SNU arrival
scraper can only be proven after `git push` (Render deploy) + on-device test. Nothing here is
called "작동 확인됨" until the user device-tests.

## Why this is safe vs rules 7/9
#1 and #2 touch external calls but REUSE already-verified integrations that run in production
today: the live `/api/shuttle/arrival` scraper and `fetchTmapRoute` (TMAP pedestrian). No new
unverified data source is introduced, so rule 9's "verify the API shape first" risk is absent.

## Response contract (must not break)
The app consumes `routes[].{duration, distance, fare, path, legs[], badges}` and each leg's
`{type, name, color, duration, distance, startStation, endStation, stations,
shuttleRouteId, shuttleStationCode, subwayCode, stId, busRouteId, ord}`.
All edits are ADDITIVE or value-refining — no field renamed or removed.

---

## Improvement order (low-risk → high-risk; each = 1 commit)

### #4 — Dedup by leg signature (first; isolated pure logic)
Current: drop a route if `|duration - other.duration| < 90s` (drops genuinely different routes
that happen to be similar length).
New: signature = ordered join of each leg's `type` + line id (`shuttleRouteId` for shuttle,
`subwayCode` for subway, `busRouteId` for bus, `"walk"` for walk). Two routes are duplicates
only if signatures match; among matches keep the fastest. Keep distinct signatures even at
similar durations. Still cap at top 4 after sorting by duration.
Verify: pure-function smoke test (two routes, same legs vs different legs).

### #6 — Distance-based shuttle timing (replaces flat 120s/stop)
Current: `shuttleSec = numStops*120 + 120`.
New: per consecutive station pair in [board..alight], sum `haversineMeters(stop_i, stop_{i+1})`,
divide by `SHUTTLE_MPS` (campus speed ≈ 18 km/h = 5 m/s), add `SHUTTLE_DWELL_SEC` (≈ 15s) per
intermediate stop, plus existing `SHUTTLE_WAIT_SEC` initial wait. Uses coords already present →
realistic relative timing. New constants `SHUTTLE_MPS`, `SHUTTLE_DWELL_SEC`.
NOTE the coupling: accuracy is bounded by STATION_COORDS accuracy (see #5).
Verify: smoke test — durations vary by segment length, monotonic in stop count.

### #3 — Real transfer time (replaces fixed TRANSFER_SEC=120 in combined routes)
Current: fixed 120s walk leg at the hub.
New: `transferSec = clamp( haversineMeters(hub.coords, firstOdsayAccessPoint)/WALK_MPS + 30, 60, 600 )`.
`firstOdsayAccessPoint` = first coordinate of `odsay.path` (fallback: keep 120s if path empty).
Update the transfer leg's `duration`/`distance` and the combined `duration` accordingly.
Verify: node -c; logic review (clamp bounds).

### #2 — Real walking distance/time via TMAP pedestrian (post-selection only)
Do NOT call TMAP inside the brute force (hundreds of candidates → API blowup). Instead, after the
final top-4 are chosen, for each route's `walk` legs call `fetchTmapRoute(pedestrian)` to replace
the straight-line haversine/4kmh estimate with real walk duration+distance. Parallelize with
`Promise.allSettled`; on any failure keep the haversine estimate (fail-open). Recompute route
`duration` from refined legs.
Verify: node -c; ensure handler still returns even if all TMAP calls fail.

### #1 — Time-awareness via live arrival scraper (highest value)
After final routes are chosen, for each route with a shuttle leg, look up live arrival using the
leg's `shuttleRouteId` + `shuttleStationCode` through the SAME logic as `/api/shuttle/arrival`
(refactor its scrape into a reusable `fetchShuttleArrival(routeId, stationCode)` helper using the
existing 15s cache). Attach `leg.live = {first, second}`. If a shuttle has no upcoming arrival
("운행정보없음"/null), mark the route (`leg.notRunning = true`) and DOWN-RANK it (sort running
routes first) — do not hard-drop, and FAIL-OPEN on scraper error (keep route). Bound calls to the
≤ handful of final routes; parallelize; reuse cache.
Verify: node -c; refactor keeps `/api/shuttle/arrival` behavior identical.

### #5 — Station coordinate precision (data-limited; honest partial)
True fix needs surveyed coordinates I cannot fabricate. Action: add a clearly-marked TODO block
above STATION_COORDS listing the data smells (e.g. 100/101 identical, 710 reusing 601's coords,
300/900/901/1000/1001 overlaps) and a verification checklist (measure each on Naver/Google Maps).
No invented numbers. Note the coupling to #6's accuracy.
Verify: node -c; documented, no false precision.

---

## Revisions after Codex review (v2 — adopted)
- **Pipeline restructure (main fix):** refine a BOUNDED CANDIDATE POOL before final sort/dedup/cap,
  so #2/#1 can't hide a better route. New handler flow:
  1) direct (distance-based #6) + combined (real transfer #3)
  2) sort by duration → take pool = top 10
  3) refine pool: #2 TMAP walk legs (parallel, fail-open) + #1 live-arrival annotate
     (parallel, scrapes de-duped by `routeId+stationCode`, fail-open)
  4) recompute each route.duration from refined legs (stay consistent with legs[])
  5) final sort: running routes first, then duration
  6) #4 signature dedup on FINALIZED durations → cap top 4 → badges
- **#6 fallback:** if any segment in [board..alight] lacks coords (missing/null), fall back to the
  old `numStops*120+120` for the WHOLE shuttle leg (no partial bad math). Guard board==alight,
  zero/one-stop; circular routes use index range so repeats are fine.
- **#3 sanity:** keep fixed 120s unless the ODSAY access coord passes a Seoul-bounds check
  (lat 37.0–37.8, lng 126.6–127.3) — also guards lat/lng order bugs. Clamp [60,600].
- **#1 sort/edge rules:** running-first then duration; scraper failure / no shuttle leg / malformed /
  only `second` present ⇒ treat as running (fail-open, no down-rank). Only an explicit
  "운행정보없음"/empty with a successful scrape marks `notRunning`.
- **#4 null-id signatures:** when a leg's line id is null, fall back to `type+startStation+endStation`
  so distinct null-id routes don't collide.
- **#5 is documentation-only** — explicitly NOT a runtime-behavior improvement.
- **Arrival cache stampede:** de-dupe scrape keys across the pool before firing (one call per
  unique `routeId+stationCode`), reuse existing 15s cache.

## Out of scope (YAGNI)
- Rewriting brute force into k-shortest-path / graph search.
- New external sources or app-side (Flutter) changes.
- Caching layer for combined routes beyond what exists.

## Success criteria
1. `node -c server/index.js` passes after every step.
2. Pure-function smoke test passes for #4 (dedup keeps distinct signatures) and #6 (distance-based
   durations sane).
3. Response contract fields unchanged (additive only) — app keeps working.
4. Each improvement is its own English, why-focused commit (rule 12).
5. Fail-open everywhere external (TMAP/ODSAY/arrival down ⇒ route still returned, never a 500).
6. Honest status: live API correctness pending user deploy + device test (rule 10).
