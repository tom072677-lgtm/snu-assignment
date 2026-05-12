node.exe : OpenAI Codex v0.130.0
At C:\Users\tom07\AppData\Roaming\npm\codex.ps1:24 char:5
+     & "node$exe"  "$basedir/node_modules/@openai/codex/bin/codex.js"  ...
+     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (OpenAI Codex v0.130.0:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 
--------
workdir: C:\Users\tom07\Desktop\snu 과제 앱
model: gpt-5.5
provider: openai
approval: never
sandbox: read-only
reasoning effort: medium
reasoning summaries: none
session id: 019e1cc2-92c7-75e3-b19b-d9e03f37bb40
--------
user
current changes
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git status --short' in C:\Users\tom07\Deskto
p\snu 과제 앱
 succeeded in 815ms:
 M script.js
 M server/index.js
 M style.css
?? CODEX_CODE_REVIEW.md
?? CODEX_REVIEW.md
?? PLAN.md
?? PLAN_REVIEW.md

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git diff -- script.js server/index.js style.
css; git diff --cached -- script.js server/index.js style.css' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 953ms:
diff --git a/script.js b/script.js
index e436d70..4894f40 100644
--- a/script.js
+++ b/script.js
@@ -1157,6 +1157,12 @@ let leafletMap = null;
 let leafletMarkers = [];
 let activeMapFilter = "all";
 
+// 내 위치/방향 상태
+let locationDot = null;
+let accuracyCircle = null;
+let orientationListenerAdded = false;
+let onOrientationHandler = null;
+
 // 타입별 마커 색상
 const MAP_COLORS = { restaurant: "#ef4444", cafe: "#f59e0b", building: "#3b82f6" };
 
@@ -1201,57 +1207,119 @@ function applyMapFilter(filter) {
 
 function renderMapTab() {
   if (!leafletMap) {
-    // 지도 초기화 (캠퍼스 중심)
     leafletMap = L.map("mapContainer", { zoomControl: true }).setView([37.4651, 126.9507], 15);
     L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
       attribution: "© <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a>",
       maxZoom: 19,
     }).addTo(leafletMap);
 
-    // 마커 추가
-    SNU_LOCATIONS.forEach(loc => {
-      const marker = L.marker([loc.lat, loc.lng], { icon: createMapIcon(loc.type) })
-        .bindPopup(buildMapPopup(loc), { maxWidth: 220 });
-      leafletMarkers.push({ marker, type: loc.type, id: loc.id });
-      marker.addTo(leafletMap);
-    });
+    startLocationWatch();
 
-    // 필터 버튼 이벤트
-    document.querySelectorAll(".map-filter-btn").forEach(btn => {
-      btn.addEventListener("click", () => {
-        document.querySelectorAll(".map-filter-btn").forEach(b => b.classList.remove("active"));
-        btn.classList.add("active");
-        applyMapFilter(btn.dataset.filter);
+    const locateCtrl = L.control({ position: "topright" });
+    locateCtrl.onAdd = function () {
+      const btn = L.DomUtil.create("button", "map-locate-btn");
+      btn.innerHTML = "📍";
+      btn.title = "내 위치";
+      L.DomEvent.on(btn, "click", () => {
+        if (locationDot) leafletMap.setView(locationDot.getLatLng(), 17);
+        requestOrientationPermission();
       });
-    });
-
-    // 현재 위치 버튼
-    L.control.locate = function(opts) {
-      const ctrl = L.control({ position: "topright" });
-      ctrl.onAdd = function() {
-        const btn = L.DomUtil.create("button", "map-locate-btn");
-        btn.innerHTML = "📍";
-        btn.title = "내 위치";
-        L.DomEvent.on(btn, "click", () => {
-          if (!navigator.geolocation) return;
-          navigator.geolocation.getCurrentPosition(pos => {
-            leafletMap.setView([pos.coords.latitude, pos.coords.longitude], 17);
-            L.circleMarker([pos.coords.latitude, pos.coords.longitude], {
-              radius: 8, color: "#2563eb", fillColor: "#2563eb", fillOpacity: 0.8, weight: 2
-            }).addTo(leafletMap).bindPopup("📍 현재 위치").openPopup();
-          }, () => alert("위치 정보를 가져올 수 없습니다."));
-        });
-        return btn;
-      };
-      return ctrl;
+      return btn;
     };
-    L.control.locate().addTo(leafletMap);
+    locateCtrl.addTo(leafletMap);
   }
 
-  // 탭이 보여진 후 지도 크기 재계산
   setTimeout(() => leafletMap.invalidateSize(), 120);
 }
 
+function startLocationWatch() {
+  if (!navigator.geolocation) return;
+
+  let firstFix = true;
+
+  navigator.geolocation.watchPosition(
+    (pos) => {
+      const { latitude: lat, longitude: lng, accuracy } = pos.coords;
+      const latlng = [lat, lng];
+
+      if (!locationDot) {
+        accuracyCircle = L.circle(latlng, {
+          radius: accuracy,
+          color: "#2563eb",
+          fillColor: "#2563eb",
+          fillOpacity: 0.08,
+          weight: 1,
+          interactive: false,
+        }).addTo(leafletMap);
+
+        locationDot = L.marker(latlng, {
+          icon: L.divIcon({
+            className: "map-location-icon",
+            html: `<svg viewBox="-16 -28 32 44" width="32" height="44" overflow="visible">
+              <path class="map-heading-cone" d="M0,-26 L-10,-6 L10,-6 Z"
+                fill="rgba(37,99,235,0.5)" stroke="none" display="none"/>
+              <circle cx="0" cy="0" r="8" fill="#2563eb" stroke="white" stroke-width="2.5"/>
+            </svg>`,
+            iconSize: [32, 44],
+            iconAnchor: [16, 28],
+          }),
+          interactive: false,
+          zIndexOffset: 100,
+        }).addTo(leafletMap);
+      } else {
+        locationDot.setLatLng(latlng);
+        accuracyCircle.setLatLng(latlng).setRadius(accuracy);
+      }
+
+      if (firstFix) {
+        leafletMap.setView(latlng, 17);
+        firstFix = false;
+      }
+    },
+    () => {},
+    { enableHighAccuracy: true, maximumAge: 5000 }
+  );
+
+  onOrientationHandler = function (e) {
+    const el = locationDot?.getElement();
+    if (!el) return;
+    let heading = null;
+    if (typeof e.webkitCompassHeading === "number") {
+      heading = e.webkitCompassHeading;
+    } else if (typeof e.alpha === "number") {
+      heading = (360 - e.alpha) % 360;
+    }
+    if (heading === null) return;
+    const svg = el.querySelector("svg");
+    const cone = el.querySelector(".map-heading-cone");
+    if (!svg || !cone) return;
+    cone.removeAttribute("display");
+    svg.style.transform = `rotate(${heading}deg)`;
+  };
+
+  // 비iOS는 즉시 등록
+  if (typeof DeviceOrientationEvent === "undefined" ||
+      typeof DeviceOrientationEvent.requestPermission !== "function") {
+    window.addEventListener("deviceorientationabsolute", onOrientationHandler, true);
+    window.addEventListener("deviceorientation", onOrientationHandler, true);
+    orientationListenerAdded = true;
+  }
+}
+
+function requestOrientationPermission() {
+  if (orientationListenerAdded) return;
+  if (typeof DeviceOrientationEvent === "undefined") return;
+  if (typeof DeviceOrientationEvent.requestPermission !== "function") return;
+  DeviceOrientationEvent.requestPermission()
+    .then(state => {
+      if (state === "granted" && onOrientationHandler) {
+        window.addEventListener("deviceorientation", onOrientationHandler);
+        orientationListenerAdded = true;
+      }
+    })
+    .catch(() => {});
+}
+
 // ─── 디테일 패널 HTML ───
 function buildDetailHtml(id, list, snucoData, gangyeoData) {
   // snuco 세부 식당
diff --git a/server/index.js b/server/index.js
index b942002..f9d69c6 100644
--- a/server/index.js
+++ b/server/index.js
@@ -5,8 +5,12 @@ const https = require("https");
 const webpush = require("web-push");
 
 // VAPID 설정
-const VAPID_PUBLIC = process.env.VAPID_PUBLIC || "BNHX2y_hSe3MDv1TelFE8LSK6Kg2DY8Aa7gFAjvX9OAIyJu72OerTOMA7PNW3dVf-6lM
9DNUFkI9FOoAh_TTZOg";
-const VAPID_PRIVATE = process.env.VAPID_PRIVATE || "zf1hxNgT-YzntEwS5CycYS9oynMTZeDIqmPlWUMrbU0";
+const VAPID_PUBLIC = process.env.VAPID_PUBLIC;
+const VAPID_PRIVATE = process.env.VAPID_PRIVATE;
+if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
+  console.error("환경변수 VAPID_PUBLIC, VAPID_PRIVATE가 설정되지 않았습니다.");
+  process.exit(1);
+}
 webpush.setVapidDetails("mailto:admin@snu-app.com", VAPID_PUBLIC, VAPID_PRIVATE);
 
 const app = express();
diff --git a/style.css b/style.css
index 1575c1d..a6f52dd 100644
--- a/style.css
+++ b/style.css
@@ -958,9 +958,10 @@ body.dark .rest-meal-tab.active {
   display: flex;
   flex-direction: column;
 }
+#mapTab.hidden { display: none; }
 
 .map-filter-bar {
-  display: flex;
+  display: none;
   gap: 8px;
   padding: 10px 16px;
   background: var(--app-bg);
@@ -1051,6 +1052,14 @@ body.dark .map-filter-btn.active { background: #2563eb; border-color: #2563eb; }
 /* 마커 아이콘 (divIcon) */
 .map-custom-icon { background: none; border: none; }
 
+/* 내 위치 마커 */
+.map-location-icon { background: none !important; border: none !important; }
+.map-location-icon svg {
+  transform-origin: 16px 28px;
+  transition: transform 0.25s ease;
+  overflow: visible;
+}
+
 /* 길찾기 버튼 (식당 디테일 패널) */
 .rest-nav-btn {
   display: inline-flex;

2026-05-12T15:16:29.501401Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command 'Get-Content -Path script.js | Select-Object -Skip 1120 -First 170 | ForEach-Object -Begin {$i=1
121} -Process {"$i`:$($_)"; $i++}'` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content -Path script.js | Select-Object 
-Skip 1120 -First 170 | ForEach-Object -Begin {$i=1121} -Process {"$i`:$($_)"; $i++}' in C:\Users\tom07\Desktop\snu 과제 
앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content -Path script.js | Select-Object
 -Skip 1120 -First 170 | ForEach-Object -Begin {$i=1121} -Process {"$i`:$($_)"; $i++}'` rejected: blocked by policy
2026-05-12T15:16:34.713499Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command "python - <<'PY'
from pathlib import Path
for i,line in enumerate(Path('script.js').read_text(encoding='utf-8').splitlines(),1):
    if 1120<=i<=1300:
        print(f'{i}:{line}')
PY"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "python - <<'PY'
from pathlib import Path
for i,line in enumerate(Path('script.js').read_text(encoding='utf-8').splitlines(),1):
    if 1120<=i<=1300:
        print(f'{i}:{line}')
PY" in C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "python - <<'PY'
from pathlib import Path
for i,line in enumerate(Path('script.js').read_text(encoding='utf-8').splitlines(),1):
    if 1120<=i<=1300:
        print(f'{i}:{line}')
PY"` rejected: blocked by policy
2026-05-12T15:16:39.908101Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command '$i=1; Get-Content script.js | ForEach-Object { if($i -ge 1120 -and $i -le 1300){ Write-Output (
$i.ToString()+'"':' + "'$_) }; $i++ }'` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command '$i=1; Get-Content script.js | ForEach-Object
 { if($i -ge 1120 -and $i -le 1300){ Write-Output ($i.ToString()+'"':' + "'$_) }; $i++ }' in C:\Users\tom07\Desktop\snu
 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command '$i=1; Get-Content script.js | ForEach-Objec
t { if($i -ge 1120 -and $i -le 1300){ Write-Output ($i.ToString()+'"':' + "'$_) }; $i++ }'` rejected: blocked by policy
2026-05-12T15:16:44.380752Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command 'Select-String -Path script.js -Pattern "function renderMapTab|function startLocationWatch|SNU_L
OCATIONS.forEach|map-filter-btn" -Context 3,8'` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Select-String -Path script.js -Pattern "func
tion renderMapTab|function startLocationWatch|SNU_LOCATIONS.forEach|map-filter-btn" -Context 3,8' in C:\Users\tom07\Des
ktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Select-String -Path script.js -Pattern "fun
ction renderMapTab|function startLocationWatch|SNU_LOCATIONS.forEach|map-filter-btn" -Context 3,8'` rejected: blocked b
y policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'findstr /n "renderMapTab startLocationWatch 
SNU_LOCATIONS map-filter-btn" script.js' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 688ms:
181:    if (tab === "map") renderMapTab();
1101:const SNU_LOCATIONS = [
1139:// 식당 id / name → SNU_LOCATIONS 매칭
1142:  const byRestId = SNU_LOCATIONS.find(l => l.restId === id);
1147:    return SNU_LOCATIONS.find(l =>
1208:function renderMapTab() {
1216:    startLocationWatch();
1235:function startLocationWatch() {

2026-05-12T15:16:54.525918Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command "python -c \"from pathlib import Path; lines=Path('script.js').read_text(encoding='utf-8').split
lines(); [print(f'{i+1}:{lines[i]}') for i in range(1198,1255)]\""` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "python -c \"from pathlib import Path; lines=
Path('script.js').read_text(encoding='utf-8').splitlines(); [print(f'{i+1}:{lines[i]}') for i in range(1198,1255)]\"" i
n C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "python -c \"from pathlib import Path; lines
=Path('script.js').read_text(encoding='utf-8').splitlines(); [print(f'{i+1}:{lines[i]}') for i in range(1198,1255)]\""`
 rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git diff --unified=0 -- script.js server/ind
ex.js style.css' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 802ms:
diff --git a/script.js b/script.js
index e436d70..4894f40 100644
--- a/script.js
+++ b/script.js
@@ -1159,0 +1160,6 @@ let activeMapFilter = "all";
+// 내 위치/방향 상태
+let locationDot = null;
+let accuracyCircle = null;
+let orientationListenerAdded = false;
+let onOrientationHandler = null;
+
@@ -1204 +1209,0 @@ function renderMapTab() {
-    // 지도 초기화 (캠퍼스 중심)
@@ -1211,7 +1216 @@ function renderMapTab() {
-    // 마커 추가
-    SNU_LOCATIONS.forEach(loc => {
-      const marker = L.marker([loc.lat, loc.lng], { icon: createMapIcon(loc.type) })
-        .bindPopup(buildMapPopup(loc), { maxWidth: 220 });
-      leafletMarkers.push({ marker, type: loc.type, id: loc.id });
-      marker.addTo(leafletMap);
-    });
+    startLocationWatch();
@@ -1219,6 +1218,8 @@ function renderMapTab() {
-    // 필터 버튼 이벤트
-    document.querySelectorAll(".map-filter-btn").forEach(btn => {
-      btn.addEventListener("click", () => {
-        document.querySelectorAll(".map-filter-btn").forEach(b => b.classList.remove("active"));
-        btn.classList.add("active");
-        applyMapFilter(btn.dataset.filter);
+    const locateCtrl = L.control({ position: "topright" });
+    locateCtrl.onAdd = function () {
+      const btn = L.DomUtil.create("button", "map-locate-btn");
+      btn.innerHTML = "📍";
+      btn.title = "내 위치";
+      L.DomEvent.on(btn, "click", () => {
+        if (locationDot) leafletMap.setView(locationDot.getLatLng(), 17);
+        requestOrientationPermission();
@@ -1226,21 +1227 @@ function renderMapTab() {
-    });
-
-    // 현재 위치 버튼
-    L.control.locate = function(opts) {
-      const ctrl = L.control({ position: "topright" });
-      ctrl.onAdd = function() {
-        const btn = L.DomUtil.create("button", "map-locate-btn");
-        btn.innerHTML = "📍";
-        btn.title = "내 위치";
-        L.DomEvent.on(btn, "click", () => {
-          if (!navigator.geolocation) return;
-          navigator.geolocation.getCurrentPosition(pos => {
-            leafletMap.setView([pos.coords.latitude, pos.coords.longitude], 17);
-            L.circleMarker([pos.coords.latitude, pos.coords.longitude], {
-              radius: 8, color: "#2563eb", fillColor: "#2563eb", fillOpacity: 0.8, weight: 2
-            }).addTo(leafletMap).bindPopup("📍 현재 위치").openPopup();
-          }, () => alert("위치 정보를 가져올 수 없습니다."));
-        });
-        return btn;
-      };
-      return ctrl;
+      return btn;
@@ -1248 +1229 @@ function renderMapTab() {
-    L.control.locate().addTo(leafletMap);
+    locateCtrl.addTo(leafletMap);
@@ -1251 +1231,0 @@ function renderMapTab() {
-  // 탭이 보여진 후 지도 크기 재계산
@@ -1254,0 +1235,88 @@ function renderMapTab() {
+function startLocationWatch() {
+  if (!navigator.geolocation) return;
+
+  let firstFix = true;
+
+  navigator.geolocation.watchPosition(
+    (pos) => {
+      const { latitude: lat, longitude: lng, accuracy } = pos.coords;
+      const latlng = [lat, lng];
+
+      if (!locationDot) {
+        accuracyCircle = L.circle(latlng, {
+          radius: accuracy,
+          color: "#2563eb",
+          fillColor: "#2563eb",
+          fillOpacity: 0.08,
+          weight: 1,
+          interactive: false,
+        }).addTo(leafletMap);
+
+        locationDot = L.marker(latlng, {
+          icon: L.divIcon({
+            className: "map-location-icon",
+            html: `<svg viewBox="-16 -28 32 44" width="32" height="44" overflow="visible">
+              <path class="map-heading-cone" d="M0,-26 L-10,-6 L10,-6 Z"
+                fill="rgba(37,99,235,0.5)" stroke="none" display="none"/>
+              <circle cx="0" cy="0" r="8" fill="#2563eb" stroke="white" stroke-width="2.5"/>
+            </svg>`,
+            iconSize: [32, 44],
+            iconAnchor: [16, 28],
+          }),
+          interactive: false,
+          zIndexOffset: 100,
+        }).addTo(leafletMap);
+      } else {
+        locationDot.setLatLng(latlng);
+        accuracyCircle.setLatLng(latlng).setRadius(accuracy);
+      }
+
+      if (firstFix) {
+        leafletMap.setView(latlng, 17);
+        firstFix = false;
+      }
+    },
+    () => {},
+    { enableHighAccuracy: true, maximumAge: 5000 }
+  );
+
+  onOrientationHandler = function (e) {
+    const el = locationDot?.getElement();
+    if (!el) return;
+    let heading = null;
+    if (typeof e.webkitCompassHeading === "number") {
+      heading = e.webkitCompassHeading;
+    } else if (typeof e.alpha === "number") {
+      heading = (360 - e.alpha) % 360;
+    }
+    if (heading === null) return;
+    const svg = el.querySelector("svg");
+    const cone = el.querySelector(".map-heading-cone");
+    if (!svg || !cone) return;
+    cone.removeAttribute("display");
+    svg.style.transform = `rotate(${heading}deg)`;
+  };
+
+  // 비iOS는 즉시 등록
+  if (typeof DeviceOrientationEvent === "undefined" ||
+      typeof DeviceOrientationEvent.requestPermission !== "function") {
+    window.addEventListener("deviceorientationabsolute", onOrientationHandler, true);
+    window.addEventListener("deviceorientation", onOrientationHandler, true);
+    orientationListenerAdded = true;
+  }
+}
+
+function requestOrientationPermission() {
+  if (orientationListenerAdded) return;
+  if (typeof DeviceOrientationEvent === "undefined") return;
+  if (typeof DeviceOrientationEvent.requestPermission !== "function") return;
+  DeviceOrientationEvent.requestPermission()
+    .then(state => {
+      if (state === "granted" && onOrientationHandler) {
+        window.addEventListener("deviceorientation", onOrientationHandler);
+        orientationListenerAdded = true;
+      }
+    })
+    .catch(() => {});
+}
+
diff --git a/server/index.js b/server/index.js
index b942002..f9d69c6 100644
--- a/server/index.js
+++ b/server/index.js
@@ -8,2 +8,6 @@ const webpush = require("web-push");
-const VAPID_PUBLIC = process.env.VAPID_PUBLIC || "BNHX2y_hSe3MDv1TelFE8LSK6Kg2DY8Aa7gFAjvX9OAIyJu72OerTOMA7PNW3dVf-6lM
9DNUFkI9FOoAh_TTZOg";
-const VAPID_PRIVATE = process.env.VAPID_PRIVATE || "zf1hxNgT-YzntEwS5CycYS9oynMTZeDIqmPlWUMrbU0";
+const VAPID_PUBLIC = process.env.VAPID_PUBLIC;
+const VAPID_PRIVATE = process.env.VAPID_PRIVATE;
+if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
+  console.error("환경변수 VAPID_PUBLIC, VAPID_PRIVATE가 설정되지 않았습니다.");
+  process.exit(1);
+}
diff --git a/style.css b/style.css
index 1575c1d..a6f52dd 100644
--- a/style.css
+++ b/style.css
@@ -960,0 +961 @@ body.dark .rest-meal-tab.active {
+#mapTab.hidden { display: none; }
@@ -963 +964 @@ body.dark .rest-meal-tab.active {
-  display: flex;
+  display: none;
@@ -1053,0 +1055,8 @@ body.dark .map-filter-btn.active { background: #2563eb; border-color: #2563eb; }
+/* 내 위치 마커 */
+.map-location-icon { background: none !important; border: none !important; }
+.map-location-icon svg {
+  transform-origin: 16px 28px;
+  transition: transform 0.25s ease;
+  overflow: visible;
+}
+

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'type PLAN.md' in C:\Users\tom07\Desktop\snu 
과제 앱
 succeeded in 872ms:
# 吏????媛쒗렪 怨꾪쉷

## 臾댁뾿?? ??- 湲곗〈 留덉빱(?앸떦/移댄럹/嫄대Ъ) ?꾨? ?④?
- ???꾩튂 ?쒖떆 (?뚮? ??
- ???몃뱶?곗씠 諛붾씪蹂대뒗 諛⑺뼢 ?쒖떆 (諛⑺뼢 ?쇨컖???ㅻ쾭?덉씠)

## ?묎렐踰?
### 1. 湲곗〈 留덉빱 ?쒓굅
- `SNU_LOCATIONS` ?곗씠?곗? `leafletMarkers` 諛곗뿴? ?좎? (?꾪꽣 踰꾪듉 濡쒖쭅 ?ъ궗??媛?μ꽦)
- ?? `renderMapTab()`?먯꽌 留덉빱瑜?吏?꾩뿉 異붽??섎뒗 肄붾뱶 ?쒓굅
- ?꾪꽣 踰꾪듉 諛붾룄 ?④퍡 ?④? (留덉빱媛 ?놁쑝誘濡??섎? ?놁쓬)

### 2. ???꾩튂 ?쒖떆
- `navigator.geolocation.watchPosition()` ?쇰줈 ?ㅼ떆媛??꾩튂 異붿쟻
- Leaflet `L.circleMarker` 濡??뚮? ???쒖떆
- ?꾩튂 媛깆떊 ??留덉빱 醫뚰몴 ?낅뜲?댄듃 (留ㅻ쾲 ?덈줈 ?앹꽦?섏? ?딄퀬 `setLatLng`)
- 吏??泥?吏꾩엯 ???먮룞?쇰줈 ???꾩튂濡??대룞 (`setView`)

### 3. 諛⑺뼢(Heading) ?쒖떆
- `DeviceOrientationEvent` API ?ъ슜
  - iOS 13+: `DeviceOrientationEvent.requestPermission()` ?꾩슂
  - Android/湲고?: 蹂꾨룄 沅뚰븳 ?놁씠 `window.addEventListener('deviceorientation', ...)`
- `event.alpha` (?섏묠諛?諛⑺뼢, 0~360째) 媛믪쑝濡??쇨컖???뚯쟾
- ?꾩튂 留덉빱 ?꾩뿉 `L.divIcon`?쇰줈 諛⑺뼢 ?쇨컖???ㅻ쾭?덉씠 (`L.marker` + CSS transform rotate)
- heading 媛??놁쑝硫??곗뒪?ы넲 ?? ?쇨컖???④?

### 4. UI
- ?꾪꽣 諛??쒓굅 (`.map-filter-bar` hidden 泥섎━)
- ?꾩옱 ?꾩튂 踰꾪듉(?뱧)? ?좎? ???대┃ ?????꾩튂濡?吏???대룞

## 蹂寃??뚯씪
- `script.js`: renderMapTab(), SNU_LOCATIONS 留덉빱 異붽? 肄붾뱶 ?쒓굅, watchPosition + deviceorientation 濡쒖쭅 異붽?
- `style.css`: 諛⑺뼢 ?쇨컖??divIcon ?ㅽ???異붽?, ?꾪꽣 諛??④?
- `index.html`: ?꾪꽣 諛?踰꾪듉 ?쒓굅 ?먮뒗 hidden

## ?깃났 湲곗?
- [ ] 吏????吏꾩엯 ??湲곗〈 留덉빱(?앸떦/移댄럹/嫄대Ъ) ??蹂댁엫
- [ ] 吏????吏꾩엯 ???먮룞?쇰줈 ???꾩튂濡??대룞
- [ ] ?뚮? ?먯쑝濡????꾩튂 ?쒖떆
- [ ] ?몃뱶??諛⑺뼢???곕씪 ?쇨컖?뺤씠 ?뚯쟾
- [ ] ?곗뒪?ы넲?먯꽌???쇨컖???놁씠 ?뚮? ?먮쭔 ?쒖떆
- [ ] iOS?먯꽌 沅뚰븳 ?붿껌 ?뺤긽 ?숈옉

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /i \"VAPID vapid applicationServe
rKey\" *.js server\\*.js index.html" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 678ms:
script.js:919:    const keyRes = await fetch(`${SERVER_URL}/api/push/vapid-public-key`);
script.js:924:      applicationServerKey: urlBase64ToUint8Array(key),
server\index.js:7:// VAPID 설정
server\index.js:8:const VAPID_PUBLIC = process.env.VAPID_PUBLIC;
server\index.js:9:const VAPID_PRIVATE = process.env.VAPID_PRIVATE;
server\index.js:10:if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
server\index.js:11:  console.error("환경변수 VAPID_PUBLIC, VAPID_PRIVATE가 설정되지 않았습니다.");
server\index.js:14:webpush.setVapidDetails("mailto:admin@snu-app.com", VAPID_PUBLIC, VAPID_PRIVATE);
server\index.js:341:app.get("/api/push/vapid-public-key", (req, res) => {
server\index.js:342:  res.json({ key: VAPID_PUBLIC });

2026-05-12T15:17:26.324472Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command "dir /b & if exist package.json type package.json & if exist server\\package.json type server\\p
ackage.json"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "dir /b & if exist package.json type package.
json & if exist server\\package.json type server\\package.json" in C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "dir /b & if exist package.json type package
.json & if exist server\\package.json type server\\package.json"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-ChildItem -Name' in C:\Users\tom07\Deskt
op\snu 과제 앱
 succeeded in 951ms:
server
.gitignore
app.webmanifest
CODEX_CODE_REVIEW.md
CODEX_REVIEW.md
icon-192.png
icon-512.png
index.html
LICENSE
PLAN.md
PLAN_REVIEW.md
README.md
script.js
style.css
sw.js

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "Get-ChildItem -Name server; type server\\pac
kage.json" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 773ms:
node_modules
id_tab.png
id_tab_clicked.png
index.js
login_flow.png
login_page.png
login_stealth.png
main_page.png
package-lock.json
package.json
{
  "name": "snu-assignment-server",
  "version": "1.0.0",
  "description": "SNU eTL 怨쇱젣 ?뚮┝ ???꾨줉???쒕쾭",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "cheerio": "^1.2.0",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "node-ical": "^0.26.1",
    "web-push": "^3.6.7"
  }
}

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /i \"VAPID npm start start server
\" README.md server\\package.json" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 679ms:
server\package.json:2:  "name": "snu-assignment-server",
server\package.json:7:    "start": "node index.js"

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git diff --name-only; git status --short' in
 C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 969ms:
script.js
server/index.js
style.css
 M script.js
 M server/index.js
 M style.css
?? CODEX_CODE_REVIEW.md
?? CODEX_REVIEW.md
?? PLAN.md
?? PLAN_REVIEW.md

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git show HEAD:script.js | findstr /n /c:"fun
ction renderMapTab" /c:"SNU_LOCATIONS.forEach" /c:"L.control.locate"' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 1107ms:
1202:function renderMapTab() {
1212:    SNU_LOCATIONS.forEach(loc => {
1229:    L.control.locate = function(opts) {
1248:    L.control.locate().addTo(leafletMap);

2026-05-12T15:17:57.043523Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command "node --check script.js; node --check server\\index.js"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "node --check script.js; node --check server\
\index.js" in C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "node --check script.js; node --check server
\\index.js"` rejected: blocked by policy
2026-05-12T15:17:59.704227Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command 'node --check script.js'` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'node --check script.js' in C:\Users\tom07\De
sktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'node --check script.js'` rejected: blocked 
by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'type .gitignore' in C:\Users\tom07\Desktop\s
nu 과제 앱
 succeeded in 823ms:
node_modules/
server/node_modules/
.env
*.log

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'type CODEX_CODE_REVIEW.md' in C:\Users\tom07
\Desktop\snu 과제 앱
 succeeded in 863ms:
node.exe : OpenAI Codex v0.130.0
At C:\Users\tom07\AppData\Roaming\npm\codex.ps1:24 char:5
+     & "node$exe"  "$basedir/node_modules/@openai/codex/bin/codex.js"  ...
+     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (OpenAI Codex v0.130.0:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 
--------
workdir: C:\Users\tom07\Desktop\snu 과제 앱
model: gpt-5.5
provider: openai
approval: never
sandbox: read-only
reasoning effort: medium
reasoning summaries: none
session id: 019e1cc2-92c7-75e3-b19b-d9e03f37bb40
--------
user
current changes
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git status --short' in C:\Users\tom07\Deskto
p\snu 과제 앱
 succeeded in 815ms:
 M script.js
 M server/index.js
 M style.css
?? CODEX_CODE_REVIEW.md
?? CODEX_REVIEW.md
?? PLAN.md
?? PLAN_REVIEW.md

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git diff -- script.js server/index.js style.
css; git diff --cached -- script.js server/index.js style.css' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 953ms:
diff --git a/script.js b/script.js
index e436d70..4894f40 100644
--- a/script.js
+++ b/script.js
@@ -1157,6 +1157,12 @@ let leafletMap = null;
 let leafletMarkers = [];
 let activeMapFilter = "all";
 
+// 내 위치/방향 상태
+let locationDot = null;
+let accuracyCircle = null;
+let orientationListenerAdded = false;
+let onOrientationHandler = null;
+
 // 타입별 마커 색상
 const MAP_COLORS = { restaurant: "#ef4444", cafe: "#f59e0b", building: "#3b82f6" };
 
@@ -1201,57 +1207,119 @@ function applyMapFilter(filter) {
 
 function renderMapTab() {
   if (!leafletMap) {
-    // 지도 초기화 (캠퍼스 중심)
     leafletMap = L.map("mapContainer", { zoomControl: true }).setView([37.4651, 126.9507], 15);
     L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
       attribution: "© <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a>",
       maxZoom: 19,
     }).addTo(leafletMap);
 
-    // 마커 추가
-    SNU_LOCATIONS.forEach(loc => {
-      const marker = L.marker([loc.lat, loc.lng], { icon: createMapIcon(loc.type) })
-        .bindPopup(buildMapPopup(loc), { maxWidth: 220 });
-      leafletMarkers.push({ marker, type: loc.type, id: loc.id });
-      marker.addTo(leafletMap);
-    });
+    startLocationWatch();
 
-    // 필터 버튼 이벤트
-    document.querySelectorAll(".map-filter-btn").forEach(btn => {
-      btn.addEventListener("click", () => {
-        document.querySelectorAll(".map-filter-btn").forEach(b => b.classList.remove("active"));
-        btn.classList.add("active");
-        applyMapFilter(btn.dataset.filter);
+    const locateCtrl = L.control({ position: "topright" });
+    locateCtrl.onAdd = function () {
+      const btn = L.DomUtil.create("button", "map-locate-btn");
+      btn.innerHTML = "📍";
+      btn.title = "내 위치";
+      L.DomEvent.on(btn, "click", () => {
+        if (locationDot) leafletMap.setView(locationDot.getLatLng(), 17);
+        requestOrientationPermission();
       });
-    });
-
-    // 현재 위치 버튼
-    L.control.locate = function(opts) {
-      const ctrl = L.control({ position: "topright" });
-      ctrl.onAdd = function() {
-        const btn = L.DomUtil.create("button", "map-locate-btn");
-        btn.innerHTML = "📍";
-        btn.title = "내 위치";
-        L.DomEvent.on(btn, "click", () => {
-          if (!navigator.geolocation) return;
-          navigator.geolocation.getCurrentPosition(pos => {
-            leafletMap.setView([pos.coords.latitude, pos.coords.longitude], 17);
-            L.circleMarker([pos.coords.latitude, pos.coords.longitude], {
-              radius: 8, color: "#2563eb", fillColor: "#2563eb", fillOpacity: 0.8, weight: 2
-            }).addTo(leafletMap).bindPopup("📍 현재 위치").openPopup();
-          }, () => alert("위치 정보를 가져올 수 없습니다."));
-        });
-        return btn;
-      };
-      return ctrl;
+      return btn;
     };
-    L.control.locate().addTo(leafletMap);
+    locateCtrl.addTo(leafletMap);
   }
 
-  // 탭이 보여진 후 지도 크기 재계산
   setTimeout(() => leafletMap.invalidateSize(), 120);
 }
 
+function startLocationWatch() {
+  if (!navigator.geolocation) return;
+
+  let firstFix = true;
+
+  navigator.geolocation.watchPosition(
+    (pos) => {
+      const { latitude: lat, longitude: lng, accuracy } = pos.coords;
+      const latlng = [lat, lng];
+
+      if (!locationDot) {
+        accuracyCircle = L.circle(latlng, {
+          radius: accuracy,
+          color: "#2563eb",
+          fillColor: "#2563eb",
+          fillOpacity: 0.08,
+          weight: 1,
+          interactive: false,
+        }).addTo(leafletMap);
+
+        locationDot = L.marker(latlng, {
+          icon: L.divIcon({
+            className: "map-location-icon",
+            html: `<svg viewBox="-16 -28 32 44" width="32" height="44" overflow="visible">
+              <path class="map-heading-cone" d="M0,-26 L-10,-6 L10,-6 Z"
+                fill="rgba(37,99,235,0.5)" stroke="none" display="none"/>
+              <circle cx="0" cy="0" r="8" fill="#2563eb" stroke="white" stroke-width="2.5"/>
+            </svg>`,
+            iconSize: [32, 44],
+            iconAnchor: [16, 28],
+          }),
+          interactive: false,
+          zIndexOffset: 100,
+        }).addTo(leafletMap);
+      } else {
+        locationDot.setLatLng(latlng);
+        accuracyCircle.setLatLng(latlng).setRadius(accuracy);
+      }
+
+      if (firstFix) {
+        leafletMap.setView(latlng, 17);
+        firstFix = false;
+      }
+    },
+    () => {},
+    { enableHighAccuracy: true, maximumAge: 5000 }
+  );
+
+  onOrientationHandler = function (e) {
+    const el = locationDot?.getElement();
+    if (!el) return;
+    let heading = null;
+    if (typeof e.webkitCompassHeading === "number") {
+      heading = e.webkitCompassHeading;
+    } else if (typeof e.alpha === "number") {
+      heading = (360 - e.alpha) % 360;
+    }
+    if (heading === null) return;
+    const svg = el.querySelector("svg");
+    const cone = el.querySelector(".map-heading-cone");
+    if (!svg || !cone) return;
+    cone.removeAttribute("display");
+    svg.style.transform = `rotate(${heading}deg)`;
+  };
+
+  // 비iOS는 즉시 등록
+  if (typeof DeviceOrientationEvent === "undefined" ||
+      typeof DeviceOrientationEvent.requestPermission !== "function") {
+    window.addEventListener("deviceorientationabsolute", onOrientationHandler, true);
+    window.addEventListener("deviceorientation", onOrientationHandler, true);
+    orientationListenerAdded = true;
+  }
+}
+
+function requestOrientationPermission() {
+  if (orientationListenerAdded) return;
+  if (typeof DeviceOrientationEvent === "undefined") return;
+  if (typeof DeviceOrientationEvent.requestPermission !== "function") return;
+  DeviceOrientationEvent.requestPermission()
+    .then(state => {
+      if (state === "granted" && onOrientationHandler) {
+        window.addEventListener("deviceorientation", onOrientationHandler);
+        orientationListenerAdded = true;
+      }
+    })
+    .catch(() => {});
+}
+
 // ─── 디테일 패널 HTML ───
 function buildDetailHtml(id, list, snucoData, gangyeoData) {
   // snuco 세부 식당
diff --git a/server/index.js b/server/index.js
index b942002..f9d69c6 100644
--- a/server/index.js
+++ b/server/index.js
@@ -5,8 +5,12 @@ const https = require("https");
 const webpush = require("web-push");
 
 // VAPID 설정
-const VAPID_PUBLIC = process.env.VAPID_PUBLIC || "BNHX2y_hSe3MDv1TelFE8LSK6Kg2DY8Aa7gFAjvX9OAIyJu72OerTOMA7PNW3dVf-6lM
9DNUFkI9FOoAh_TTZOg";
-const VAPID_PRIVATE = process.env.VAPID_PRIVATE || "zf1hxNgT-YzntEwS5CycYS9oynMTZeDIqmPlWUMrbU0";
+const VAPID_PUBLIC = process.env.VAPID_PUBLIC;
+const VAPID_PRIVATE = process.env.VAPID_PRIVATE;
+if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
+  console.error("환경변수 VAPID_PUBLIC, VAPID_PRIVATE가 설정되지 않았습니다.");
+  process.exit(1);
+}
 webpush.setVapidDetails("mailto:admin@snu-app.com", VAPID_PUBLIC, VAPID_PRIVATE);
 
 const app = express();
diff --git a/style.css b/style.css
index 1575c1d..a6f52dd 100644
--- a/style.css
+++ b/style.css
@@ -958,9 +958,10 @@ body.dark .rest-meal-tab.active {
   display: flex;
   flex-direction: column;
 }
+#mapTab.hidden { display: none; }
 
 .map-filter-bar {
-  display: flex;
+  display: none;
   gap: 8px;
   padding: 10px 16px;
   background: var(--app-bg);
@@ -1051,6 +1052,14 @@ body.dark .map-filter-btn.active { background: #2563eb; border-color: #2563eb; }
 /* 마커 아이콘 (divIcon) */
 .map-custom-icon { background: none; border: none; }
 
+/* 내 위치 마커 */
+.map-location-icon { background: none !important; border: none !important; }
+.map-location-icon svg {
+  transform-origin: 16px 28px;
+  transition: transform 0.25s ease;
+  overflow: visible;
+}
+
 /* 길찾기 버튼 (식당 디테일 패널) */
 .rest-nav-btn {
   display: inline-flex;

2026-05-12T15:16:29.501401Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command 'Get-Content -Path script.js | Select-Object -Skip 1120 -First 170 | ForEach-Object -Begin {$i=1
121} -Process {"$i`:$($_)"; $i++}'` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content -Path script.js | Select-Object 
-Skip 1120 -First 170 | ForEach-Object -Begin {$i=1121} -Process {"$i`:$($_)"; $i++}' in C:\Users\tom07\Desktop\snu 과제 
앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content -Path script.js | Select-Object
 -Skip 1120 -First 170 | ForEach-Object -Begin {$i=1121} -Process {"$i`:$($_)"; $i++}'` rejected: blocked by policy
2026-05-12T15:16:34.713499Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command "python - <<'PY'
from pathlib import Path
for i,line in enumerate(Path('script.js').read_text(encoding='utf-8').splitlines(),1):
    if 1120<=i<=1300:
        print(f'{i}:{line}')
PY"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "python - <<'PY'
from pathlib import Path
for i,line in enumerate(Path('script.js').read_text(encoding='utf-8').splitlines(),1):
    if 1120<=i<=1300:
        print(f'{i}:{line}')
PY" in C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "python - <<'PY'
from pathlib import Path
for i,line in enumerate(Path('script.js').read_text(encoding='utf-8').splitlines(),1):
    if 1120<=i<=1300:
        print(f'{i}:{line}')
PY"` rejected: blocked by policy
2026-05-12T15:16:39.908101Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command '$i=1; Get-Content script.js | ForEach-Object { if($i -ge 1120 -and $i -le 1300){ Write-Output (
$i.ToString()+'"':' + "'$_) }; $i++ }'` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command '$i=1; Get-Content script.js | ForEach-Object
 { if($i -ge 1120 -and $i -le 1300){ Write-Output ($i.ToString()+'"':' + "'$_) }; $i++ }' in C:\Users\tom07\Desktop\snu
 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command '$i=1; Get-Content script.js | ForEach-Objec
t { if($i -ge 1120 -and $i -le 1300){ Write-Output ($i.ToString()+'"':' + "'$_) }; $i++ }'` rejected: blocked by policy
2026-05-12T15:16:44.380752Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command 'Select-String -Path script.js -Pattern "function renderMapTab|function startLocationWatch|SNU_L
OCATIONS.forEach|map-filter-btn" -Context 3,8'` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Select-String -Path script.js -Pattern "func
tion renderMapTab|function startLocationWatch|SNU_LOCATIONS.forEach|map-filter-btn" -Context 3,8' in C:\Users\tom07\Des
ktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Select-String -Path script.js -Pattern "fun
ction renderMapTab|function startLocationWatch|SNU_LOCATIONS.forEach|map-filter-btn" -Context 3,8'` rejected: blocked b
y policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'findstr /n "renderMapTab startLocationWatch 
SNU_LOCATIONS map-filter-btn" script.js' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 688ms:
181:    if (tab === "map") renderMapTab();
1101:const SNU_LOCATIONS = [
1139:// 식당 id / name → SNU_LOCATIONS 매칭
1142:  const byRestId = SNU_LOCATIONS.find(l => l.restId === id);
1147:    return SNU_LOCATIONS.find(l =>
1208:function renderMapTab() {
1216:    startLocationWatch();
1235:function startLocationWatch() {

2026-05-12T15:16:54.525918Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command "python -c \"from pathlib import Path; lines=Path('script.js').read_text(encoding='utf-8').split
lines(); [print(f'{i+1}:{lines[i]}') for i in range(1198,1255)]\""` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "python -c \"from pathlib import Path; lines=
Path('script.js').read_text(encoding='utf-8').splitlines(); [print(f'{i+1}:{lines[i]}') for i in range(1198,1255)]\"" i
n C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "python -c \"from pathlib import Path; lines
=Path('script.js').read_text(encoding='utf-8').splitlines(); [print(f'{i+1}:{lines[i]}') for i in range(1198,1255)]\""`
 rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git diff --unified=0 -- script.js server/ind
ex.js style.css' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 802ms:
diff --git a/script.js b/script.js
index e436d70..4894f40 100644
--- a/script.js
+++ b/script.js
@@ -1159,0 +1160,6 @@ let activeMapFilter = "all";
+// 내 위치/방향 상태
+let locationDot = null;
+let accuracyCircle = null;
+let orientationListenerAdded = false;
+let onOrientationHandler = null;
+
@@ -1204 +1209,0 @@ function renderMapTab() {
-    // 지도 초기화 (캠퍼스 중심)
@@ -1211,7 +1216 @@ function renderMapTab() {
-    // 마커 추가
-    SNU_LOCATIONS.forEach(loc => {
-      const marker = L.marker([loc.lat, loc.lng], { icon: createMapIcon(loc.type) })
-        .bindPopup(buildMapPopup(loc), { maxWidth: 220 });
-      leafletMarkers.push({ marker, type: loc.type, id: loc.id });
-      marker.addTo(leafletMap);
-    });
+    startLocationWatch();
@@ -1219,6 +1218,8 @@ function renderMapTab() {
-    // 필터 버튼 이벤트
-    document.querySelectorAll(".map-filter-btn").forEach(btn => {
-      btn.addEventListener("click", () => {
-        document.querySelectorAll(".map-filter-btn").forEach(b => b.classList.remove("active"));
-        btn.classList.add("active");
-        applyMapFilter(btn.dataset.filter);
+    const locateCtrl = L.control({ position: "topright" });
+    locateCtrl.onAdd = function () {
+      const btn = L.DomUtil.create("button", "map-locate-btn");
+      btn.innerHTML = "📍";
+      btn.title = "내 위치";
+      L.DomEvent.on(btn, "click", () => {
+        if (locationDot) leafletMap.setView(locationDot.getLatLng(), 17);
+        requestOrientationPermission();
@@ -1226,21 +1227 @@ function renderMapTab() {
-    });
-
-    // 현재 위치 버튼
-    L.control.locate = function(opts) {
-      const ctrl = L.control({ position: "topright" });
-      ctrl.onAdd = function() {
-        const btn = L.DomUtil.create("button", "map-locate-btn");
-        btn.innerHTML = "📍";
-        btn.title = "내 위치";
-        L.DomEvent.on(btn, "click", () => {
-          if (!navigator.geolocation) return;
-          navigator.geolocation.getCurrentPosition(pos => {
-            leafletMap.setView([pos.coords.latitude, pos.coords.longitude], 17);
-            L.circleMarker([pos.coords.latitude, pos.coords.longitude], {
-              radius: 8, color: "#2563eb", fillColor: "#2563eb", fillOpacity: 0.8, weight: 2
-            }).addTo(leafletMap).bindPopup("📍 현재 위치").openPopup();
-          }, () => alert("위치 정보를 가져올 수 없습니다."));
-        });
-        return btn;
-      };
-      return ctrl;
+      return btn;
@@ -1248 +1229 @@ function renderMapTab() {
-    L.control.locate().addTo(leafletMap);
+    locateCtrl.addTo(leafletMap);
@@ -1251 +1231,0 @@ function renderMapTab() {
-  // 탭이 보여진 후 지도 크기 재계산
@@ -1254,0 +1235,88 @@ function renderMapTab() {
+function startLocationWatch() {
+  if (!navigator.geolocation) return;
+
+  let firstFix = true;
+
+  navigator.geolocation.watchPosition(
+    (pos) => {
+      const { latitude: lat, longitude: lng, accuracy } = pos.coords;
+      const latlng = [lat, lng];
+
+      if (!locationDot) {
+        accuracyCircle = L.circle(latlng, {
+          radius: accuracy,
+          color: "#2563eb",
+          fillColor: "#2563eb",
+          fillOpacity: 0.08,
+          weight: 1,
+          interactive: false,
+        }).addTo(leafletMap);
+
+        locationDot = L.marker(latlng, {
+          icon: L.divIcon({
+            className: "map-location-icon",
+            html: `<svg viewBox="-16 -28 32 44" width="32" height="44" overflow="visible">
+              <path class="map-heading-cone" d="M0,-26 L-10,-6 L10,-6 Z"
+                fill="rgba(37,99,235,0.5)" stroke="none" display="none"/>
+              <circle cx="0" cy="0" r="8" fill="#2563eb" stroke="white" stroke-width="2.5"/>
+            </svg>`,
+            iconSize: [32, 44],
+            iconAnchor: [16, 28],
+          }),
+          interactive: false,
+          zIndexOffset: 100,
+        }).addTo(leafletMap);
+      } else {
+        locationDot.setLatLng(latlng);
+        accuracyCircle.setLatLng(latlng).setRadius(accuracy);
+      }
+
+      if (firstFix) {
+        leafletMap.setView(latlng, 17);
+        firstFix = false;
+      }
+    },
+    () => {},
+    { enableHighAccuracy: true, maximumAge: 5000 }
+  );
+
+  onOrientationHandler = function (e) {
+    const el = locationDot?.getElement();
+    if (!el) return;
+    let heading = null;
+    if (typeof e.webkitCompassHeading === "number") {
+      heading = e.webkitCompassHeading;
+    } else if (typeof e.alpha === "number") {
+      heading = (360 - e.alpha) % 360;
+    }
+    if (heading === null) return;
+    const svg = el.querySelector("svg");
+    const cone = el.querySelector(".map-heading-cone");
+    if (!svg || !cone) return;
+    cone.removeAttribute("display");
+    svg.style.transform = `rotate(${heading}deg)`;
+  };
+
+  // 비iOS는 즉시 등록
+  if (typeof DeviceOrientationEvent === "undefined" ||
+      typeof DeviceOrientationEvent.requestPermission !== "function") {
+    window.addEventListener("deviceorientationabsolute", onOrientationHandler, true);
+    window.addEventListener("deviceorientation", onOrientationHandler, true);
+    orientationListenerAdded = true;
+  }
+}
+
+function requestOrientationPermission() {
+  if (orientationListenerAdded) return;
+  if (typeof DeviceOrientationEvent === "undefined") return;
+  if (typeof DeviceOrientationEvent.requestPermission !== "function") return;
+  DeviceOrientationEvent.requestPermission()
+    .then(state => {
+      if (state === "granted" && onOrientationHandler) {
+        window.addEventListener("deviceorientation", onOrientationHandler);
+        orientationListenerAdded = true;
+      }
+    })
+    .catch(() => {});
+}
+
diff --git a/server/index.js b/server/index.js
index b942002..f9d69c6 100644
--- a/server/index.js
+++ b/server/index.js
@@ -8,2 +8,6 @@ const webpush = require("web-push");
-const VAPID_PUBLIC = process.env.VAPID_PUBLIC || "BNHX2y_hSe3MDv1TelFE8LSK6Kg2DY8Aa7gFAjvX9OAIyJu72OerTOMA7PNW3dVf-6lM
9DNUFkI9FOoAh_TTZOg";
-const VAPID_PRIVATE = process.env.VAPID_PRIVATE || "zf1hxNgT-YzntEwS5CycYS9oynMTZeDIqmPlWUMrbU0";
+const VAPID_PUBLIC = process.env.VAPID_PUBLIC;
+const VAPID_PRIVATE = process.env.VAPID_PRIVATE;
+if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
+  console.error("환경변수 VAPID_PUBLIC, VAPID_PRIVATE가 설정되지 않았습니다.");
+  process.exit(1);
+}
diff --git a/style.css b/style.css
index 1575c1d..a6f52dd 100644
--- a/style.css
+++ b/style.css
@@ -960,0 +961 @@ body.dark .rest-meal-tab.active {
+#mapTab.hidden { display: none; }
@@ -963 +964 @@ body.dark .rest-meal-tab.active {
-  display: flex;
+  display: none;
@@ -1053,0 +1055,8 @@ body.dark .map-filter-btn.active { background: #2563eb; border-color: #2563eb; }
+/* 내 위치 마커 */
+.map-location-icon { background: none !important; border: none !important; }
+.map-location-icon svg {
+  transform-origin: 16px 28px;
+  transition: transform 0.25s ease;
+  overflow: visible;
+}
+

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'type PLAN.md' in C:\Users\tom07\Desktop\snu 
과제 앱
 succeeded in 872ms:
# 吏????媛쒗렪 怨꾪쉷

## 臾댁뾿?? ??- 湲곗〈 留덉빱(?앸떦/移댄럹/嫄대Ъ) ?꾨? ?④?
- ???꾩튂 ?쒖떆 (?뚮? ??
- ???몃뱶?곗씠 諛붾씪蹂대뒗 諛⑺뼢 ?쒖떆 (諛⑺뼢 ?쇨컖???ㅻ쾭?덉씠)

## ?묎렐踰?
### 1. 湲곗〈 留덉빱 ?쒓굅
- `SNU_LOCATIONS` ?곗씠?곗? `leafletMarkers` 諛곗뿴? ?좎? (?꾪꽣 踰꾪듉 濡쒖쭅 ?ъ궗??媛?μ꽦)
- ?? `renderMapTab()`?먯꽌 留덉빱瑜?吏?꾩뿉 異붽??섎뒗 肄붾뱶 ?쒓굅
- ?꾪꽣 踰꾪듉 諛붾룄 ?④퍡 ?④? (留덉빱媛 ?놁쑝誘濡??섎? ?놁쓬)

### 2. ???꾩튂 ?쒖떆
- `navigator.geolocation.watchPosition()` ?쇰줈 ?ㅼ떆媛??꾩튂 異붿쟻
- Leaflet `L.circleMarker` 濡??뚮? ???쒖떆
- ?꾩튂 媛깆떊 ??留덉빱 醫뚰몴 ?낅뜲?댄듃 (留ㅻ쾲 ?덈줈 ?앹꽦?섏? ?딄퀬 `setLatLng`)
- 吏??泥?吏꾩엯 ???먮룞?쇰줈 ???꾩튂濡??대룞 (`setView`)

### 3. 諛⑺뼢(Heading) ?쒖떆
- `DeviceOrientationEvent` API ?ъ슜
  - iOS 13+: `DeviceOrientationEvent.requestPermission()` ?꾩슂
  - Android/湲고?: 蹂꾨룄 沅뚰븳 ?놁씠 `window.addEventListener('deviceorientation', ...)`
- `event.alpha` (?섏묠諛?諛⑺뼢, 0~360째) 媛믪쑝濡??쇨컖???뚯쟾
- ?꾩튂 留덉빱 ?꾩뿉 `L.divIcon`?쇰줈 諛⑺뼢 ?쇨컖???ㅻ쾭?덉씠 (`L.marker` + CSS transform rotate)
- heading 媛??놁쑝硫??곗뒪?ы넲 ?? ?쇨컖???④?

### 4. UI
- ?꾪꽣 諛??쒓굅 (`.map-filter-bar` hidden 泥섎━)
- ?꾩옱 ?꾩튂 踰꾪듉(?뱧)? ?좎? ???대┃ ?????꾩튂濡?吏???대룞

## 蹂寃??뚯씪
- `script.js`: renderMapTab(), SNU_LOCATIONS 留덉빱 異붽? 肄붾뱶 ?쒓굅, watchPosition + deviceorientation 濡쒖쭅 異붽?
- `style.css`: 諛⑺뼢 ?쇨컖??divIcon ?ㅽ???異붽?, ?꾪꽣 諛??④?
- `index.html`: ?꾪꽣 諛?踰꾪듉 ?쒓굅 ?먮뒗 hidden

## ?깃났 湲곗?
- [ ] 吏????吏꾩엯 ??湲곗〈 留덉빱(?앸떦/移댄럹/嫄대Ъ) ??蹂댁엫
- [ ] 吏????吏꾩엯 ???먮룞?쇰줈 ???꾩튂濡??대룞
- [ ] ?뚮? ?먯쑝濡????꾩튂 ?쒖떆
- [ ] ?몃뱶??諛⑺뼢???곕씪 ?쇨컖?뺤씠 ?뚯쟾
- [ ] ?곗뒪?ы넲?먯꽌???쇨컖???놁씠 ?뚮? ?먮쭔 ?쒖떆
- [ ] iOS?먯꽌 沅뚰븳 ?붿껌 ?뺤긽 ?숈옉

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /i \"VAPID vapid applicationServe
rKey\" *.js server\\*.js index.html" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 678ms:
script.js:919:    const keyRes = await fetch(`${SERVER_URL}/api/push/vapid-public-key`);
script.js:924:      applicationServerKey: urlBase64ToUint8Array(key),
server\index.js:7:// VAPID 설정
server\index.js:8:const VAPID_PUBLIC = process.env.VAPID_PUBLIC;
server\index.js:9:const VAPID_PRIVATE = process.env.VAPID_PRIVATE;
server\index.js:10:if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
server\index.js:11:  console.error("환경변수 VAPID_PUBLIC, VAPID_PRIVATE가 설정되지 않았습니다.");
server\index.js:14:webpush.setVapidDetails("mailto:admin@snu-app.com", VAPID_PUBLIC, VAPID_PRIVATE);
server\index.js:341:app.get("/api/push/vapid-public-key", (req, res) => {
server\index.js:342:  res.json({ key: VAPID_PUBLIC });

2026-05-12T15:17:26.324472Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command "dir /b & if exist package.json type package.json & if exist server\\package.json type server\\p
ackage.json"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "dir /b & if exist package.json type package.
json & if exist server\\package.json type server\\package.json" in C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "dir /b & if exist package.json type package
.json & if exist server\\package.json type server\\package.json"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-ChildItem -Name' in C:\Users\tom07\Deskt
op\snu 과제 앱
 succeeded in 951ms:
server
.gitignore
app.webmanifest
CODEX_CODE_REVIEW.md
CODEX_REVIEW.md
icon-192.png
icon-512.png
index.html
LICENSE
PLAN.md
PLAN_REVIEW.md
README.md
script.js
style.css
sw.js

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "Get-ChildItem -Name server; type server\\pac
kage.json" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 773ms:
node_modules
id_tab.png
id_tab_clicked.png
index.js
login_flow.png
login_page.png
login_stealth.png
main_page.png
package-lock.json
package.json
{
  "name": "snu-assignment-server",
  "version": "1.0.0",
  "description": "SNU eTL 怨쇱젣 ?뚮┝ ???꾨줉???쒕쾭",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "cheerio": "^1.2.0",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "node-ical": "^0.26.1",
    "web-push": "^3.6.7"
  }
}

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /i \"VAPID npm start start server
\" README.md server\\package.json" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 679ms:
server\package.json:2:  "name": "snu-assignment-server",
server\package.json:7:    "start": "node index.js"

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git diff --name-only; git status --short' in
 C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 969ms:
script.js
server/index.js
style.css
 M script.js
 M server/index.js
 M style.css
?? CODEX_CODE_REVIEW.md
?? CODEX_REVIEW.md
?? PLAN.md
?? PLAN_REVIEW.md

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git show HEAD:script.js | findstr /n /c:"fun
ction renderMapTab" /c:"SNU_LOCATIONS.forEach" /c:"L.control.locate"' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 1107ms:
1202:function renderMapTab() {
1212:    SNU_LOCATIONS.forEach(loc => {
1229:    L.control.locate = function(opts) {
1248:    L.control.locate().addTo(leafletMap);

2026-05-12T15:17:57.043523Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command "node --check script.js; node --check server\\index.js"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "node --check script.js; node --check server\
\index.js" in C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "node --check script.js; node --check server
\\index.js"` rejected: blocked by policy
2026-05-12T15:17:59.704227Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command 'node --check script.js'` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'node --check script.js' in C:\Users\tom07\De
sktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'node --check script.js'` rejected: blocked 
by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'type .gitignore' in C:\Users\tom07\Desktop\s
nu 과제 앱
 succeeded in 823ms:
node_modules/
server/node_modules/
.env
*.log

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'type CODEX_CODE_REVIEW.md' in C:\Users\tom07
\Desktop\snu 과제 앱

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'type CODEX_REVIEW.md' in C:\Users\tom07\Desk
top\snu 과제 앱
 succeeded in 1142ms:
node.exe : OpenAI Codex v0.130.0
At C:\Users\tom07\AppData\Roaming\npm\codex.ps1:24 char:5
+     & "node$exe"  "$basedir/node_modules/@openai/codex/bin/codex.js"  ...
+     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (OpenAI Codex v0.130.0:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 
--------
workdir: C:\Users\tom07\Desktop\snu 과제 앱
model: gpt-5.5
provider: openai
approval: never
sandbox: read-only
reasoning effort: medium
reasoning summaries: none
session id: 019e1c95-35d5-7010-9208-ef18f14d4686
--------
user
changes against 'ca89c07'
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git diff ca89c07128d9e4b438b0ae91a8dedfe6360
be248' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 402ms:
diff --git a/.gitignore b/.gitignore
new file mode 100644
index 0000000..db7dc50
--- /dev/null
+++ b/.gitignore
@@ -0,0 +1,4 @@
+node_modules/
+server/node_modules/
+.env
+*.log
diff --git a/app.webmanifest b/app.webmanifest
new file mode 100644
index 0000000..2ce738e
--- /dev/null
+++ b/app.webmanifest
@@ -0,0 +1,20 @@
+{
+  "name": "서울대 과제 알림",
+  "short_name": "과제알림",
+  "start_url": "./",
+  "display": "standalone",
+  "background_color": "#ffffff",
+  "theme_color": "#ffffff",
+  "icons": [
+    {
+      "src": "icon-192.png",
+      "sizes": "192x192",
+      "type": "image/png"
+    },
+    {
+      "src": "icon-512.png",
+      "sizes": "512x512",
+      "type": "image/png"
+    }
+  ]
+}
\ No newline at end of file
diff --git a/icon-192.png b/icon-192.png
new file mode 100644
index 0000000..7c2a791
Binary files /dev/null and b/icon-192.png differ
diff --git a/icon-512.png b/icon-512.png
new file mode 100644
index 0000000..4ca3759
Binary files /dev/null and b/icon-512.png differ
diff --git a/index.html b/index.html
new file mode 100644
index 0000000..5c1ac45
--- /dev/null
+++ b/index.html
@@ -0,0 +1,220 @@
+<!DOCTYPE html>
+<html lang="ko">
+<head>
+  <meta charset="UTF-8" />
+  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
+  <title>서울대 과제 알림</title>
+  <link rel="manifest" href="app.webmanifest" />
+  <meta name="theme-color" content="#ffffff" />
+  <link rel="apple-touch-icon" href="icon-192.png" />
+  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" crossorigin="" />
+  <link rel="stylesheet" href="style.css?v=13" />
+</head>
+<body>
+  <div class="app">
+
+    <header class="app-header">
+      <div class="header-row">
+        <h1>서울대</h1>
+        <button type="button" id="settingsBtn" title="설정">⚙</button>
+      </div>
+    </header>
+
+    <!-- 설정 드로어 오버레이 -->
+    <div id="settingsOverlay" class="settings-overlay"></div>
+
+    <!-- 설정 패널 -->
+    <div id="settingsPanel" class="settings-panel">
+      <div class="settings-panel-header">
+        <p class="settings-panel-title">설정</p>
+        <button type="button" id="settingsCloseBtn">✕</button>
+      </div>
+      <div id="etlSetupForm">
+        <div class="how-to">
+          <p class="how-to-title">📋 eTL 캘린더 URL 가져오는 방법</p>
+          <ol>
+            <li>eTL 로그인 후 상단 <strong>캘린더</strong> 클릭</li>
+            <li>좌측 하단 <strong>"캘린더 내보내기"</strong> 클릭</li>
+            <li><strong>"모든 과목"</strong> + <strong>"최근 및 다음 60일"</strong> 선택</li>
+            <li><strong>"캘린더 URL 가져오기"</strong> 클릭 → URL 복사</li>
+            <li>아래에 붙여넣기</li>
+          </ol>
+        </div>
+        <form id="icalForm">
+          <div class="input-group">
+            <label for="icalUrlInput">eTL 캘린더 URL</label>
+            <input type="text" id="icalUrlInput" placeholder="webcal://myetl.snu.ac.kr/feeds/calendars/user_..." />
+          </div>
+          <div class="etl-actions">
+            <button type="submit" id="icalSaveBtn">저장 &amp; 과제 가져오기</button>
+          </div>
+        </form>
+      </div>
+
+      <div id="etlConnected" class="hidden">
+        <div class="etl-status">
+          <span class="status-dot"></span>
+          <span>eTL 연동됨</span>
+          <span id="etlSyncStatus" class="sync-status"></span>
+        </div>
+        <div class="etl-actions">
+          <button type="button" id="etlSyncBtn">지금 새로고침</button>
+          <button type="button" id="etlDisconnectBtn" class="btn-secondary">연동 해제</button>
+        </div>
+        <div class="token-section">
+          <p class="token-label">제출한 과제 자동 제외 <span class="token-optional">(선택)</span></p>
+          <div class="token-input-row">
+            <input type="password" id="apiTokenInput" placeholder="eTL API 토큰 입력..." />
+            <button type="button" id="apiTokenSaveBtn" class="btn-secondary">저장</button>
+          </div>
+          <p class="token-hint">eTL → 우측 상단 프로필 → 설정 → 스크롤 하단 "승인된 통합" → 새 액세스 토큰</p>
+        </div>
+      </div>
+
+      <p id="etlError" class="etl-error hidden"></p>
+
+      <div class="dark-mode-row">
+        <span class="token-label">다크 모드</span>
+        <button type="button" id="darkModeBtn" class="btn-secondary">🌙 다크 모드</button>
+      </div>
+    </div>
+
+    <!-- 탭 바 -->
+    <div class="tab-bar">
+      <button class="tab-btn active" data-tab="alerts">과제 알림</button>
+      <button class="tab-btn" data-tab="calendar">달력</button>
+      <button class="tab-btn" data-tab="restaurant">식당</button>
+      <button class="tab-btn" data-tab="map">지도</button>
+    </div>
+
+    <!-- 과제 알림 탭 -->
+    <div id="alertsTab">
+      <section class="list-section">
+        <div class="list-header">
+          <h2>과제 목록</h2>
+        </div>
+        <ul id="taskList" class="task-list"></ul>
+        <p id="emptyMessage" class="empty-message">아직 등록된 과제가 없습니다.</p>
+      </section>
+
+      <section id="completedSection" class="list-section hidden">
+        <div class="list-header completed-header" id="completedToggle">
+          <h2>최근 완료한 과제</h2>
+          <span id="completedToggleIcon">▲</span>
+        </div>
+        <ul id="completedList" class="task-list"></ul>
+      </section>
+    </div>
+
+    <!-- 달력 탭 -->
+    <div id="calendarTab" class="hidden">
+
+      <!-- 월 네비게이션 -->
+      <div class="cal-nav">
+        <button id="calPrev" class="cal-nav-btn">‹</button>
+        <span id="calTitle" class="cal-title"></span>
+        <button id="calNext" class="cal-nav-btn">›</button>
+      </div>
+
+      <!-- 요일 헤더 -->
+      <div class="cal-weekdays">
+        <span>일</span><span>월</span><span>화</span><span>수</span><span>목</span><span>금</span><span>토</span>
+      </div>
+
+      <!-- 날짜 그리드 -->
+      <div id="calDays" class="cal-days"></div>
+
+      <!-- 날짜 상세 -->
+      <div id="calDayDetail" class="cal-day-detail hidden">
+        <div class="cal-detail-header">
+          <span id="calSelectedDate" class="cal-selected-label"></span>
+          <button id="calAddBtn" class="cal-add-btn">+ 추가</button>
+        </div>
+        <ul id="calEventList" class="cal-event-list"></ul>
+      </div>
+
+      <!-- 학교 소식 -->
+      <section class="news-section list-section">
+        <div class="list-header news-header" id="newsToggle">
+          <h2>학교 소식</h2>
+          <span id="newsToggleIcon">▲</span>
+        </div>
+        <div id="newsBody">
+          <div class="news-tabs">
+            <button class="news-tab active" data-tab="schedule">학사일정</button>
+            <button class="news-tab" data-tab="notices">공지사항</button>
+          </div>
+          <div id="newsSchedule" class="news-panel"></div>
+          <div id="newsNotices" class="news-panel hidden"></div>
+          <p id="newsLoading" class="news-loading">불러오는 중...</p>
+          <p id="newsError" class="news-error hidden"></p>
+        </div>
+      </section>
+    </div>
+
+  </div>
+
+    <!-- 식당 탭 -->
+    <div id="restaurantTab" class="hidden">
+      <div id="restaurantList"></div>
+    </div>
+
+  <!-- 지도 탭 -->
+  <div id="mapTab" class="hidden">
+    <div class="map-filter-bar">
+      <button class="map-filter-btn active" data-filter="all">전체</button>
+      <button class="map-filter-btn" data-filter="restaurant">🍽️ 식당</button>
+      <button class="map-filter-btn" data-filter="cafe">☕ 카페</button>
+      <button class="map-filter-btn" data-filter="building">🏛️ 건물</button>
+    </div>
+    <div id="mapContainer"></div>
+  </div>
+
+  <!-- 일정 추가 모달 -->
+  <div id="calModal" class="cal-modal hidden">
+    <div class="cal-modal-overlay" id="calModalOverlay"></div>
+    <div class="cal-modal-box">
+      <h3 class="cal-modal-title">일정 추가</h3>
+      <div class="cal-modal-field">
+        <label>제목</label>
+        <input type="text" id="calModalTitle" placeholder="일정 제목" />
+      </div>
+      <div class="cal-modal-field">
+        <label id="calModalDateLabel"></label>
+        <div class="time-picker">
+          <div class="time-picker-highlight"></div>
+          <div class="time-scroll-col" id="ampmCol">
+            <div class="time-scroll-inner">
+              <div class="time-item" data-val="오전">오전</div>
+              <div class="time-item" data-val="오후">오후</div>
+            </div>
+          </div>
+          <div class="time-scroll-col" id="hourCol">
+            <div class="time-scroll-inner" id="hourInner"></div>
+          </div>
+          <div class="time-colon">:</div>
+          <div class="time-scroll-col" id="minCol">
+            <div class="time-scroll-inner" id="minInner"></div>
+          </div>
+        </div>
+      </div>
+      <div class="cal-modal-actions">
+        <button id="calModalSave">저장</button>
+        <button id="calModalCancel" class="btn-secondary">취소</button>
+      </div>
+    </div>
+  </div>
+
+  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" crossorigin=""></script>
+  <script src="script.js?v=13"></script>
+  <script>
+    if ("serviceWorker" in navigator) {
+      window.addEventListener("load", () => {
+        navigator.serviceWorker.register("./sw.js")
+          .then(() => console.log("Service Worker 등록 성공"))
+          .catch((err) => console.log("Service Worker 등록 실패:", err));
+      });
+    }
+  </script>
+</body>
+</html>
diff --git a/script.js b/script.js
new file mode 100644
index 0000000..e436d70
--- /dev/null
+++ b/script.js
@@ -0,0 +1,1545 @@
+const SERVER_URL = location.hostname === "localhost"
+  ? "http://localhost:3001"
+  : "https://snu-assignment-server.onrender.com";
+
+// Render 무료 플랜 cold start 방지: 10분마다 서버 핑
+if (location.hostname !== "localhost") {
+  setInterval(() => fetch(`${SERVER_URL}/health`).catch(() => {}), 10 * 60 * 1000);
+}
+const STORAGE_KEY = "snu_assignment_app_tasks";
+const ICAL_URL_KEY = "snu_etl_ical_url";
+const CANVAS_TOKEN_KEY = "snu_etl_canvas_token";
+const MEMO_KEY = "snu_assignment_app_memos";
+const COMPLETED_KEY = "snu_assignment_app_completed";
+const CALENDAR_KEY = "snu_calendar_events";
+
+// 2026년 공휴일 및 대체공휴일
+const HOLIDAYS = [
+  { title: "신정",             date: "2026-01-01" },
+  { title: "설날 연휴",         date: "2026-02-15" },
+  { title: "설날",             date: "2026-02-17" },
+  { title: "설날 연휴",         date: "2026-02-18" },
+  { title: "대체공휴일(설날)",   date: "2026-02-19" },
+  { title: "삼일절",           date: "2026-03-01" },
+  { title: "대체공휴일(삼일절)", date: "2026-03-02" },
+  { title: "어린이날",          date: "2026-05-05" },
+  { title: "부처님오신날",       date: "2026-05-24" },
+  { title: "현충일",            date: "2026-06-06" },
+  { title: "대체공휴일(현충일)", date: "2026-06-08" },
+  { title: "광복절",            date: "2026-08-15" },
+  { title: "대체공휴일(광복절)", date: "2026-08-17" },
+  { title: "추석 연휴",         date: "2026-09-23" },
+  { title: "추석 연휴",         date: "2026-09-24" },
+  { title: "추석",             date: "2026-09-25" },
+  { title: "대체공휴일(추석)",   date: "2026-09-28" },
+  { title: "개천절",            date: "2026-10-03" },
+  { title: "대체공휴일(개천절)", date: "2026-10-05" },
+  { title: "한글날",            date: "2026-10-09" },
+  { title: "성탄절",            date: "2026-12-25" },
+];
+
+// 2026년 1학기 학사일정
+const ACADEMIC_SCHEDULE = [
+  { id: "ac_1", title: "봄학기 개강", date: "2026-03-02" },
+  { id: "ac_2", title: "수강변경 기간", startDate: "2026-03-02", endDate: "2026-03-13" },
+  { id: "ac_3", title: "중간고사", startDate: "2026-04-20", endDate: "2026-04-25" },
+  { id: "ac_4", title: "수강취소 기간", startDate: "2026-04-27", endDate: "2026-05-01" },
+  { id: "ac_5", title: "기말고사", startDate: "2026-06-15", endDate: "2026-06-20" },
+  { id: "ac_6", title: "봄학기 종강", date: "2026-06-19" },
+  { id: "ac_7", title: "관악제", startDate: "2026-05-12", endDate: "2026-05-14" },
+];
+
+// DOM - 과제
+const taskList = document.getElementById("taskList");
+const emptyMessage = document.getElementById("emptyMessage");
+const completedSection = document.getElementById("completedSection");
+const completedList = document.getElementById("completedList");
+const completedToggle = document.getElementById("completedToggle");
+const completedToggleIcon = document.getElementById("completedToggleIcon");
+
+// DOM - 설정
+const settingsBtn = document.getElementById("settingsBtn");
+const settingsPanel = document.getElementById("settingsPanel");
+const settingsOverlay = document.getElementById("settingsOverlay");
+const settingsCloseBtn = document.getElementById("settingsCloseBtn");
+const icalForm = document.getElementById("icalForm");
+const icalUrlInput = document.getElementById("icalUrlInput");
+const icalSaveBtn = document.getElementById("icalSaveBtn");
+const etlSetupForm = document.getElementById("etlSetupForm");
+const etlConnected = document.getElementById("etlConnected");
+const etlSyncBtn = document.getElementById("etlSyncBtn");
+const etlDisconnectBtn = document.getElementById("etlDisconnectBtn");
+const etlSyncStatus = document.getElementById("etlSyncStatus");
+const etlError = document.getElementById("etlError");
+const apiTokenInput = document.getElementById("apiTokenInput");
+const apiTokenSaveBtn = document.getElementById("apiTokenSaveBtn");
+
+// 데이터
+let tasks = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
+let memos = JSON.parse(localStorage.getItem(MEMO_KEY)) || {};
+let completedTasks = JSON.parse(localStorage.getItem(COMPLETED_KEY)) || [];
+let calendarEvents = JSON.parse(localStorage.getItem(CALENDAR_KEY)) || [];
+let icalUrl = localStorage.getItem(ICAL_URL_KEY) || null;
+let canvasToken = localStorage.getItem(CANVAS_TOKEN_KEY) || null;
+
+// 달력 상태
+let calYear = new Date().getFullYear();
+let calMonth = new Date().getMonth();
+let calSelectedDate = null;
+
+// ──────────────────────────────────────────
+// 날짜 유틸
+// ──────────────────────────────────────────
+
+function parseDateValue(value) {
+  const date = new Date(value);
+  return Number.isNaN(date.getTime()) ? null : date;
+}
+
+function formatDateTime(value, dateOnly = false) {
+  const date = parseDateValue(value);
+  if (!date) return value;
+  const y = date.getFullYear();
+  const mo = String(date.getMonth() + 1).padStart(2, "0");
+  const d = String(date.getDate()).padStart(2, "0");
+  if (dateOnly) return `${y}.${mo}.${d}`;
+  const hours = date.getHours();
+  const ampm = hours < 12 ? "오전" : "오후";
+  const h12 = hours % 12 === 0 ? 12 : hours % 12;
+  const mi = String(date.getMinutes()).padStart(2, "0");
+  return `${y}.${mo}.${d} ${ampm} ${h12}:${mi}`;
+}
+
+function formatCellText(text) {
+  const clean = text.replace(/\s+/g, "");
+  const lines = [];
+  for (let i = 0; i < clean.length; i += 4) lines.push(clean.slice(i, i + 4));
+  return lines.join("\n");
+}
+
+function toDateStr(y, m, d) {
+  return `${y}-${String(m + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
+}
+
+function getBadgeInfo(dateString) {
+  const dueDate = parseDateValue(dateString);
+  if (!dueDate) return { text: "날짜 확인", className: "due-blue" };
+  const diffMs = dueDate - new Date();
+  const diffDays = diffMs / (1000 * 60 * 60 * 24);
+  if (diffMs < 0) return { text: "마감", className: "due-black" };
+  const d = Math.floor(diffDays);
+  if (d === 0) return { text: "D-0", className: "due-red" };
+  if (d <= 3) return { text: `D-${d}`, className: "due-green" };
+  return { text: `D-${d}`, className: "due-blue" };
+}
+
+function cleanCourseName(name) {
+  if (!name) return name;
+  return name
+    .replace(/^\d{4}-\d+/g, "")   // 앞의 2026-1 제거
+    .replace(/\(\d+\)$/g, "")     // 뒤의 (001) 제거
+    .trim();
+}
+
+function escapeHtml(str) {
+  return String(str)
+    .replace(/&/g, "&amp;")
+    .replace(/</g, "&lt;")
+    .replace(/>/g, "&gt;")
+    .replace(/"/g, "&quot;");
+}
+
+// ──────────────────────────────────────────
+// 저장
+// ──────────────────────────────────────────
+
+function saveTasks() { localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks)); }
+function saveMemos() { localStorage.setItem(MEMO_KEY, JSON.stringify(memos)); }
+function saveCompleted() { localStorage.setItem(COMPLETED_KEY, JSON.stringify(completedTasks)); }
+function saveCalendarEvents() { localStorage.setItem(CALENDAR_KEY, JSON.stringify(calendarEvents)); }
+
+// ──────────────────────────────────────────
+// 탭 전환
+// ──────────────────────────────────────────
+
+const alertsTab = document.getElementById("alertsTab");
+const calendarTab = document.getElementById("calendarTab");
+const restaurantTab = document.getElementById("restaurantTab");
+const mapTab = document.getElementById("mapTab");
+
+document.querySelectorAll(".tab-btn").forEach((btn) => {
+  btn.addEventListener("click", () => {
+    document.querySelectorAll(".tab-btn").forEach((b) => b.classList.remove("active"));
+    btn.classList.add("active");
+    const tab = btn.dataset.tab;
+    alertsTab.classList.toggle("hidden", tab !== "alerts");
+    calendarTab.classList.toggle("hidden", tab !== "calendar");
+    restaurantTab.classList.toggle("hidden", tab !== "restaurant");
+    mapTab.classList.toggle("hidden", tab !== "map");
+    if (tab === "calendar") renderCalendar();
+    if (tab === "restaurant") renderRestaurantTab();
+    if (tab === "map") renderMapTab();
+  });
+});
+
+// ──────────────────────────────────────────
+// 과제 렌더링
+// ──────────────────────────────────────────
+
+function sortTasks() {
+  tasks.sort((a, b) => {
+    const da = parseDateValue(a.dueDate);
+    const db = parseDateValue(b.dueDate);
+    if (!da && !db) return 0;
+    if (!da) return 1;
+    if (!db) return -1;
+    return da - db;
+  });
+}
+
+function renderTasks() {
+  sortTasks();
+  taskList.innerHTML = "";
+
+  const now = new Date();
+  const visible = tasks.filter((t) => {
+    const due = parseDateValue(t.dueDate);
+    if (!due) return true;
+    const diffDays = (due - now) / (1000 * 60 * 60 * 24);
+    return diffDays >= 0 && diffDays <= 7;
+  });
+
+  emptyMessage.classList.toggle("hidden", visible.length > 0);
+
+  visible.forEach((task) => {
+    const badge = getBadgeInfo(task.dueDate);
+    const li = document.createElement("li");
+    li.className = "task-item";
+
+    const memo = memos[task.id] || "";
+    const mainLabel = cleanCourseName(task.courseName) || task.title;
+    const subLabel = task.courseName ? task.title : ""  // subLabel은 원본 title 유지;
+    const sourceTag = task.source === "etl"
+      ? `<span class="source-tag etl-tag">eTL</span>`
+      : "";
+    const mainLink = task.url
+      ? `<a class="task-title" href="${escapeHtml(task.url)}" target="_blank">${escapeHtml(mainLabel)}</a>`
+      : `<p class="task-title">${escapeHtml(mainLabel)}</p>`;
+    const subLabelHtml = subLabel
+      ? `<span class="course-label">${escapeHtml(subLabel)}</span>`
+      : "";
+
+    li.innerHTML = `
+      <div class="task-main">
+        <div class="task-title-row">${sourceTag}${mainLink}</div>
+        ${subLabelHtml}
+        <div class="task-meta">
+          <span class="due-date-text">마감일: ${formatDateTime(task.dueDate, task.dateOnly)}</span>
+          <span class="due-badge ${badge.className}">${badge.text}</span>
+          <button class="memo-btn" data-id="${task.id}" title="메모">✏️</button>
+        </div>
+        <textarea class="memo-input${memo ? "" : " hidden"}" placeholder="메모 입력..." data-id="${task.id}">${escapeHtml(
memo)}</textarea>
+      </div>
+      <button class="complete-btn" data-id="${task.id}">완료</button>
+    `;
+
+    const memoTextarea = li.querySelector(".memo-input");
+    const memoBtn = li.querySelector(".memo-btn");
+
+    function autoResize() {
+      memoTextarea.style.height = "36px";
+      memoTextarea.style.height = Math.max(36, memoTextarea.scrollHeight) + "px";
+    }
+
+    memoBtn.addEventListener("click", () => {
+      memoTextarea.classList.toggle("hidden");
+      if (!memoTextarea.classList.contains("hidden")) {
+        autoResize();
+        memoTextarea.focus();
+      }
+    });
+
+    memoTextarea.addEventListener("input", () => {
+      autoResize();
+      const val = memoTextarea.value;
+      if (val.trim()) {
+        memos[task.id] = val;
+      } else {
+        delete memos[task.id];
+      }
+      saveMemos();
+    });
+
+    if (memo) autoResize();
+
+    li.querySelector(".complete-btn").addEventListener("click", () => {
+      completedTasks.unshift({ ...task, completedAt: new Date().toISOString() });
+      if (completedTasks.length > 20) completedTasks.pop();
+      tasks = tasks.filter((item) => item.id !== task.id);
+      saveTasks();
+      saveCompleted();
+      renderTasks();
+      renderCompleted();
+      if (!calendarTab.classList.contains("hidden")) renderCalendar();
+    });
+
+    taskList.appendChild(li);
+  });
+}
+
+function renderCompleted() {
+  if (!completedList) return;
+  completedList.innerHTML = "";
+
+  if (completedTasks.length === 0) {
+    completedSection.classList.add("hidden");
+    return;
+  }
+
+  completedSection.classList.remove("hidden");
+
+  completedTasks.forEach((task) => {
+    const li = document.createElement("li");
+    li.className = "task-item completed-task-item";
+
+    const mainLabel = cleanCourseName(task.courseName) || task.title;
+    const subLabel = task.courseName ? task.title : ""  // subLabel은 원본 title 유지;
+    const titleDisplay = task.url
+      ? `<a class="task-title" href="${escapeHtml(task.url)}" target="_blank">${escapeHtml(mainLabel)}</a>`
+      : `<p class="task-title">${escapeHtml(mainLabel)}</p>`;
+    const subLabelHtml = subLabel
+      ? `<span class="course-label">${escapeHtml(subLabel)}</span>`
+      : "";
+
+    li.innerHTML = `
+      <div class="task-main">
+        <div class="task-title-row">${titleDisplay}</div>
+        ${subLabelHtml}
+        <div class="task-meta">
+          <span class="due-date-text">완료: ${formatDateTime(task.completedAt)}</span>
+        </div>
+      </div>
+      <button class="restore-btn" data-id="${task.id}">되돌리기</button>
+    `;
+
+    li.querySelector(".restore-btn").addEventListener("click", () => {
+      const { completedAt, ...restored } = task;
+      tasks.push(restored);
+      completedTasks = completedTasks.filter((t) => t.id !== task.id);
+      saveTasks();
+      saveCompleted();
+      renderTasks();
+      renderCompleted();
+      if (!calendarTab.classList.contains("hidden")) renderCalendar();
+    });
+
+    completedList.appendChild(li);
+  });
+}
+
+if (completedToggle) {
+  completedToggle.addEventListener("click", () => {
+    const isHidden = completedList.classList.toggle("hidden");
+    if (completedToggleIcon) completedToggleIcon.textContent = isHidden ? "▼" : "▲";
+  });
+}
+
+// ──────────────────────────────────────────
+// 달력
+// ──────────────────────────────────────────
+
+function getHolidaysForDate(dateStr) {
+  return HOLIDAYS.filter((h) => h.date === dateStr);
+}
+
+function getAcademicForDate(dateStr) {
+  return ACADEMIC_SCHEDULE.filter((ev) => {
+    if (ev.startDate && ev.endDate) return dateStr >= ev.startDate && dateStr <= ev.endDate;
+    return ev.date === dateStr;
+  });
+}
+
+function getAssignmentsForDate(dateStr) {
+  return tasks.filter((t) => {
+    if (!t.dueDate) return false;
+    const d = new Date(t.dueDate);
+    return toDateStr(d.getFullYear(), d.getMonth(), d.getDate()) === dateStr;
+  });
+}
+
+function getUserEventsForDate(dateStr) {
+  return calendarEvents.filter((ev) => ev.date === dateStr);
+}
+
+function renderCalendar() {
+  const calDaysEl = document.getElementById("calDays");
+  const calTitleEl = document.getElementById("calTitle");
+  calTitleEl.textContent = `${calYear}년 ${calMonth + 1}월`;
+  calDaysEl.innerHTML = "";
+
+  const firstDay = new Date(calYear, calMonth, 1).getDay();
+  const daysInMonth = new Date(calYear, calMonth + 1, 0).getDate();
+  const daysInPrevMonth = new Date(calYear, calMonth, 0).getDate();
+
+  const today = new Date();
+  const todayStr = toDateStr(today.getFullYear(), today.getMonth(), today.getDate());
+
+  const totalCells = Math.ceil((firstDay + daysInMonth) / 7) * 7;
+
+  for (let i = 0; i < totalCells; i++) {
+    let day, year, month, inCurrentMonth;
+
+    if (i < firstDay) {
+      day = daysInPrevMonth - firstDay + i + 1;
+      year = calMonth === 0 ? calYear - 1 : calYear;
+      month = calMonth === 0 ? 11 : calMonth - 1;
+      inCurrentMonth = false;
+    } else if (i - firstDay < daysInMonth) {
+      day = i - firstDay + 1;
+      year = calYear;
+      month = calMonth;
+      inCurrentMonth = true;
+    } else {
+      day = i - firstDay - daysInMonth + 1;
+      year = calMonth === 11 ? calYear + 1 : calYear;
+      month = calMonth === 11 ? 0 : calMonth + 1;
+      inCurrentMonth = false;
+    }
+
+    const dateStr = toDateStr(year, month, day);
+    const isToday = dateStr === todayStr;
+    const isSelected = dateStr === calSelectedDate;
+    const isSun = i % 7 === 0;
+    const isSat = i % 7 === 6;
+
+    const holidays = getHolidaysForDate(dateStr);
+    const academic = getAcademicForDate(dateStr);
+    const assignments = getAssignmentsForDate(dateStr);
+    const userEvts = getUserEventsForDate(dateStr);
+
+    const isHol = holidays.length > 0;
+
+    const cell = document.createElement("div");
+    cell.className = [
+      "cal-day",
+      inCurrentMonth ? "" : "other-month",
+      isToday ? "today" : "",
+      isSelected ? "selected" : "",
+      isSun || isHol ? "sunday" : "",
+      isSat ? "saturday" : "",
+    ].filter(Boolean).join(" ");
+    cell.dataset.date = dateStr;
+
+    const allEvents = [
+      ...holidays.map((e) => ({ text: e.title, type: "holiday" })),
+      ...academic.map((e) => ({ text: e.title, type: "academic" })),
+      ...assignments.map((e) => ({ text: cleanCourseName(e.courseName) || e.title, type: "assignment" })),
+      ...userEvts.map((e) => ({ text: e.title, type: "user" })),
+    ];
+
+    const MAX_VISIBLE = 2;
+    const visibleEvents = allEvents.slice(0, MAX_VISIBLE);
+    const extraCount = allEvents.length - MAX_VISIBLE;
+
+    const eventsHtml = visibleEvents.map((e) =>
+      `<div class="cal-cell-event ${e.type}">${escapeHtml(formatCellText(e.text))}</div>`
+    ).join("") + (extraCount > 0 ? `<div class="cal-cell-more">+${extraCount}</div>` : "");
+
+    cell.innerHTML = `
+      <span class="cal-day-num">${day}</span>
+      <div class="cal-cell-events">${eventsHtml}</div>
+    `;
+
+    cell.addEventListener("click", () => {
+      calSelectedDate = dateStr;
+      renderCalendar();
+      renderDayDetail(dateStr);
+    });
+
+    calDaysEl.appendChild(cell);
+  }
+}
+
+function renderDayDetail(dateStr) {
+  const detailEl = document.getElementById("calDayDetail");
+  const selectedDateEl = document.getElementById("calSelectedDate");
+  const eventListEl = document.getElementById("calEventList");
+
+  detailEl.classList.remove("hidden");
+
+  const [y, m, d] = dateStr.split("-").map(Number);
+  selectedDateEl.textContent = `${m}월 ${d}일`;
+
+  document.getElementById("calAddBtn").dataset.date = dateStr;
+
+  const holidays = getHolidaysForDate(dateStr);
+  const academic = getAcademicForDate(dateStr);
+  const assignments = getAssignmentsForDate(dateStr);
+  const userEvts = getUserEventsForDate(dateStr);
+
+  eventListEl.innerHTML = "";
+
+  if (holidays.length === 0 && academic.length === 0 && assignments.length === 0 && userEvts.length === 0) {
+    eventListEl.innerHTML = '<li class="cal-no-events">일정이 없습니다.</li>';
+    return;
+  }
+
+  holidays.forEach((ev) => {
+    const li = document.createElement("li");
+    li.className = "cal-event-item";
+    li.innerHTML = `
+      <span class="cal-event-dot holiday"></span>
+      <span class="cal-event-title">${escapeHtml(ev.title)}</span>
+      <span class="cal-event-tag holiday-tag">공휴일</span>
+    `;
+    eventListEl.appendChild(li);
+  });
+
+  academic.forEach((ev) => {
+    const li = document.createElement("li");
+    li.className = "cal-event-item";
+    li.innerHTML = `
+      <span class="cal-event-dot academic"></span>
+      <span class="cal-event-title">${escapeHtml(ev.title)}</span>
+      <span class="cal-event-tag academic-tag">학사</span>
+    `;
+    eventListEl.appendChild(li);
+  });
+
+  assignments.forEach((task) => {
+    const li = document.createElement("li");
+    li.className = "cal-event-item";
+    const badge = getBadgeInfo(task.dueDate);
+    const calLabel = cleanCourseName(task.courseName) || task.title;
+    const titleEl = task.url
+      ? `<a class="cal-event-title link" href="${escapeHtml(task.url)}" target="_blank">${escapeHtml(calLabel)}</a>`
+      : `<span class="cal-event-title">${escapeHtml(calLabel)}</span>`;
+    li.innerHTML = `
+      <span class="cal-event-dot assignment"></span>
+      ${titleEl}
+      <span class="due-badge ${badge.className}" style="font-size:11px;padding:2px 8px">${badge.text}</span>
+    `;
+    eventListEl.appendChild(li);
+  });
+
+  userEvts.forEach((ev) => {
+    const li = document.createElement("li");
+    li.className = "cal-event-item";
+    const timeLabel = ev.time ? `<span class="due-date-text" style="font-size:12px">${formatDateTime(ev.time)}</span>`
 : "";
+    li.innerHTML = `
+      <span class="cal-event-dot user"></span>
+      <span class="cal-event-title">${escapeHtml(ev.title)}</span>
+      ${timeLabel}
+      <button class="cal-delete-btn" data-id="${ev.id}">✕</button>
+    `;
+    li.querySelector(".cal-delete-btn").addEventListener("click", () => {
+      calendarEvents = calendarEvents.filter((e) => e.id !== ev.id);
+      saveCalendarEvents();
+      renderCalendar();
+      renderDayDetail(dateStr);
+    });
+    eventListEl.appendChild(li);
+  });
+}
+
+// 달력 네비게이션
+document.getElementById("calPrev").addEventListener("click", () => {
+  calMonth--;
+  if (calMonth < 0) { calMonth = 11; calYear--; }
+  calSelectedDate = null;
+  document.getElementById("calDayDetail").classList.add("hidden");
+  renderCalendar();
+});
+
+document.getElementById("calNext").addEventListener("click", () => {
+  calMonth++;
+  if (calMonth > 11) { calMonth = 0; calYear++; }
+  calSelectedDate = null;
+  document.getElementById("calDayDetail").classList.add("hidden");
+  renderCalendar();
+});
+
+// 일정 추가 모달
+const calModal = document.getElementById("calModal");
+let calModalSelectedDate = null;
+
+// 시간 피커 초기화
+(function initTimePicker() {
+  const hourInner = document.getElementById("hourInner");
+  const minInner = document.getElementById("minInner");
+  for (let h = 1; h <= 12; h++) {
+    const el = document.createElement("div");
+    el.className = "time-item";
+    el.dataset.val = String(h);
+    el.textContent = String(h);
+    hourInner.appendChild(el);
+  }
+  for (let m = 0; m < 60; m += 5) {
+    const el = document.createElement("div");
+    el.className = "time-item";
+    el.dataset.val = String(m).padStart(2, "0");
+    el.textContent = String(m).padStart(2, "0");
+    minInner.appendChild(el);
+  }
+})();
+
+function scrollPickerTo(colId, index) {
+  const col = document.getElementById(colId);
+  col.scrollTop = index * 44;
+}
+
+function getPickerIndex(colId) {
+  const col = document.getElementById(colId);
+  const items = col.querySelectorAll(".time-item").length;
+  return Math.max(0, Math.min(Math.round(col.scrollTop / 44), items - 1));
+}
+
+function openCalModal(date) {
+  calModalSelectedDate = date;
+  const [y, mo, d] = date.split("-").map(Number);
+  document.getElementById("calModalDateLabel").textContent = `${mo}월 ${d}일`;
+  document.getElementById("calModalTitle").value = "";
+  calModal.classList.remove("hidden");
+  // hidden 해제 후에 scrollTop 적용 (display:none 상태에서는 무시됨)
+  requestAnimationFrame(() => {
+    scrollPickerTo("ampmCol", 1); // 오후
+    scrollPickerTo("hourCol", 5); // index 5 = 6시
+    scrollPickerTo("minCol", 0);  // index 0 = 00분
+  });
+  document.getElementById("calModalTitle").focus();
+}
+
+document.getElementById("calAddBtn").addEventListener("click", () => {
+  const date = document.getElementById("calAddBtn").dataset.date || toDateStr(calYear, calMonth, new Date().getDate())
;
+  openCalModal(date);
+});
+
+document.getElementById("calModalCancel").addEventListener("click", () => {
+  calModal.classList.add("hidden");
+});
+
+document.getElementById("calModalOverlay").addEventListener("click", () => {
+  calModal.classList.add("hidden");
+});
+
+document.getElementById("calModalSave").addEventListener("click", () => {
+  const title = document.getElementById("calModalTitle").value.trim();
+  if (!title || !calModalSelectedDate) return;
+
+  const ampmIdx = getPickerIndex("ampmCol");
+  const hourIdx = getPickerIndex("hourCol");
+  const minIdx = getPickerIndex("minCol");
+  const isAm = ampmIdx === 0;
+  const hour12 = hourIdx + 1;
+  const min = minIdx * 5;
+  let hour24;
+  if (isAm) {
+    hour24 = hour12 === 12 ? 0 : hour12;
+  } else {
+    hour24 = hour12 === 12 ? 12 : hour12 + 12;
+  }
+
+  const [y, mo, d] = calModalSelectedDate.split("-").map(Number);
+  const dt = new Date(y, mo - 1, d, hour24, min);
+
+  calendarEvents.push({
+    id: `user_${Date.now()}`,
+    title,
+    date: calModalSelectedDate,
+    time: dt.toISOString(),
+  });
+  saveCalendarEvents();
+  subscribePush();
+  checkDeadlines();
+  calModal.classList.add("hidden");
+  calSelectedDate = calModalSelectedDate;
+  renderCalendar();
+  renderDayDetail(calModalSelectedDate);
+});
+
+document.getElementById("calModalTitle").addEventListener("keydown", (e) => {
+  if (e.key === "Enter") document.getElementById("calModalSave").click();
+});
+
+// ──────────────────────────────────────────
+// 학교 소식
+// ──────────────────────────────────────────
+
+const newsToggle = document.getElementById("newsToggle");
+const newsToggleIcon = document.getElementById("newsToggleIcon");
+const newsBody = document.getElementById("newsBody");
+const newsSchedule = document.getElementById("newsSchedule");
+const newsNotices = document.getElementById("newsNotices");
+const newsLoading = document.getElementById("newsLoading");
+const newsError = document.getElementById("newsError");
+
+newsToggle.addEventListener("click", () => {
+  const hidden = newsBody.classList.toggle("hidden");
+  newsToggleIcon.textContent = hidden ? "▼" : "▲";
+});
+
+document.querySelectorAll(".news-tab").forEach((btn) => {
+  btn.addEventListener("click", () => {
+    document.querySelectorAll(".news-tab").forEach((b) => b.classList.remove("active"));
+    btn.classList.add("active");
+    const tab = btn.dataset.tab;
+    newsSchedule.classList.toggle("hidden", tab !== "schedule");
+    newsNotices.classList.toggle("hidden", tab !== "notices");
+  });
+});
+
+function formatNewsDate(isoString) {
+  if (!isoString) return "";
+  const d = new Date(isoString);
+  if (isNaN(d)) return isoString;
+  return `${String(d.getMonth() + 1).padStart(2, "0")}.${String(d.getDate()).padStart(2, "0")}`;
+}
+
+function renderSchedule(schedule) {
+  const now = new Date();
+  newsSchedule.innerHTML = "";
+  schedule.forEach((item) => {
+    const start = new Date(item.date || item.startDate);
+    const end = item.endDate ? new Date(item.endDate) : null;
+    const isPast = end ? end < now : start < now;
+    const div = document.createElement("div");
+    div.className = `news-item schedule-item${isPast ? " past" : ""}`;
+    const dateText = item.endDate
+      ? `${formatNewsDate(item.startDate || item.date)} ~ ${formatNewsDate(item.endDate)}`
+      : formatNewsDate(item.date);
+    div.innerHTML = `
+      <span class="news-source-tag snu-tag">공식</span>
+      <span class="news-title">${escapeHtml(item.title)}</span>
+      <span class="news-date">${dateText}</span>
+    `;
+    newsSchedule.appendChild(div);
+  });
+}
+
+function renderNotices(notices) {
+  newsNotices.innerHTML = "";
+  if (notices.length === 0) {
+    newsNotices.innerHTML = `<p class="news-empty">불러온 공지가 없습니다.</p>`;
+    return;
+  }
+  notices.forEach((item) => {
+    const div = document.createElement("div");
+    div.className = "news-item";
+    const sourceClass = item.source === "wesnu" ? "wesnu-tag" : "dongari-tag";
+    const sourceLabel = item.source === "wesnu" ? "총학" : "동아리";
+    div.innerHTML = `
+      <span class="news-source-tag ${sourceClass}">${sourceLabel}</span>
+      ${item.url
+        ? `<a class="news-title" href="${escapeHtml(item.url)}" target="_blank">${escapeHtml(item.title)}</a>`
+        : `<span class="news-title">${escapeHtml(item.title)}</span>`}
+      <span class="news-date">${formatNewsDate(item.date)}</span>
+    `;
+    newsNotices.appendChild(div);
+  });
+}
+
+let newsLoaded = false;
+async function loadEvents() {
+  if (newsLoaded) return;
+  newsLoading.classList.remove("hidden");
+  newsError.classList.add("hidden");
+  try {
+    const res = await fetch(`${SERVER_URL}/api/events`);
+    const data = await res.json();
+    newsLoading.classList.add("hidden");
+    newsLoaded = true;
+    renderSchedule(data.schedule || []);
+    renderNotices(data.notices || []);
+  } catch {
+    newsLoading.classList.add("hidden");
+    newsError.textContent = "학교 소식을 불러오지 못했습니다.";
+    newsError.classList.remove("hidden");
+  }
+}
+
+// ──────────────────────────────────────────
+// 설정 패널
+// ──────────────────────────────────────────
+
+function openSettings() {
+  settingsPanel.classList.add("open");
+  settingsOverlay.classList.add("open");
+}
+function closeSettings() {
+  settingsPanel.classList.remove("open");
+  settingsOverlay.classList.remove("open");
+}
+
+settingsBtn.addEventListener("click", openSettings);
+settingsCloseBtn.addEventListener("click", closeSettings);
+settingsOverlay.addEventListener("click", closeSettings);
+
+function showEtlError(msg) {
+  etlError.textContent = msg;
+  etlError.classList.remove("hidden");
+}
+function hideEtlError() {
+  etlError.classList.add("hidden");
+}
+function setConnectedUI() {
+  etlSetupForm.classList.add("hidden");
+  etlConnected.classList.remove("hidden");
+}
+function setDisconnectedUI() {
+  etlSetupForm.classList.remove("hidden");
+  etlConnected.classList.add("hidden");
+  etlSyncStatus.textContent = "";
+}
+
+icalForm.addEventListener("submit", async (e) => {
+  e.preventDefault();
+  hideEtlError();
+  const url = icalUrlInput.value.trim();
+  if (!url) { showEtlError("URL을 입력해주세요."); return; }
+  if (!url.startsWith("webcal://") && !url.startsWith("https://")) {
+    showEtlError("webcal:// 또는 https:// 로 시작하는 URL을 입력해주세요."); return;
+  }
+  if (!url.includes("etl.snu.ac.kr") && !url.includes("myetl.snu.ac.kr")) {
+    showEtlError("eTL 캘린더 URL이 맞는지 확인해주세요."); return;
+  }
+  icalSaveBtn.disabled = true;
+  icalSaveBtn.textContent = "가져오는 중...";
+  icalUrl = url;
+  localStorage.setItem(ICAL_URL_KEY, url);
+  const ok = await syncIcal();
+  if (ok) { setConnectedUI(); closeSettings(); }
+  icalSaveBtn.disabled = false;
+  icalSaveBtn.textContent = "저장 & 과제 가져오기";
+});
+
+etlSyncBtn.addEventListener("click", async () => {
+  hideEtlError();
+  etlSyncBtn.disabled = true;
+  etlSyncBtn.textContent = "새로고침 중...";
+  await syncIcal();
+  etlSyncBtn.disabled = false;
+  etlSyncBtn.textContent = "지금 새로고침";
+});
+
+etlDisconnectBtn.addEventListener("click", () => {
+  icalUrl = null;
+  localStorage.removeItem(ICAL_URL_KEY);
+  tasks = tasks.filter((t) => t.source !== "etl");
+  saveTasks();
+  renderTasks();
+  setDisconnectedUI();
+  hideEtlError();
+  icalUrlInput.value = "";
+  openSettings();
+});
+
+if (apiTokenSaveBtn) {
+  apiTokenSaveBtn.addEventListener("click", async () => {
+    const token = apiTokenInput.value.trim();
+    canvasToken = token || null;
+    if (token) {
+      localStorage.setItem(CANVAS_TOKEN_KEY, token);
+      apiTokenSaveBtn.textContent = "저장됨 ✓";
+    } else {
+      localStorage.removeItem(CANVAS_TOKEN_KEY);
+      apiTokenSaveBtn.textContent = "삭제됨";
+    }
+    setTimeout(() => { apiTokenSaveBtn.textContent = "저장"; }, 2000);
+    if (icalUrl) await syncIcal();
+  });
+}
+
+async function syncIcal(retrying = false) {
+  if (!icalUrl) return false;
+  if (retrying) etlSyncStatus.textContent = "서버 준비 중... 재시도 중";
+  try {
+    const res = await fetch(`${SERVER_URL}/api/sync-ical`, {
+      method: "POST",
+      headers: { "Content-Type": "application/json" },
+      body: JSON.stringify({ icalUrl, apiToken: canvasToken || undefined }),
+    });
+    const data = await res.json();
+    if (!res.ok) {
+      showEtlError(data.error || "과제 불러오기 실패");
+      etlSyncStatus.textContent = "동기화 실패";
+      return false;
+    }
+    tasks = tasks.filter((t) => t.source !== "etl");
+    data.forEach((a) => {
+      tasks.push({
+        id: `etl_${a.etlId}`,
+        etlId: a.etlId,
+        title: a.title,
+        courseName: a.courseName,
+        dueDate: a.dueDate,
+        dateOnly: a.dateOnly || false,
+        url: a.url || null,
+        source: "etl",
+      });
+    });
+    saveTasks();
+    renderTasks();
+    if (!calendarTab.classList.contains("hidden")) renderCalendar();
+    checkDeadlines();
+    subscribePush();
+    const now = new Date();
+    const t = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
+    etlSyncStatus.textContent = `마지막 동기화: ${t} (${data.length}개)`;
+    return true;
+  } catch {
+    if (!retrying) {
+      etlSyncStatus.textContent = "서버 깨우는 중... (최대 30초)";
+      hideEtlError();
+      setTimeout(() => syncIcal(true), 10000);
+      return false;
+    }
+    showEtlError("서버에 연결할 수 없습니다. 잠시 후 다시 시도해주세요.");
+    etlSyncStatus.textContent = "동기화 실패";
+    return false;
+  }
+}
+
+// ──────────────────────────────────────────
+// 알림 (Web Push)
+// ──────────────────────────────────────────
+
+function urlBase64ToUint8Array(base64String) {
+  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
+  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
+  const rawData = atob(base64);
+  return Uint8Array.from([...rawData].map((c) => c.charCodeAt(0)));
+}
+
+async function subscribePush() {
+  if (!("PushManager" in window) || !("serviceWorker" in navigator)) return;
+  if (Notification.permission !== "granted") return;
+
+  try {
+    const reg = await navigator.serviceWorker.ready;
+    const keyRes = await fetch(`${SERVER_URL}/api/push/vapid-public-key`);
+    const { key } = await keyRes.json();
+
+    const sub = await reg.pushManager.subscribe({
+      userVisibleOnly: true,
+      applicationServerKey: urlBase64ToUint8Array(key),
+    });
+
+    const etlTasks = tasks.filter((t) => t.source === "etl").map((t) => ({
+      etlId: t.etlId || t.id,
+      dueDate: t.dueDate,
+      title: t.title,
+      courseName: cleanCourseName(t.courseName),
+    }));
+
+    const userEventTasks = calendarEvents
+      .filter((e) => e.time)
+      .map((e) => ({
+        etlId: e.id,
+        dueDate: e.time,
+        title: e.title,
+        courseName: null,
+        targets: [24, 5],
+      }));
+
+    await fetch(`${SERVER_URL}/api/push/subscribe`, {
+      method: "POST",
+      headers: { "Content-Type": "application/json" },
+      body: JSON.stringify({ subscription: sub, tasks: [...etlTasks, ...userEventTasks] }),
+    });
+  } catch (err) {
+    console.warn("[push] 구독 실패:", err.message);
+  }
+}
+
+async function requestNotificationPermission() {
+  if (!("Notification" in window)) return;
+  const result = await Notification.requestPermission();
+  if (result === "granted") await subscribePush();
+}
+
+function checkDeadlines() {
+  if (Notification.permission !== "granted") return;
+
+  // ETL 과제: 24h / 5h / 1h (±6분 창에 들어올 때만 발송)
+  const WINDOW_H = 1 / 60;
+  const etlTasks = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
+  etlTasks.forEach((task) => {
+    const dueDate = parseDateValue(task.dueDate);
+    if (!dueDate) return;
+    const diffHours = (dueDate - new Date()) / (1000 * 60 * 60);
+    if (diffHours < 0) return;
+    [
+      { h: 24, key: `notified_24h_${task.id}` },
+      { h: 5,  key: `notified_5h_${task.id}` },
+      { h: 1,  key: `notified_1h_${task.id}` },
+    ].forEach(({ h, key }) => {
+      if (diffHours <= h + WINDOW_H && diffHours > h - WINDOW_H && !localStorage.getItem(key)) {
+        navigator.serviceWorker.ready.then((reg) => {
+          const name = cleanCourseName(task.courseName) || task.title;
+          reg.showNotification(`📚 마감 ${h}시간 전`, {
+            body: `${name} 과제 마감이 ${h}시간 후입니다.`,
+            icon: "./icon-192.png",
+          });
+        });
+        localStorage.setItem(key, "true");
+      }
+    });
+  });
+
+  // 사용자 직접 추가 일정: 24h / 5h (±1분 창에 들어올 때만 발송)
+  const userEvents = JSON.parse(localStorage.getItem(CALENDAR_KEY)) || [];
+  userEvents.filter((e) => e.time).forEach((ev) => {
+    const dueDate = parseDateValue(ev.time);
+    if (!dueDate) return;
+    const diffHours = (dueDate - new Date()) / (1000 * 60 * 60);
+    if (diffHours < 0) return;
+    [
+      { h: 24, key: `notified_24h_${ev.id}` },
+      { h: 5,  key: `notified_5h_${ev.id}` },
+    ].forEach(({ h, key }) => {
+      if (diffHours <= h + WINDOW_H && diffHours > h - WINDOW_H && !localStorage.getItem(key)) {
+        navigator.serviceWorker.ready.then((reg) => {
+          reg.showNotification(`📅 일정 ${h}시간 전`, {
+            body: `"${ev.title}" 일정이 ${h}시간 후입니다.`,
+            icon: "./icon-192.png",
+          });
+        });
+        localStorage.setItem(key, "true");
+      }
+    });
+  });
+}
+
+// ──────────────────────────────────────────
+// 식당 탭
+// ──────────────────────────────────────────
+
+const restaurantListEl = document.getElementById("restaurantList");
+const FAVE_REST_KEY = "snu_fave_restaurant";
+let restaurantDataCache = null;   // { list, snucoData, gangyeoData }
+let restaurantFetching = false;
+let selectedRestId = null;        // 현재 선택된 식당 id
+let selectedMeal = null;          // "breakfast" | "lunch" | "dinner"
+let faveRestId = localStorage.getItem(FAVE_REST_KEY) || null;
+
+function toggleFave(id) {
+  faveRestId = (faveRestId === id) ? null : id;
+  if (faveRestId) localStorage.setItem(FAVE_REST_KEY, faveRestId);
+  else            localStorage.removeItem(FAVE_REST_KEY);
+  // 순서가 바뀌므로 사이드바 전체 재렌더
+  if (restaurantDataCache) renderRestaurantLayout();
+}
+
+function getDefaultMeal() {
+  const h = new Date().getHours();
+  if (h < 9)  return "breakfast";
+  if (h < 15) return "lunch";
+  return "dinner";
+}
+
+// ─── 가나다 정렬 (숫자 시작은 맨 뒤) ───
+function koreanSort(a, b) {
+  const startsWithNum = s => /^\d/.test(s);
+  const an = startsWithNum(a), bn = startsWithNum(b);
+  if (an !== bn) return an ? 1 : -1;
+  return a.localeCompare(b, "ko");
+}
+
+// ─── 사이드바 항목 빌드 ───
+// snuco는 세부 식당 여러 개를 각각 항목으로 노출
+function buildSidebarItems(list, snucoData) {
+  const allItems = [];
+
+  for (const info of list) {
+    if (info.type === "snuco") {
+      allItems.push({ id: "snuco_header", label: "SNU 학생식당", isHeader: true, isOpen: info.isOpen });
+      if (snucoData && snucoData.restaurants) {
+        const sorted = snucoData.restaurants
+          .map((r, i) => ({ r, i, name: r.name.replace(/\s*\([\d-]+\)\s*$/, "").trim() }))
+          .sort((a, b) => koreanSort(a.name, b.name));
+        sorted.forEach(({ i, name }) => {
+          allItems.push({ id: `snuco_${i}`, label: name, isHeader: false, isOpen: null });
+        });
+      }
+    } else {
+      allItems.push({ id: info.id, label: info.name, isHeader: false, isOpen: info.isOpen });
+    }
+  }
+
+  // 즐겨찾기 항목을 맨 위로 이동
+  if (faveRestId) {
+    const faveItem = allItems.find(i => i.id === faveRestId && !i.isHeader);
+    if (faveItem) {
+      return [
+        { id: "__fave_header", label: "즐겨찾기", isHeader: true, isFaveHeader: true },
+        faveItem,
+        { id: "__divider", label: "전체 식당", isHeader: true },
+        ...allItems.filter(i => i.id !== faveRestId),
+      ];
+    }
+  }
+  return allItems;
+}
+
+// ─── 식사 메뉴 텍스트 → HTML ───
+function formatMealLines(val) {
+  const lines = val.split("\n").map(l => l.trim()).filter(Boolean);
+  return lines.map(line => {
+    if (/:\s*[\d,]+원/.test(line))              return `<span class="rest-menu-row">${escapeHtml(line)}</span>`;
+    if (/운영시간|예약|문의|※|\d{1,2}:\d{2}/.test(line)) return `<span class="rest-menu-time">${escapeHtml(line)}</span>`;
+    return `<span class="rest-menu-item">${escapeHtml(line)}</span>`;
+  }).join("");
+}
+
+// ──────────────────────────────────────────
+// 지도 탭
+// ──────────────────────────────────────────
+
+// SNU 주요 위치 데이터
+// type: "restaurant" | "cafe" | "building"
+// restId: 식당 탭 ID와 연결 (있을 때)
+const SNU_LOCATIONS = [
+  // ── 학생식당 (SNUCO) ──
+  { id: "loc_hakgwan_rest",   name: "학생회관 식당",    type: "restaurant", lat: 37.4614, lng: 126.9493, note: "220동 1·2층" }
,
+  { id: "loc_zahayeon_rest",  name: "자하연 식당",      type: "restaurant", lat: 37.4592, lng: 126.9453, note: "규장각 인근" },
+  { id: "loc_sodam",          name: "소담마루",          type: "restaurant", lat: 37.4548, lng: 126.9510, note: "301동 인근" 
},
+  { id: "loc_dure_rest",      name: "두레미담",          type: "restaurant", lat: 37.4607, lng: 126.9511, note: "63-1동" },
+  { id: "loc_gongdae_rest",   name: "공대 식당",         type: "restaurant", lat: 37.4537, lng: 126.9506, note: "302동 인근" 
},
+  { id: "loc_yesul_rest",     name: "예술계 식당",       type: "restaurant", lat: 37.4621, lng: 126.9500, note: "50동 인근" },
+  { id: "loc_gamgol",         name: "감골식당",          type: "restaurant", lat: 37.4582, lng: 126.9461, note: "사범대 인근" }
,
+  { id: "loc_byeolmee",       name: "별미네",            type: "restaurant", lat: 37.4600, lng: 126.9504, note: "학교 내 식당"
 },
+  // ── 외부 식당 ──
+  { id: "loc_burger",         name: "버거운버거",         type: "restaurant", lat: 37.4793, lng: 126.9513, note: "서울대입구역 상권
", restId: "burgerwoober" },
+  { id: "loc_gangyeo",        name: "강여사집밥",          type: "restaurant", lat: 37.4800, lng: 126.9519, note: "서울대입구역 상
권", restId: "gangyeo" },
+  // ── 카페 ──
+  { id: "loc_cafe_library",   name: "스누리 카페",        type: "cafe", lat: 37.4639, lng: 126.9487, note: "중앙도서관 1층" },
+  { id: "loc_cafe_hakgwan",   name: "학생회관 카페",       type: "cafe", lat: 37.4611, lng: 126.9493, note: "220동 1층" },
+  { id: "loc_starbucks",      name: "스타벅스 서울대점",   type: "cafe", lat: 37.4616, lng: 126.9499, note: "학생회관 앞" },
+  { id: "loc_cafe_inmun",     name: "인문대 카페",         type: "cafe", lat: 37.4609, lng: 126.9469, note: "인문대 1동" },
+  // ── 건물 ──
+  { id: "loc_library",        name: "중앙도서관",          type: "building", lat: 37.4639, lng: 126.9487, note: "62동" },
+  { id: "loc_hakgwan_bld",    name: "학생회관",            type: "building", lat: 37.4614, lng: 126.9493, note: "220동" },
+  { id: "loc_bonkwan",        name: "본관 (행정관)",       type: "building", lat: 37.4616, lng: 126.9476, note: "60동" },
+  { id: "loc_dure_bld",       name: "두레문예관",          type: "building", lat: 37.4607, lng: 126.9509, note: "학생 문화공간" }
,
+  { id: "loc_gate",           name: "SNU 정문",            type: "building", lat: 37.4596, lng: 126.9516, note: "관악캠퍼스 정
문" },
+  { id: "loc_gongdae_bld",    name: "공과대학",            type: "building", lat: 37.4535, lng: 126.9505, note: "301·302동 
일대" },
+  { id: "loc_inmun_bld",      name: "인문대학",            type: "building", lat: 37.4609, lng: 126.9468, note: "1·2동 일대" 
},
+  { id: "loc_sahoe_bld",      name: "사회과학대학",        type: "building", lat: 37.4601, lng: 126.9522, note: "16동" },
+  { id: "loc_gyeong_bld",     name: "경영대학",            type: "building", lat: 37.4623, lng: 126.9523, note: "58동" },
+  { id: "loc_jawoon_bld",     name: "자연과학대학",        type: "building", lat: 37.4573, lng: 126.9496, note: "500동 일대" },
+  { id: "loc_sabum_bld",      name: "사범대학",            type: "building", lat: 37.4581, lng: 126.9461, note: "11동 일대" }
,
+  { id: "loc_subway",         name: "서울대입구역",        type: "building", lat: 37.4811, lng: 126.9531, note: "지하철 2호선" },
+];
+
+// 카카오맵 길찾기 URL
+function kakaoNavUrl(lat, lng, name) {
+  return `https://map.kakao.com/link/to/${encodeURIComponent(name)},${lat},${lng}`;
+}
+
+// 식당 id / name → SNU_LOCATIONS 매칭
+function getRestaurantLoc(id, name) {
+  // 외부 식당: restId 직접 매칭
+  const byRestId = SNU_LOCATIONS.find(l => l.restId === id);
+  if (byRestId) return byRestId;
+  // 학생식당(snuco): 이름 기반 매칭
+  if (id && id.startsWith("snuco_")) {
+    const cleanName = name.replace(/\s*\([\d-]+\)\s*$/, "").trim();
+    return SNU_LOCATIONS.find(l =>
+      l.type === "restaurant" &&
+      (l.name === cleanName || l.name.includes(cleanName) || cleanName.includes(l.name))
+    ) || null;
+  }
+  return null;
+}
+
+// Leaflet 상태
+let leafletMap = null;
+let leafletMarkers = [];
+let activeMapFilter = "all";
+
+// 타입별 마커 색상
+const MAP_COLORS = { restaurant: "#ef4444", cafe: "#f59e0b", building: "#3b82f6" };
+
+function createMapIcon(type) {
+  const color = MAP_COLORS[type] || "#6b7280";
+  return L.divIcon({
+    className: "map-custom-icon",
+    html: `<div style="
+      width:20px;height:20px;
+      border-radius:50% 50% 50% 0;
+      background:${color};
+      border:2.5px solid #fff;
+      transform:rotate(-45deg);
+      box-shadow:0 2px 6px rgba(0,0,0,0.35)
+    "></div>`,
+    iconSize: [20, 20],
+    iconAnchor: [10, 20],
+    popupAnchor: [0, -22],
+  });
+}
+
+function buildMapPopup(loc) {
+  const typeLabel = loc.type === "restaurant" ? "🍽️ 식당" : loc.type === "cafe" ? "☕ 카페" : "🏛️ 건물";
+  return `
+    <div class="map-popup-inner">
+      <p class="map-popup-name">${escapeHtml(loc.name)}</p>
+      <p class="map-popup-note">${typeLabel}${loc.note ? ` · ${escapeHtml(loc.note)}` : ""}</p>
+      <a class="map-popup-nav" href="${kakaoNavUrl(loc.lat, loc.lng, loc.name)}" target="_blank" rel="noopener">🗺️ 카카
오맵 길찾기</a>
+    </div>`;
+}
+
+function applyMapFilter(filter) {
+  activeMapFilter = filter;
+  leafletMarkers.forEach(({ marker, type }) => {
+    if (filter === "all" || filter === type) {
+      marker.addTo(leafletMap);
+    } else {
+      marker.remove();
+    }
+  });
+}
+
+function renderMapTab() {
+  if (!leafletMap) {
+    // 지도 초기화 (캠퍼스 중심)
+    leafletMap = L.map("mapContainer", { zoomControl: true }).setView([37.4651, 126.9507], 15);
+    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
+      attribution: "© <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a>",
+      maxZoom: 19,
+    }).addTo(leafletMap);
+
+    // 마커 추가
+    SNU_LOCATIONS.forEach(loc => {
+      const marker = L.marker([loc.lat, loc.lng], { icon: createMapIcon(loc.type) })
+        .bindPopup(buildMapPopup(loc), { maxWidth: 220 });
+      leafletMarkers.push({ marker, type: loc.type, id: loc.id });
+      marker.addTo(leafletMap);
+    });
+
+    // 필터 버튼 이벤트
+    document.querySelectorAll(".map-filter-btn").forEach(btn => {
+      btn.addEventListener("click", () => {
+        document.querySelectorAll(".map-filter-btn").forEach(b => b.classList.remove("active"));
+        btn.classList.add("active");
+        applyMapFilter(btn.dataset.filter);
+      });
+    });
+
+    // 현재 위치 버튼
+    L.control.locate = function(opts) {
+      const ctrl = L.control({ position: "topright" });
+      ctrl.onAdd = function() {
+        const btn = L.DomUtil.create("button", "map-locate-btn");
+        btn.innerHTML = "📍";
+        btn.title = "내 위치";
+        L.DomEvent.on(btn, "click", () => {
+          if (!navigator.geolocation) return;
+          navigator.geolocation.getCurrentPosition(pos => {
+            leafletMap.setView([pos.coords.latitude, pos.coords.longitude], 17);
+            L.circleMarker([pos.coords.latitude, pos.coords.longitude], {
+              radius: 8, color: "#2563eb", fillColor: "#2563eb", fillOpacity: 0.8, weight: 2
+            }).addTo(leafletMap).bindPopup("📍 현재 위치").openPopup();
+          }, () => alert("위치 정보를 가져올 수 없습니다."));
+        });
+        return btn;
+      };
+      return ctrl;
+    };
+    L.control.locate().addTo(leafletMap);
+  }
+
+  // 탭이 보여진 후 지도 크기 재계산
+  setTimeout(() => leafletMap.invalidateSize(), 120);
+}
+
+// ─── 디테일 패널 HTML ───
+function buildDetailHtml(id, list, snucoData, gangyeoData) {
+  // snuco 세부 식당
+  if (id && id.startsWith("snuco_") && id !== "snuco_header") {
+    const idx = parseInt(id.replace("snuco_", ""), 10);
+    if (!snucoData || !snucoData.restaurants) return `<p class="rest-detail-empty">메뉴 정보 없음</p>`;
+    const r = snucoData.restaurants[idx];
+    if (!r) return `<p class="rest-detail-empty">메뉴 정보 없음</p>`;
+
+    const name  = r.name.replace(/\s*\([\d-]+\)\s*$/, "").trim();
+    const phone = (r.name.match(/\(([\d-]+)\)/) || [])[1] || "";
+
+    // 있는 식사 항목 중 내용이 다른 것만 추출 (중복 내용은 탭 안 만듦)
+    const MEAL_DEFS = [
+      { key: "breakfast", label: "조식" },
+      { key: "lunch",     label: "점심" },
+      { key: "dinner",    label: "저녁" },
+    ];
+    const seen = new Set();
+    const available = MEAL_DEFS.filter(m => {
+      const val = r[m.key];
+      if (!val || val === "정보 없음") return false;
+      if (seen.has(val)) return false;
+      seen.add(val);
+      return true;
+    });
+
+    // 표시할 식사 결정 (기본값: 시간 기반, 없으면 첫 번째)
+    let meal = selectedMeal;
+    if (!available.find(m => m.key === meal)) {
+      meal = available[0]?.key || "lunch";
+    }
+
+    const val = r[meal] || "";
+    const content = val
+      ? `<div class="rest-detail-lines">${formatMealLines(val)}</div>`
+      : `<p class="rest-detail-empty">정보 없음</p>`;
+
+    // 식사 구분이 2개 이상일 때만 탭 표시
+    const tabsHtml = available.length >= 2
+      ? `<div class="rest-meal-tabs">${
+          available.map(m =>
+            `<button class="rest-meal-tab${meal === m.key ? " active" : ""}" data-meal="${m.key}">${m.label}</button>`
+          ).join("")
+        }</div>`
+      : "";
+
+    const snucoLoc = getRestaurantLoc(id, name);
+    const snucoNavBtn = snucoLoc
+      ? `<a class="rest-nav-btn" href="${kakaoNavUrl(snucoLoc.lat, snucoLoc.lng, name)}" target="_blank" rel="noopener
">🗺️ 길찾기</a>`
+      : "";
+
+    return `
+      <div class="rest-detail-title">${escapeHtml(name)}</div>
+      ${phone ? `<p class="rest-detail-phone">📞 ${escapeHtml(phone)}</p>` : ""}
+      ${snucoNavBtn}
+      ${tabsHtml}
+      <div class="rest-meal-content">${content}</div>`;
+  }
+
+  // snuco_header 클릭 — 안내 메시지
+  if (id === "snuco_header") {
+    return `<p class="rest-detail-empty">왼쪽에서 세부 식당을 선택하세요.</p>`;
+  }
+
+  // 일반 식당 (강여사집밥, 불당 등)
+  const info = list.find(r => r.id === id);
+  if (!info) return `<p class="rest-detail-empty">정보 없음</p>`;
+
+  const extLoc = getRestaurantLoc(id, info.name);
+  const extNavBtn = extLoc
+    ? `<a class="rest-nav-btn" href="${kakaoNavUrl(extLoc.lat, extLoc.lng, info.name)}" target="_blank" rel="noopener"
>🗺️ 길찾기</a>`
+    : "";
+
+  let html = `<div class="rest-detail-title">${escapeHtml(info.name)}</div>`;
+
+  const openBadge = info.isOpen === true
+    ? `<span class="rest-open">영업중</span>`
+    : info.isOpen === false
+    ? `<span class="rest-closed">영업종료</span>`
+    : "";
+  if (openBadge) html += `<div style="margin-bottom:10px">${openBadge}</div>`;
+  if (extNavBtn) html += `<div style="margin-bottom:10px">${extNavBtn}</div>`;
+
+  const tags = (info.tags || []).map(t => `<span class="rest-tag">${escapeHtml(t)}</span>`).join("");
+  if (tags) html += `<div class="rest-tags" style="margin-bottom:10px">${tags}</div>`;
+
+  if (info.address) html += `<p class="rest-detail-phone">📍 ${escapeHtml(info.address)}</p>`;
+
+  // 운영 시간
+  if (info.hours) {
+    const hoursLines = Object.entries(info.hours).map(([k, v]) => {
+      const label = k === "weekday" ? "평일" : k === "weekend" ? "주말"
+                  : k === "breakfast" ? "조식" : k === "lunch" ? "점심"
+                  : k === "dinner" ? "저녁" : k;
+      return `<span class="rest-menu-time">${label}: ${escapeHtml(v)}</span>`;
+    }).join("");
+    html += `
+      <div class="rest-detail-section">
+        <p class="rest-detail-label">운영 시간</p>
+        <div class="rest-detail-lines">${hoursLines}</div>
+      </div>`;
+  }
+
+  if (info.note) html += `<p class="rest-note" style="margin-top:8px">${escapeHtml(info.note)}</p>`;
+
+  // Instagram 게시물
+  if (info.type === "instagram") {
+    if (!gangyeoData || gangyeoData.needsAuth) {
+      html += `<p class="rest-menu-error" style="margin-top:12px">사장님 Instagram 연동 필요</p>`;
+    } else if (gangyeoData.error) {
+      html += `<p class="rest-menu-error" style="margin-top:12px">메뉴 불러오기 실패</p>`;
+    } else if (gangyeoData.posts && gangyeoData.posts.length > 0) {
+      const post = gangyeoData.posts[0];
+      const caption = post.caption || "";
+      html += `
+        <div class="rest-detail-section">
+          <p class="rest-detail-label">오늘의 메뉴</p>
+          <div class="rest-ig-post">
+            ${post.imageUrl ? `<img class="rest-ig-img" src="${escapeHtml(post.imageUrl)}" alt="오늘의 메뉴" loading="lazy"
>` : ""}
+            <p class="rest-ig-caption">${escapeHtml(caption)}</p>
+            <a class="rest-ig-link" href="${escapeHtml(post.url)}" target="_blank" rel="noopener">Instagram에서 보기 →</a>
+          </div>
+        </div>`;
+    }
+  }
+
+  return html;
+}
+
+// ─── 식사 탭 클릭 처리 ───
+function selectMeal(meal) {
+  selectedMeal = meal;
+  const { list, snucoData, gangyeoData } = restaurantDataCache;
+  // 탭 active 업데이트
+  document.querySelectorAll(".rest-meal-tab").forEach(b => {
+    b.classList.toggle("active", b.dataset.meal === meal);
+  });
+  // 메뉴 내용만 교체
+  const idx = parseInt(selectedRestId.replace("snuco_", ""), 10);
+  const r = snucoData.restaurants[idx];
+  const val = r?.[meal] || "";
+  const content = val
+    ? `<div class="rest-detail-lines">${formatMealLines(val)}</div>`
+    : `<p class="rest-detail-empty">정보 없음</p>`;
+  document.querySelector(".rest-meal-content").innerHTML = content;
+}
+
+// ─── 사이드바 선택 처리 ───
+function selectRestaurant(id) {
+  selectedRestId = id;
+  selectedMeal = getDefaultMeal(); // 식당 바뀌면 시간 기반 기본값으로 리셋
+  // 사이드바 active 표시
+  document.querySelectorAll(".rest-sidebar-item").forEach(el => {
+    el.classList.toggle("active", el.dataset.id === id);
+  });
+  // 디테일 업데이트
+  const { list, snucoData, gangyeoData } = restaurantDataCache;
+  document.getElementById("restDetailPanel").innerHTML = buildDetailHtml(id, list, snucoData, gangyeoData);
+}
+
+// ─── 탭 렌더링 ───
+async function renderRestaurantTab() {
+  if (restaurantFetching) return;
+
+  // 캐시 있으면 재렌더만
+  if (restaurantDataCache) {
+    renderRestaurantLayout();
+    return;
+  }
+
+  restaurantFetching = true;
+  restaurantListEl.innerHTML = `<div class="restaurant-loading">불러오는 중...</div>`;
+
+  try {
+    const [listRes, snucoRes, gangyeoRes] = await Promise.allSettled([
+      fetch(`${SERVER_URL}/api/restaurant/list`).then(r => r.json()),
+      fetch(`${SERVER_URL}/api/restaurant/snuco`).then(r => r.json()),
+      fetch(`${SERVER_URL}/api/restaurant/gangyeo`).then(r => r.json()),
+    ]);
+
+    const list       = listRes.status    === "fulfilled" ? listRes.value    : [];
+    const snucoData  = snucoRes.status   === "fulfilled" ? snucoRes.value   : { error: "실패" };
+    const gangyeoData = gangyeoRes.status === "fulfilled" ? gangyeoRes.value : { error: "실패" };
+
+    if (list.length === 0) {
+      restaurantListEl.innerHTML = `<p class="restaurant-error">식당 정보를 불러오지 못했습니다.</p>`;
+      return;
+    }
+
+    restaurantDataCache = { list, snucoData, gangyeoData };
+    renderRestaurantLayout();
+  } catch (err) {
+    restaurantListEl.innerHTML = `<p class="restaurant-error">오류: ${escapeHtml(err.message)}</p>`;
+  } finally {
+    restaurantFetching = false;
+  }
+}
+
+function renderRestaurantLayout() {
+  const { list, snucoData, gangyeoData } = restaurantDataCache;
+  const items = buildSidebarItems(list, snucoData);
+
+  // 즐겨찾기가 있으면 우선 선택, 없으면 첫 번째 비헤더
+  const validFave = faveRestId && items.find(i => i.id === faveRestId && !i.isHeader);
+  if (!selectedRestId || !items.find(i => i.id === selectedRestId)) {
+    selectedRestId = validFave ? faveRestId : (items.find(i => !i.isHeader)?.id || items[0]?.id);
+  }
+  if (!selectedMeal) selectedMeal = getDefaultMeal();
+
+  const sidebarHtml = items.map(item => {
+    if (item.isHeader) {
+      const dot = item.isOpen === true  ? `<span class="rest-dot open"></span>`
+                : item.isOpen === false ? `<span class="rest-dot closed"></span>`
+                : "";
+      const icon = item.isFaveHeader ? "★ " : "";
+      return `<div class="rest-sidebar-group${item.isFaveHeader ? " fave-group" : ""}">${dot}${icon}${escapeHtml(item.
label)}</div>`;
+    }
+    const dot = item.isOpen === true  ? `<span class="rest-dot open"></span>`
+              : item.isOpen === false ? `<span class="rest-dot closed"></span>`
+              : "";
+    const activeClass = item.id === selectedRestId ? " active" : "";
+    const isFave = item.id === faveRestId;
+    const faveBtn = `<button class="rest-fave-btn${isFave ? " active" : ""}" data-id="${escapeHtml(item.id)}" title="$
{isFave ? "즐겨찾기 해제" : "즐겨찾기"}">${isFave ? "★" : "☆"}</button>`;
+    return `<div class="rest-sidebar-item${activeClass}" data-id="${escapeHtml(item.id)}">${dot}<span class="rest-side
bar-label">${escapeHtml(item.label)}</span>${faveBtn}</div>`;
+  }).join("");
+
+  restaurantListEl.innerHTML = `
+    <div class="rest-layout">
+      <div class="rest-sidebar" id="restSidebar">${sidebarHtml}</div>
+      <div class="rest-detail" id="restDetailPanel">${buildDetailHtml(selectedRestId, list, snucoData, gangyeoData)}</
div>
+    </div>`;
+
+  // 사이드바 클릭 (즐겨찾기 버튼 / 식당 선택 분리)
+  document.getElementById("restSidebar").addEventListener("click", e => {
+    const faveBtn = e.target.closest(".rest-fave-btn");
+    if (faveBtn) { toggleFave(faveBtn.dataset.id); return; }
+    const item = e.target.closest(".rest-sidebar-item");
+    if (item) selectRestaurant(item.dataset.id);
+  });
+
+  // 식사 탭 클릭 (이벤트 위임)
+  document.getElementById("restDetailPanel").addEventListener("click", e => {
+    const tab = e.target.closest(".rest-meal-tab");
+    if (tab) selectMeal(tab.dataset.meal);
+  });
+}
+
+// ──────────────────────────────────────────
+// 다크 모드
+// ──────────────────────────────────────────
+
+const darkModeBtn = document.getElementById("darkModeBtn");
+
+function applyDarkMode(dark) {
+  document.body.classList.toggle("dark", dark);
+  darkModeBtn.textContent = dark ? "☀️ 라이트 모드" : "🌙 다크 모드";
+}
+
+const savedDark = localStorage.getItem("darkMode") === "true"
+  || (localStorage.getItem("darkMode") === null && window.matchMedia("(prefers-color-scheme: dark)").matches);
+applyDarkMode(savedDark);
+
+darkModeBtn.addEventListener("click", () => {
+  const isDark = !document.body.classList.contains("dark");
+  applyDarkMode(isDark);
+  localStorage.setItem("darkMode", isDark);
+});
+
+// ──────────────────────────────────────────
+// 초기화
+// ──────────────────────────────────────────
+
+requestNotificationPermission();
+// 권한이 이미 있으면 서버 재시작 후 구독 복구
+if (Notification.permission === "granted") subscribePush();
+renderTasks();
+renderCompleted();
+checkDeadlines();
+setInterval(checkDeadlines, 60000);
+
+if (icalUrl) {
+  setConnectedUI();
+  if (canvasToken && apiTokenInput) apiTokenInput.value = canvasToken;
+  syncIcal();
+} else {
+  openSettings();
+}
+
+setInterval(() => { if (icalUrl) syncIcal(); }, 10 * 60 * 1000);
+setInterval(() => { fetch(`${SERVER_URL}/health`).catch(() => {}); }, 14 * 60 * 1000);
diff --git a/server/id_tab.png b/server/id_tab.png
new file mode 100644
index 0000000..fb0fba2
Binary files /dev/null and b/server/id_tab.png differ
diff --git a/server/id_tab_clicked.png b/server/id_tab_clicked.png
new file mode 100644
index 0000000..808642c
Binary files /dev/null and b/server/id_tab_clicked.png differ
diff --git a/server/index.js b/server/index.js
new file mode 100644
index 0000000..b942002
--- /dev/null
+++ b/server/index.js
@@ -0,0 +1,641 @@
+const express = require("express");
+const cors = require("cors");
+const ical = require("node-ical");
+const https = require("https");
+const webpush = require("web-push");
+
+// VAPID 설정
+const VAPID_PUBLIC = process.env.VAPID_PUBLIC || "BNHX2y_hSe3MDv1TelFE8LSK6Kg2DY8Aa7gFAjvX9OAIyJu72OerTOMA7PNW3dVf-6lM
9DNUFkI9FOoAh_TTZOg";
+const VAPID_PRIVATE = process.env.VAPID_PRIVATE || "zf1hxNgT-YzntEwS5CycYS9oynMTZeDIqmPlWUMrbU0";
+webpush.setVapidDetails("mailto:admin@snu-app.com", VAPID_PUBLIC, VAPID_PRIVATE);
+
+const app = express();
+const PORT = process.env.PORT || 3001;
+
+app.use(cors({ origin: "*" }));
+app.use(express.json());
+
+// ──────────────────────────────────────────
+// URL fetch (헤더 지원, 리다이렉트 자동 처리, POST 지원)
+// ──────────────────────────────────────────
+function fetchText(url, redirectCount = 0, extraHeaders = {}, method = "GET", body = null) {
+  return new Promise((resolve, reject) => {
+    if (redirectCount > 5) return reject(new Error("리다이렉트가 너무 많습니다."));
+
+    const parsed = new URL(url);
+    const bodyBuf = body ? Buffer.from(body, "utf8") : null;
+    const options = {
+      hostname: parsed.hostname,
+      path: parsed.pathname + parsed.search,
+      method: method,
+      headers: {
+        ...extraHeaders,
+        ...(bodyBuf ? { "Content-Length": bodyBuf.length } : {}),
+      },
+    };
+
+    const req = https.request(options, (res) => {
+      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
+        res.resume();
+        return fetchText(res.headers.location, redirectCount + 1, extraHeaders).then(resolve).catch(reject);
+      }
+      if (res.statusCode !== 200) {
+        res.resume();
+        return reject(new Error(`HTTP ${res.statusCode}`));
+      }
+      res.setEncoding("utf8");
+      let data = "";
+      res.on("data", (chunk) => { data += chunk; });
+      res.on("end", () => resolve(data));
+    });
+
+    req.on("error", reject);
+    req.setTimeout(15000, () => req.destroy(new Error("요청 시간 초과 (15초)")));
+    if (bodyBuf) req.write(bodyBuf);
+    req.end();
+  });
+}
+
+// ──────────────────────────────────────────
+// Canvas API: 제출 여부 확인
+// ──────────────────────────────────────────
+async function isSubmitted(courseId, assignmentId, token) {
+  try {
+    const url = `https://myetl.snu.ac.kr/api/v1/courses/${courseId}/assignments/${assignmentId}/submissions/self`;
+    const text = await fetchText(url, 0, { Authorization: `Bearer ${token}` });
+    const data = JSON.parse(text);
+    return ["submitted", "graded", "pending_review"].includes(data.workflow_state);
+  } catch {
+    return false; // 확인 실패 시 과제 유지 (안전 기본값)
+  }
+}
+
+// ──────────────────────────────────────────
+// Canvas iCal 파싱 유틸
+// ──────────────────────────────────────────
+
+function parseSummary(summary) {
+  const match = (summary || "").match(/^(.*?)\s*\[([^\]]+)\]\s*$/);
+  if (match) return { title: match[1].trim(), courseName: match[2].trim() };
+  return { title: (summary || "").trim(), courseName: "" };
+}
+
+function buildAssignmentUrl(calendarUrl) {
+  if (!calendarUrl) return "";
+  const courseMatch = calendarUrl.match(/include_contexts=course_(\d+)/);
+  const assignMatch = calendarUrl.match(/#assignment_(\d+)/);
+  if (courseMatch && assignMatch) {
+    return `https://myetl.snu.ac.kr/courses/${courseMatch[1]}/assignments/${assignMatch[1]}`;
+  }
+  return calendarUrl;
+}
+
+function parseEventDate(ev) {
+  const start = ev.start;
+  if (!start) return { date: null, dateOnly: false };
+  if (start instanceof Date) {
+    const isDateOnly = ev.start.dateOnly === true || (ev.dtstart && ev.dtstart.includes("VALUE=DATE"));
+    if (isDateOnly) {
+      // node-ical은 VALUE=DATE를 서버 로컬 자정으로 파싱함
+      // eTL은 KST 기준이므로 +9h 보정으로 서버 시간대 무관하게 KST 날짜 추출
+      const kst = new Date(start.getTime() + 9 * 60 * 60 * 1000);
+      const y = kst.getUTCFullYear();
+      const m = kst.getUTCMonth();
+      const d = kst.getUTCDate();
+      const deadline = new Date(Date.UTC(y, m, d, 14, 59, 0));
+      return { date: deadline, dateOnly: false };
+    }
+    return { date: start, dateOnly: false };
+  }
+  return { date: null, dateOnly: false };
+}
+
+// ──────────────────────────────────────────
+// POST /api/sync-ical
+// body: { icalUrl, apiToken? }
+// ──────────────────────────────────────────
+app.post("/api/sync-ical", async (req, res) => {
+  let { icalUrl, apiToken } = req.body;
+
+  if (!icalUrl) {
+    return res.status(400).json({ error: "icalUrl이 필요합니다." });
+  }
+
+  icalUrl = icalUrl.trim().replace(/^webcal:\/\//i, "https://");
+
+  if (!icalUrl.startsWith("https://")) {
+    return res.status(400).json({ error: "유효한 eTL iCal URL을 입력해주세요." });
+  }
+
+  try {
+    console.log(`[sync] fetch: ${icalUrl.slice(0, 70)}...`);
+    const text = await fetchText(icalUrl);
+    console.log(`[sync] 수신: ${text.length} bytes`);
+
+    const events = ical.sync.parseICS(text);
+    const now = new Date();
+    const assignments = [];
+
+    for (const key of Object.keys(events)) {
+      const ev = events[key];
+      if (ev.type !== "VEVENT") continue;
+
+      const { date: dueDate, dateOnly } = parseEventDate(ev);
+      if (!dueDate || isNaN(dueDate.getTime())) continue;
+
+      const diffDays = (dueDate - now) / (1000 * 60 * 60 * 24);
+      if (diffDays < 0 || diffDays > 7) continue;
+
+      const { title, courseName } = parseSummary(ev.summary);
+      if (!title) continue;
+
+      const uidMatch = (ev.uid || "").match(/assignment-(\d+)/);
+      const etlId = uidMatch ? uidMatch[1] : (ev.uid || key).slice(0, 20);
+      const assignmentUrl = buildAssignmentUrl(ev.url);
+
+      const courseMatch = assignmentUrl.match(/courses\/(\d+)/);
+      const assignMatch = assignmentUrl.match(/assignments\/(\d+)/);
+
+      assignments.push({
+        etlId,
+        title,
+        courseName,
+        dueDate: dueDate.toISOString(),
+        dateOnly,
+        url: assignmentUrl,
+        courseId: courseMatch ? courseMatch[1] : null,
+        assignmentId: assignMatch ? assignMatch[1] : null,
+      });
+    }
+
+    // API 토큰이 있으면 제출된 과제 필터링
+    let filtered = assignments;
+    if (apiToken) {
+      console.log(`[sync] 제출 여부 확인 중 (${assignments.length}개)...`);
+      const results = await Promise.all(
+        assignments.map(async (a) => {
+          if (!a.courseId || !a.assignmentId) return true;
+          const submitted = await isSubmitted(a.courseId, a.assignmentId, apiToken);
+          return !submitted;
+        })
+      );
+      filtered = assignments.filter((_, i) => results[i]);
+      console.log(`[sync] 제출 제외 후: ${filtered.length}개`);
+    }
+
+    // courseId/assignmentId는 클라이언트에 불필요하므로 제거
+    const output = filtered.map(({ courseId, assignmentId, ...rest }) => rest);
+
+    output.sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate));
+    console.log(`[sync] 완료: ${output.length}개 과제`);
+    res.json(output);
+
+  } catch (err) {
+    console.error(`[sync] 오류: ${err.message}`);
+    res.status(500).json({ error: `iCal 불러오기 실패: ${err.message}` });
+  }
+});
+
+// ──────────────────────────────────────────
+// 학교 소식 크롤링
+// ──────────────────────────────────────────
+
+const cheerio = require("cheerio");
+
+// 학사일정 기본값 (공식 사이트 크롤링 실패 시 사용)
+const fallbackSchedule = [
+  { title: "봄학기 개강", date: "2026-03-02", source: "snu" },
+  { title: "수강변경 기간", date: "2026-03-02", endDate: "2026-03-13", source: "snu" },
+  { title: "중간고사", date: "2026-04-20", endDate: "2026-04-25", source: "snu" },
+  { title: "수강취소 기간", date: "2026-04-27", endDate: "2026-05-01", source: "snu" },
+  { title: "기말고사", date: "2026-06-15", endDate: "2026-06-20", source: "snu" },
+  { title: "봄학기 종강", date: "2026-06-19", source: "snu" },
+  { title: "관악제", date: "2026-05-12", endDate: "2026-05-14", source: "snu" },
+];
+
+// SNU 공식 이벤트 페이지 크롤링 (YYYY.MM.DD 형식 파싱)
+function parseSnuDate(str) {
+  const m = str.match(/(\d{4})\.(\d{2})\.(\d{2})/);
+  if (!m) return null;
+  return `${m[1]}-${m[2]}-${m[3]}`;
+}
+
+async function fetchSnuEvents() {
+  try {
+    const html = await fetchText("https://www.snu.ac.kr/snunow/events", 0, { "User-Agent": "Mozilla/5.0" });
+    const $ = cheerio.load(html);
+    const items = [];
+    $("span.texts").each((i, el) => {
+      const title = $(el).find("span.title").text().trim();
+      const pointText = $(el).find("span.point").text().trim();
+      if (!title || !pointText) return;
+      const dates = pointText.match(/\d{4}\.\d{2}\.\d{2}/g) || [];
+      const startDate = parseSnuDate(dates[0]);
+      const endDate = dates[1] ? parseSnuDate(dates[1]) : null;
+      if (!startDate) return;
+      items.push({ title, date: startDate, ...(endDate ? { endDate } : {}), source: "snu_events" });
+    });
+    console.log(`[events] SNU 공식 이벤트 ${items.length}개 크롤링 완료`);
+    return items;
+  } catch (err) {
+    console.error("[events] SNU 이벤트 크롤링 오류:", err.message);
+    return [];
+  }
+}
+
+function parseRSS(xml) {
+  const items = [];
+  const itemRegex = /<item>([\s\S]*?)<\/item>/g;
+  let match;
+  while ((match = itemRegex.exec(xml)) !== null) {
+    const block = match[1];
+    const getTag = (tag) => {
+      const m = block.match(new RegExp(`<${tag}>(?:<!\\[CDATA\\[)?([\\s\\S]*?)(?:\\]\\]>)?<\\/${tag}>`));
+      return m ? m[1].trim() : "";
+    };
+    const title = getTag("title");
+    const link = getTag("link") || block.match(/<link\s*\/?>(.*?)<\/link>/)?.[1]?.trim() || "";
+    const pubDate = getTag("pubDate");
+    const category = getTag("category");
+    if (title) items.push({ title, link, pubDate, category });
+  }
+  return items;
+}
+
+async function fetchWeSnuRSS() {
+  try {
+    const xml = await fetchText("https://we.snu.ac.kr/feed/");
+    const items = parseRSS(xml);
+    return items.slice(0, 10).map((item) => ({
+      title: item.title,
+      url: item.link,
+      date: item.pubDate ? new Date(item.pubDate).toISOString() : null,
+      category: item.category || "총학생회",
+      source: "wesnu",
+    }));
+  } catch (err) {
+    console.error("[events] 총학 RSS 오류:", err.message);
+    return [];
+  }
+}
+
+async function fetchDongariNotices() {
+  try {
+    const html = await fetchText("https://dongari.snu.ac.kr/%EA%B3%B5%EC%A7%80%EC%82%AC%ED%95%AD/?mod=list");
+    const $ = cheerio.load(html);
+    const items = [];
+    $("ul.board_body li").each((i, el) => {
+      const title = $(el).find("div.cut-strings").text().trim();
+      const href = $(el).find("div.subject a").attr("href");
+      const date = $(el).find("span.date").text().trim();
+      if (title && date) {
+        items.push({
+          title,
+          url: href ? `https://dongari.snu.ac.kr${href}` : null,
+          date: new Date(date).toISOString(),
+          category: "동아리연합회",
+          source: "dongari",
+        });
+      }
+    });
+    return items.slice(0, 10);
+  } catch (err) {
+    console.error("[events] 동아리연합회 오류:", err.message);
+    return [];
+  }
+}
+
+app.get("/api/events", async (req, res) => {
+  const [wesnu, dongari, snuEvents] = await Promise.all([
+    fetchWeSnuRSS(),
+    fetchDongariNotices(),
+    fetchSnuEvents(),
+  ]);
+
+  const notices = [...wesnu, ...dongari].sort((a, b) => {
+    if (!a.date) return 1;
+    if (!b.date) return -1;
+    return new Date(b.date) - new Date(a.date);
+  });
+
+  // SNU 공식 이벤트가 있으면 사용, 없으면 fallback
+  const schedule = snuEvents.length > 0
+    ? [...fallbackSchedule, ...snuEvents]
+    : fallbackSchedule;
+
+  res.json({ schedule, notices });
+});
+
+// ──────────────────────────────────────────
+// 푸시 알림
+// ──────────────────────────────────────────
+
+// { endpoint → { subscription, tasks: [{etlId, dueDate, title, courseName}] } }
+const pushStore = new Map();
+const sentKeys = new Set(); // "endpoint:etlId:Nh" - 중복 발송 방지
+
+app.get("/api/push/vapid-public-key", (req, res) => {
+  res.json({ key: VAPID_PUBLIC });
+});
+
+app.post("/api/push/subscribe", (req, res) => {
+  const { subscription, tasks } = req.body;
+  if (!subscription?.endpoint) return res.status(400).json({ error: "subscription 필요" });
+  pushStore.set(subscription.endpoint, { subscription, tasks: tasks || [] });
+  console.log(`[push] 구독 등록: ${pushStore.size}개`);
+  res.json({ ok: true });
+});
+
+// 5분마다 알림 체크 (과제: 24h/5h/1h, 사용자 일정: task.targets 사용)
+const DEFAULT_TARGETS = [24, 5, 1];
+setInterval(async () => {
+  const now = new Date();
+  const WINDOW = 6 / 60; // ±6분 허용
+
+  for (const [endpoint, { subscription, tasks }] of pushStore) {
+    for (const task of tasks) {
+      const due = new Date(task.dueDate);
+      const diffH = (due - now) / (1000 * 60 * 60);
+      if (diffH < 0) continue;
+
+      const targets = task.targets || DEFAULT_TARGETS;
+      for (const h of targets) {
+        if (diffH <= h + WINDOW && diffH > h - WINDOW) {
+          const key = `${endpoint}:${task.etlId}:${h}`;
+          if (sentKeys.has(key)) continue;
+          sentKeys.add(key);
+
+          const label = h === 1 ? "1시간" : h === 5 ? "5시간" : "24시간";
+          const name = task.courseName || task.title;
+          const isUserEvent = !!task.targets;
+          try {
+            await webpush.sendNotification(subscription, JSON.stringify({
+              title: isUserEvent ? `📅 일정 ${label} 전` : `📚 마감 ${label} 전`,
+              body: isUserEvent
+                ? `"${name}" 일정이 ${label} 후입니다.`
+                : `${name} 과제 마감이 ${label} 후입니다.`,
+            }));
+            console.log(`[push] 알림 발송: ${name} (${h}h)`);
+          } catch (err) {
+            console.error(`[push] 발송 실패:`, err.message);
+            if (err.statusCode === 410) pushStore.delete(endpoint);
+          }
+        }
+      }
+    }
+  }
+}, 5 * 60 * 1000);
+
+// ──────────────────────────────────────────
+// Instagram 공식 API (OAuth 방식)
+// ──────────────────────────────────────────
+
+const IG_APP_ID     = process.env.IG_APP_ID     || "975791108172537";
+const IG_APP_SECRET = process.env.IG_APP_SECRET || "";
+const IG_REDIRECT   = process.env.IG_REDIRECT   || "https://snu-assignment-server.onrender.com/api/instagram/callback"
;
+
+// 액세스 토큰 저장 (메모리 + 환경변수 폴백)
+// 서버 재시작 후에도 유지되도록 환경변수 IG_ACCESS_TOKEN 사용
+let igAccessToken = process.env.IG_ACCESS_TOKEN || "";
+const igPostCache = new Map(); // 게시물 캐시 (30분)
+
+// ─── OAuth 콜백 (사장님이 승인 후 리다이렉트되는 곳) ───
+app.get("/api/instagram/callback", async (req, res) => {
+  const { code, error } = req.query;
+  if (error || !code) {
+    return res.send("Instagram 연결 실패: " + (error || "코드 없음"));
+  }
+  try {
+    // 단기 토큰 발급
+    const params = new URLSearchParams({
+      client_id:     IG_APP_ID,
+      client_secret: IG_APP_SECRET,
+      grant_type:    "authorization_code",
+      redirect_uri:  IG_REDIRECT,
+      code,
+    });
+    const shortRes = await fetchText(
+      `https://api.instagram.com/oauth/access_token`,
+      0,
+      { "Content-Type": "application/x-www-form-urlencoded" },
+      "POST",
+      params.toString()
+    );
+    const { access_token: shortToken } = JSON.parse(shortRes);
+
+    // 장기 토큰으로 교환 (60일 유효)
+    const longRes = await fetchText(
+      `https://graph.instagram.com/access_token?grant_type=ig_exchange_token&client_secret=${IG_APP_SECRET}&access_tok
en=${shortToken}`
+    );
+    const { access_token: longToken } = JSON.parse(longRes);
+    igAccessToken = longToken;
+
+    console.log("[ig] 액세스 토큰 발급 완료!");
+    console.log("[ig] 토큰 (Render 환경변수 IG_ACCESS_TOKEN에 저장하세요):", longToken);
+    res.send(`
+      <h2>✅ Instagram 연결 완료!</h2>
+      <p>아래 토큰을 Render 환경변수 <b>IG_ACCESS_TOKEN</b>에 저장하세요.</p>
+      <textarea rows="4" cols="80">${longToken}</textarea>
+    `);
+  } catch (err) {
+    console.error("[ig] 토큰 발급 오류:", err.message);
+    res.status(500).send("토큰 발급 실패: " + err.message);
+  }
+});
+
+// ─── 게시물 조회 ───
+async function fetchInstagramPosts() {
+  if (!igAccessToken) throw new Error("액세스 토큰 없음 — 사장님 승인 필요");
+
+  const cached = igPostCache.get("posts");
+  if (cached && Date.now() - cached.fetchedAt < 30 * 60 * 1000) {
+    console.log("[ig] 캐시 사용");
+    return cached.posts;
+  }
+
+  console.log("[ig] Instagram API 요청");
+  const text = await fetchText(
+    `https://graph.instagram.com/v21.0/me/media?fields=id,caption,media_type,media_url,thumbnail_url,timestamp,permali
nk&limit=5&access_token=${igAccessToken}`
+  );
+  const data = JSON.parse(text);
+  if (data.error) throw new Error(data.error.message);
+
+  const posts = (data.data || []).map((p) => ({
+    id:        p.id,
+    url:       p.permalink,
+    imageUrl:  p.media_url || p.thumbnail_url || "",
+    caption:   p.caption || "",
+    date:      p.timestamp,
+  }));
+
+  igPostCache.set("posts", { posts, fetchedAt: Date.now() });
+  console.log(`[ig] 게시물 ${posts.length}개 수집`);
+  return posts;
+}
+
+// ─── 인증 URL 생성 (사장님에게 보낼 링크) ───
+app.get("/api/instagram/auth-url", (req, res) => {
+  const url = `https://www.instagram.com/oauth/authorize?client_id=${IG_APP_ID}&redirect_uri=${encodeURIComponent(IG_R
EDIRECT)}&response_type=code&scope=instagram_business_basic`;
+  res.json({ url });
+});
+
+app.get("/api/instagram/posts", async (req, res) => {
+  try {
+    const posts = await fetchInstagramPosts();
+    res.json(posts);
+  } catch (err) {
+    console.error(`[ig] 오류: ${err.message}`);
+    res.status(500).json({ error: err.message });
+  }
+});
+
+// ──────────────────────────────────────────
+// 식당 메뉴
+// ──────────────────────────────────────────
+
+// ─── SNU 학생식당 (snuco.snu.ac.kr) ───
+const snucoCache = new Map();
+
+async function fetchSnucoMenu() {
+  const cacheKey = new Date().toISOString().slice(0, 10); // 날짜 기준 캐시
+  if (snucoCache.has(cacheKey)) return snucoCache.get(cacheKey);
+
+  const html = await fetchText("https://snuco.snu.ac.kr/ko/foodmenu", 0, { "User-Agent": "Mozilla/5.0" });
+  const $ = cheerio.load(html);
+
+  const restaurants = [];
+
+  // <br> → \n 변환 후 텍스트 추출하는 헬퍼
+  function cellText(el) {
+    // <br> 태그를 줄바꿈으로 치환
+    $(el).find("br").replaceWith("\n");
+    return $(el).text()
+      .split("\n")
+      .map(l => l.trim())
+      .filter(Boolean)
+      .join("\n");
+  }
+
+  // snuco.snu.ac.kr 실제 구조: #celeb-mealtable table.menu-table tbody tr
+  $("#celeb-mealtable table.menu-table tbody tr").each((i, row) => {
+    const name      = $(row).find("td.title").text().trim().replace(/\s+/g, " ");
+    const breakfast = cellText($(row).find("td.breakfast"));
+    const lunch     = cellText($(row).find("td.lunch"));
+    const dinner    = cellText($(row).find("td.dinner"));
+    if (name && (breakfast || lunch || dinner)) {
+      restaurants.push({
+        name,
+        breakfast: breakfast || "",
+        lunch:     lunch     || "정보 없음",
+        dinner:    dinner    || "",
+      });
+    }
+  });
+
+  const result = { restaurants, fetchedAt: new Date().toISOString() };
+  snucoCache.set(cacheKey, result);
+  return result;
+}
+
+app.get("/api/restaurant/snuco", async (req, res) => {
+  try {
+    const data = await fetchSnucoMenu();
+    res.json(data);
+  } catch (err) {
+    console.error("[snuco] 오류:", err.message);
+    res.status(500).json({ error: err.message });
+  }
+});
+
+// ─── 강여사집밥 Instagram 게시물 ───
+app.get("/api/restaurant/gangyeo", async (req, res) => {
+  try {
+    const posts = await fetchInstagramPosts();
+    res.json({ posts });
+  } catch (err) {
+    console.error("[gangyeo] 오류:", err.message);
+    res.status(500).json({ error: err.message, needsAuth: !igAccessToken });
+  }
+});
+
+// ─── 고정 식당 정보 (오픈시간 등) ───
+const RESTAURANTS_INFO = [
+  {
+    id: "gangyeo",
+    name: "강여사집밥",
+    type: "instagram",
+    tags: ["한식", "백반"],
+    address: "서울 관악구 신림로 92-1",
+    hours: { weekday: "11:00–14:00", weekend: "휴무" },
+    instagram: "@sgon1476",
+    note: "매일 메뉴 변동 — 인스타그램 확인",
+  },
+  {
+    id: "snuco",
+    name: "SNU 학생식당",
+    type: "snuco",
+    tags: ["학식", "구내식당"],
+    address: "서울대학교 내",
+    hours: {
+      breakfast: "07:30–09:00",
+      lunch: "11:00–14:00",
+      dinner: "17:00–19:00",
+    },
+    note: "건물마다 운영 시간 상이",
+  },
+  {
+    id: "boodang",
+    name: "불당",
+    type: "static",
+    tags: ["한식", "분식"],
+    address: "서울 관악구 관악로 1",
+    hours: { weekday: "11:00–20:00", weekend: "11:00–17:00" },
+    note: "대학원 기숙사 인근",
+  },
+];
+
+// 현재 오픈 여부 계산
+function isOpenNow(info) {
+  const now = new Date();
+  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000); // UTC→KST
+  const day = kst.getUTCDay(); // 0=일, 6=토
+  const hhmm = kst.getUTCHours() * 100 + kst.getUTCMinutes();
+
+  function parseRange(str) {
+    if (!str || str === "휴무") return null;
+    const m = str.match(/(\d{1,2}):(\d{2})[–\-~](\d{1,2}):(\d{2})/);
+    if (!m) return null;
+    return {
+      open:  parseInt(m[1]) * 100 + parseInt(m[2]),
+      close: parseInt(m[3]) * 100 + parseInt(m[4]),
+    };
+  }
+
+  const hours = info.hours;
+  if (!hours) return null;
+
+  if (info.id === "snuco") {
+    if (day === 0 || day === 6) return false; // 주말 휴무
+    const ranges = [hours.breakfast, hours.lunch, hours.dinner].map(parseRange).filter(Boolean);
+    return ranges.some(r => hhmm >= r.open && hhmm < r.close);
+  }
+
+  const rangeStr = (day === 0 || day === 6) ? (hours.weekend || hours.weekday) : hours.weekday;
+  const r = parseRange(rangeStr);
+  if (!r) return false;
+  return hhmm >= r.open && hhmm < r.close;
+}
+
+app.get("/api/restaurant/list", (req, res) => {
+  const list = RESTAURANTS_INFO.map(r => ({
+    ...r,
+    isOpen: isOpenNow(r),
+  }));
+  res.json(list);
+});
+
+app.get("/health", (req, res) => res.json({ ok: true }));
+
+app.listen(PORT, () => {
+  console.log(`✅ SNU 과제 서버 실행 중: http://localhost:${PORT}`);
+});
diff --git a/server/login_flow.png b/server/login_flow.png
new file mode 100644
index 0000000..6c1bc3d
Binary files /dev/null and b/server/login_flow.png differ
diff --git a/server/login_page.png b/server/login_page.png
new file mode 100644
index 0000000..af89d4a
Binary files /dev/null and b/server/login_page.png differ
diff --git a/server/login_stealth.png b/server/login_stealth.png
new file mode 100644
index 0000000..af89d4a
Binary files /dev/null and b/server/login_stealth.png differ
diff --git a/server/main_page.png b/server/main_page.png
new file mode 100644
index 0000000..c1c8def
Binary files /dev/null and b/server/main_page.png differ
diff --git a/server/package-lock.json b/server/package-lock.json
new file mode 100644
index 0000000..45a4e10
--- /dev/null
+++ b/server/package-lock.json
@@ -0,0 +1,1372 @@
+{
+  "name": "snu-assignment-server",
+  "version": "1.0.0",
+  "lockfileVersion": 3,
+  "requires": true,
+  "packages": {
+    "": {
+      "name": "snu-assignment-server",
+      "version": "1.0.0",
+      "dependencies": {
+        "cheerio": "^1.2.0",
+        "cors": "^2.8.5",
+        "express": "^4.18.2",
+        "node-ical": "^0.26.1",
+        "web-push": "^3.6.7"
+      }
+    },
+    "node_modules/@js-temporal/polyfill": {
+      "version": "0.5.1",
+      "resolved": "https://registry.npmjs.org/@js-temporal/polyfill/-/polyfill-0.5.1.tgz",
+      "integrity": "sha512-hloP58zRVCRSpgDxmqCWJNlizAlUgJFqG2ypq79DCvyv9tHjRYMDOcPFjzfl/A1/YxDvRCZz8wvZvmapQnKwFQ==",
+      "license": "ISC",
+      "dependencies": {
+        "jsbi": "^4.3.0"
+      },
+      "engines": {
+        "node": ">=12"
+      }
+    },
+    "node_modules/accepts": {
+      "version": "1.3.8",
+      "resolved": "https://registry.npmjs.org/accepts/-/accepts-1.3.8.tgz",
+      "integrity": "sha512-PYAthTa2m2VKxuvSD3DPC/Gy+U+sOA1LAuT8mkmRuvw+NACSaeXEQ+NHcVF7rONl6qcaxV3Uuemwawk+7+SJLw==",
+      "license": "MIT",
+      "dependencies": {
+        "mime-types": "~2.1.34",
+        "negotiator": "0.6.3"
+      },
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/agent-base": {
+      "version": "7.1.4",
+      "resolved": "https://registry.npmjs.org/agent-base/-/agent-base-7.1.4.tgz",
+      "integrity": "sha512-MnA+YT8fwfJPgBx3m60MNqakm30XOkyIoH1y6huTQvC0PwZG7ki8NacLBcrPbNoo8vEZy7Jpuk7+jMO+CUovTQ==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 14"
+      }
+    },
+    "node_modules/array-flatten": {
+      "version": "1.1.1",
+      "resolved": "https://registry.npmjs.org/array-flatten/-/array-flatten-1.1.1.tgz",
+      "integrity": "sha512-PCVAQswWemu6UdxsDFFX/+gVeYqKAod3D3UVm91jHwynguOwAvYPhx8nNlM++NqRcK6CxxpUafjmhIdKiHibqg==",
+      "license": "MIT"
+    },
+    "node_modules/asn1.js": {
+      "version": "5.4.1",
+      "resolved": "https://registry.npmjs.org/asn1.js/-/asn1.js-5.4.1.tgz",
+      "integrity": "sha512-+I//4cYPccV8LdmBLiX8CYvf9Sp3vQsrqu2QNXRcrbiWvcx/UdlFiqUJJzxRQxgsZmvhXhn4cSKeSmoFjVdupA==",
+      "license": "MIT",
+      "dependencies": {
+        "bn.js": "^4.0.0",
+        "inherits": "^2.0.1",
+        "minimalistic-assert": "^1.0.0",
+        "safer-buffer": "^2.1.0"
+      }
+    },
+    "node_modules/bn.js": {
+      "version": "4.12.3",
+      "resolved": "https://registry.npmjs.org/bn.js/-/bn.js-4.12.3.tgz",
+      "integrity": "sha512-fGTi3gxV/23FTYdAoUtLYp6qySe2KE3teyZitipKNRuVYcBkoP/bB3guXN/XVKUe9mxCHXnc9C4ocyz8OmgN0g==",
+      "license": "MIT"
+    },
+    "node_modules/body-parser": {
+      "version": "1.20.5",
+      "resolved": "https://registry.npmjs.org/body-parser/-/body-parser-1.20.5.tgz",
+      "integrity": "sha512-3grm+/2tUOvu2cjJkvsIxrv/wVpfXQW4PsQHYm7yk4vfpu7Ekl6nEsYBoJUL6qDwZUx8wUhQ8tR2qz+ad9c9OA==",
+      "license": "MIT",
+      "dependencies": {
+        "bytes": "~3.1.2",
+        "content-type": "~1.0.5",
+        "debug": "2.6.9",
+        "depd": "2.0.0",
+        "destroy": "~1.2.0",
+        "http-errors": "~2.0.1",
+        "iconv-lite": "~0.4.24",
+        "on-finished": "~2.4.1",
+        "qs": "~6.15.1",
+        "raw-body": "~2.5.3",
+        "type-is": "~1.6.18",
+        "unpipe": "~1.0.0"
+      },
+      "engines": {
+        "node": ">= 0.8",
+        "npm": "1.2.8000 || >= 1.4.16"
+      }
+    },
+    "node_modules/body-parser/node_modules/qs": {
+      "version": "6.15.1",
+      "resolved": "https://registry.npmjs.org/qs/-/qs-6.15.1.tgz",
+      "integrity": "sha512-6YHEFRL9mfgcAvql/XhwTvf5jKcOiiupt2FiJxHkiX1z4j7WL8J/jRHYLluORvc1XxB5rV20KoeK00gVJamspg==",
+      "license": "BSD-3-Clause",
+      "dependencies": {
+        "side-channel": "^1.1.0"
+      },
+      "engines": {
+        "node": ">=0.6"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/boolbase": {
+      "version": "1.0.0",
+      "resolved": "https://registry.npmjs.org/boolbase/-/boolbase-1.0.0.tgz",
+      "integrity": "sha512-JZOSA7Mo9sNGB8+UjSgzdLtokWAky1zbztM3WRLCbZ70/3cTANmQmOdR7y2g+J0e2WXywy1yS468tY+IruqEww==",
+      "license": "ISC"
+    },
+    "node_modules/buffer-equal-constant-time": {
+      "version": "1.0.1",
+      "resolved": "https://registry.npmjs.org/buffer-equal-constant-time/-/buffer-equal-constant-time-1.0.1.tgz",
+      "integrity": "sha512-zRpUiDwd/xk6ADqPMATG8vc9VPrkck7T07OIx0gnjmJAnHnTVXNQG3vfvWNuiZIkwu9KrKdA1iJKfsfTVxE6NA==",
+      "license": "BSD-3-Clause"
+    },
+    "node_modules/bytes": {
+      "version": "3.1.2",
+      "resolved": "https://registry.npmjs.org/bytes/-/bytes-3.1.2.tgz",
+      "integrity": "sha512-/Nf7TyzTx6S3yRJObOAV7956r8cr2+Oj8AC5dt8wSP3BQAoeX58NoHyCU8P8zGkNXStjTSi6fzO6F0pBdcYbEg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.8"
+      }
+    },
+    "node_modules/call-bind-apply-helpers": {
+      "version": "1.0.2",
+      "resolved": "https://registry.npmjs.org/call-bind-apply-helpers/-/call-bind-apply-helpers-1.0.2.tgz",
+      "integrity": "sha512-Sp1ablJ0ivDkSzjcaJdxEunN5/XvksFJ2sMBFfq6x0ryhQV/2b/KwFe21cMpmHtPOSij8K99/wSfoEuTObmuMQ==",
+      "license": "MIT",
+      "dependencies": {
+        "es-errors": "^1.3.0",
+        "function-bind": "^1.1.2"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      }
+    },
+    "node_modules/call-bound": {
+      "version": "1.0.4",
+      "resolved": "https://registry.npmjs.org/call-bound/-/call-bound-1.0.4.tgz",
+      "integrity": "sha512-+ys997U96po4Kx/ABpBCqhA9EuxJaQWDQg7295H4hBphv3IZg0boBKuwYpt4YXp6MZ5AmZQnU/tyMTlRpaSejg==",
+      "license": "MIT",
+      "dependencies": {
+        "call-bind-apply-helpers": "^1.0.2",
+        "get-intrinsic": "^1.3.0"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/cheerio": {
+      "version": "1.2.0",
+      "resolved": "https://registry.npmjs.org/cheerio/-/cheerio-1.2.0.tgz",
+      "integrity": "sha512-WDrybc/gKFpTYQutKIK6UvfcuxijIZfMfXaYm8NMsPQxSYvf+13fXUJ4rztGGbJcBQ/GF55gvrZ0Bc0bj/mqvg==",
+      "license": "MIT",
+      "dependencies": {
+        "cheerio-select": "^2.1.0",
+        "dom-serializer": "^2.0.0",
+        "domhandler": "^5.0.3",
+        "domutils": "^3.2.2",
+        "encoding-sniffer": "^0.2.1",
+        "htmlparser2": "^10.1.0",
+        "parse5": "^7.3.0",
+        "parse5-htmlparser2-tree-adapter": "^7.1.0",
+        "parse5-parser-stream": "^7.1.2",
+        "undici": "^7.19.0",
+        "whatwg-mimetype": "^4.0.0"
+      },
+      "engines": {
+        "node": ">=20.18.1"
+      },
+      "funding": {
+        "url": "https://github.com/cheeriojs/cheerio?sponsor=1"
+      }
+    },
+    "node_modules/cheerio-select": {
+      "version": "2.1.0",
+      "resolved": "https://registry.npmjs.org/cheerio-select/-/cheerio-select-2.1.0.tgz",
+      "integrity": "sha512-9v9kG0LvzrlcungtnJtpGNxY+fzECQKhK4EGJX2vByejiMX84MFNQw4UxPJl3bFbTMw+Dfs37XaIkCwTZfLh4g==",
+      "license": "BSD-2-Clause",
+      "dependencies": {
+        "boolbase": "^1.0.0",
+        "css-select": "^5.1.0",
+        "css-what": "^6.1.0",
+        "domelementtype": "^2.3.0",
+        "domhandler": "^5.0.3",
+        "domutils": "^3.0.1"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/fb55"
+      }
+    },
+    "node_modules/content-disposition": {
+      "version": "0.5.4",
+      "resolved": "https://registry.npmjs.org/content-disposition/-/content-disposition-0.5.4.tgz",
+      "integrity": "sha512-FveZTNuGw04cxlAiWbzi6zTAL/lhehaWbTtgluJh4/E95DqMwTmha3KZN1aAWA8cFIhHzMZUvLevkw5Rqk+tSQ==",
+      "license": "MIT",
+      "dependencies": {
+        "safe-buffer": "5.2.1"
+      },
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/content-type": {
+      "version": "1.0.5",
+      "resolved": "https://registry.npmjs.org/content-type/-/content-type-1.0.5.tgz",
+      "integrity": "sha512-nTjqfcBFEipKdXCv4YDQWCfmcLZKm81ldF0pAopTvyrFGVbcR6P/VAAd5G7N+0tTr8QqiU0tFadD6FK4NtJwOA==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/cookie": {
+      "version": "0.7.2",
+      "resolved": "https://registry.npmjs.org/cookie/-/cookie-0.7.2.tgz",
+      "integrity": "sha512-yki5XnKuf750l50uGTllt6kKILY4nQ1eNIQatoXEByZ5dWgnKqbnqmTrBE5B4N7lrMJKQ2ytWMiTO2o0v6Ew/w==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/cookie-signature": {
+      "version": "1.0.7",
+      "resolved": "https://registry.npmjs.org/cookie-signature/-/cookie-signature-1.0.7.tgz",
+      "integrity": "sha512-NXdYc3dLr47pBkpUCHtKSwIOQXLVn8dZEuywboCOJY/osA0wFSLlSawr3KN8qXJEyX66FcONTH8EIlVuK0yyFA==",
+      "license": "MIT"
+    },
+    "node_modules/cors": {
+      "version": "2.8.6",
+      "resolved": "https://registry.npmjs.org/cors/-/cors-2.8.6.tgz",
+      "integrity": "sha512-tJtZBBHA6vjIAaF6EnIaq6laBBP9aq/Y3ouVJjEfoHbRBcHBAHYcMh/w8LDrk2PvIMMq8gmopa5D4V8RmbrxGw==",
+      "license": "MIT",
+      "dependencies": {
+        "object-assign": "^4",
+        "vary": "^1"
+      },
+      "engines": {
+        "node": ">= 0.10"
+      },
+      "funding": {
+        "type": "opencollective",
+        "url": "https://opencollective.com/express"
+      }
+    },
+    "node_modules/css-select": {
+      "version": "5.2.2",
+      "resolved": "https://registry.npmjs.org/css-select/-/css-select-5.2.2.tgz",
+      "integrity": "sha512-TizTzUddG/xYLA3NXodFM0fSbNizXjOKhqiQQwvhlspadZokn1KDy0NZFS0wuEubIYAV5/c1/lAr0TaaFXEXzw==",
+      "license": "BSD-2-Clause",
+      "dependencies": {
+        "boolbase": "^1.0.0",
+        "css-what": "^6.1.0",
+        "domhandler": "^5.0.2",
+        "domutils": "^3.0.1",
+        "nth-check": "^2.0.1"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/fb55"
+      }
+    },
+    "node_modules/css-what": {
+      "version": "6.2.2",
+      "resolved": "https://registry.npmjs.org/css-what/-/css-what-6.2.2.tgz",
+      "integrity": "sha512-u/O3vwbptzhMs3L1fQE82ZSLHQQfto5gyZzwteVIEyeaY5Fc7R4dapF/BvRoSYFeqfBk4m0V1Vafq5Pjv25wvA==",
+      "license": "BSD-2-Clause",
+      "engines": {
+        "node": ">= 6"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/fb55"
+      }
+    },
+    "node_modules/debug": {
+      "version": "2.6.9",
+      "resolved": "https://registry.npmjs.org/debug/-/debug-2.6.9.tgz",
+      "integrity": "sha512-bC7ElrdJaJnPbAP+1EotYvqZsb3ecl5wi6Bfi6BJTUcNowp6cvspg0jXznRTKDjm/E7AdgFBVeAPVMNcKGsHMA==",
+      "license": "MIT",
+      "dependencies": {
+        "ms": "2.0.0"
+      }
+    },
+    "node_modules/depd": {
+      "version": "2.0.0",
+      "resolved": "https://registry.npmjs.org/depd/-/depd-2.0.0.tgz",
+      "integrity": "sha512-g7nH6P6dyDioJogAAGprGpCtVImJhpPk/roCzdb3fIh61/s/nPsfR6onyMwkCAR/OlC3yBC0lESvUoQEAssIrw==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.8"
+      }
+    },
+    "node_modules/destroy": {
+      "version": "1.2.0",
+      "resolved": "https://registry.npmjs.org/destroy/-/destroy-1.2.0.tgz",
+      "integrity": "sha512-2sJGJTaXIIaR1w4iJSNoN0hnMY7Gpc/n8D4qSCJw8QqFWXf7cuAgnEHxBpweaVcPevC2l3KpjYCx3NypQQgaJg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.8",
+        "npm": "1.2.8000 || >= 1.4.16"
+      }
+    },
+    "node_modules/dom-serializer": {
+      "version": "2.0.0",
+      "resolved": "https://registry.npmjs.org/dom-serializer/-/dom-serializer-2.0.0.tgz",
+      "integrity": "sha512-wIkAryiqt/nV5EQKqQpo3SToSOV9J0DnbJqwK7Wv/Trc92zIAYZ4FlMu+JPFW1DfGFt81ZTCGgDEabffXeLyJg==",
+      "license": "MIT",
+      "dependencies": {
+        "domelementtype": "^2.3.0",
+        "domhandler": "^5.0.2",
+        "entities": "^4.2.0"
+      },
+      "funding": {
+        "url": "https://github.com/cheeriojs/dom-serializer?sponsor=1"
+      }
+    },
+    "node_modules/domelementtype": {
+      "version": "2.3.0",
+      "resolved": "https://registry.npmjs.org/domelementtype/-/domelementtype-2.3.0.tgz",
+      "integrity": "sha512-OLETBj6w0OsagBwdXnPdN0cnMfF9opN69co+7ZrbfPGrdpPVNBUj02spi6B1N7wChLQiPn4CSH/zJvXw56gmHw==",
+      "funding": [
+        {
+          "type": "github",
+          "url": "https://github.com/sponsors/fb55"
+        }
+      ],
+      "license": "BSD-2-Clause"
+    },
+    "node_modules/domhandler": {
+      "version": "5.0.3",
+      "resolved": "https://registry.npmjs.org/domhandler/-/domhandler-5.0.3.tgz",
+      "integrity": "sha512-cgwlv/1iFQiFnU96XXgROh8xTeetsnJiDsTc7TYCLFd9+/WNkIqPTxiM/8pSd8VIrhXGTf1Ny1q1hquVqDJB5w==",
+      "license": "BSD-2-Clause",
+      "dependencies": {
+        "domelementtype": "^2.3.0"
+      },
+      "engines": {
+        "node": ">= 4"
+      },
+      "funding": {
+        "url": "https://github.com/fb55/domhandler?sponsor=1"
+      }
+    },
+    "node_modules/domutils": {
+      "version": "3.2.2",
+      "resolved": "https://registry.npmjs.org/domutils/-/domutils-3.2.2.tgz",
+      "integrity": "sha512-6kZKyUajlDuqlHKVX1w7gyslj9MPIXzIFiz/rGu35uC1wMi+kMhQwGhl4lt9unC9Vb9INnY9Z3/ZA3+FhASLaw==",
+      "license": "BSD-2-Clause",
+      "dependencies": {
+        "dom-serializer": "^2.0.0",
+        "domelementtype": "^2.3.0",
+        "domhandler": "^5.0.3"
+      },
+      "funding": {
+        "url": "https://github.com/fb55/domutils?sponsor=1"
+      }
+    },
+    "node_modules/dunder-proto": {
+      "version": "1.0.1",
+      "resolved": "https://registry.npmjs.org/dunder-proto/-/dunder-proto-1.0.1.tgz",
+      "integrity": "sha512-KIN/nDJBQRcXw0MLVhZE9iQHmG68qAVIBg9CqmUYjmQIhgij9U5MFvrqkUL5FbtyyzZuOeOt0zdeRe4UY7ct+A==",
+      "license": "MIT",
+      "dependencies": {
+        "call-bind-apply-helpers": "^1.0.1",
+        "es-errors": "^1.3.0",
+        "gopd": "^1.2.0"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      }
+    },
+    "node_modules/ecdsa-sig-formatter": {
+      "version": "1.0.11",
+      "resolved": "https://registry.npmjs.org/ecdsa-sig-formatter/-/ecdsa-sig-formatter-1.0.11.tgz",
+      "integrity": "sha512-nagl3RYrbNv6kQkeJIpt6NJZy8twLB/2vtz6yN9Z4vRKHN4/QZJIEbqohALSgwKdnksuY3k5Addp5lg8sVoVcQ==",
+      "license": "Apache-2.0",
+      "dependencies": {
+        "safe-buffer": "^5.0.1"
+      }
+    },
+    "node_modules/ee-first": {
+      "version": "1.1.1",
+      "resolved": "https://registry.npmjs.org/ee-first/-/ee-first-1.1.1.tgz",
+      "integrity": "sha512-WMwm9LhRUo+WUaRN+vRuETqG89IgZphVSNkdFgeb6sS/E4OrDIN7t48CAewSHXc6C8lefD8KKfr5vY61brQlow==",
+      "license": "MIT"
+    },
+    "node_modules/encodeurl": {
+      "version": "2.0.0",
+      "resolved": "https://registry.npmjs.org/encodeurl/-/encodeurl-2.0.0.tgz",
+      "integrity": "sha512-Q0n9HRi4m6JuGIV1eFlmvJB7ZEVxu93IrMyiMsGC0lrMJMWzRgx6WGquyfQgZVb31vhGgXnfmPNNXmxnOkRBrg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.8"
+      }
+    },
+    "node_modules/encoding-sniffer": {
+      "version": "0.2.1",
+      "resolved": "https://registry.npmjs.org/encoding-sniffer/-/encoding-sniffer-0.2.1.tgz",
+      "integrity": "sha512-5gvq20T6vfpekVtqrYQsSCFZ1wEg5+wW0/QaZMWkFr6BqD3NfKs0rLCx4rrVlSWJeZb5NBJgVLswK/w2MWU+Gw==",
+      "license": "MIT",
+      "dependencies": {
+        "iconv-lite": "^0.6.3",
+        "whatwg-encoding": "^3.1.1"
+      },
+      "funding": {
+        "url": "https://github.com/fb55/encoding-sniffer?sponsor=1"
+      }
+    },
+    "node_modules/encoding-sniffer/node_modules/iconv-lite": {
+      "version": "0.6.3",
+      "resolved": "https://registry.npmjs.org/iconv-lite/-/iconv-lite-0.6.3.tgz",
+      "integrity": "sha512-4fCk79wshMdzMp2rH06qWrJE4iolqLhCUH+OiuIgU++RB0+94NlDL81atO7GX55uUKueo0txHNtvEyI6D7WdMw==",
+      "license": "MIT",
+      "dependencies": {
+        "safer-buffer": ">= 2.1.2 < 3.0.0"
+      },
+      "engines": {
+        "node": ">=0.10.0"
+      }
+    },
+    "node_modules/entities": {
+      "version": "4.5.0",
+      "resolved": "https://registry.npmjs.org/entities/-/entities-4.5.0.tgz",
+      "integrity": "sha512-V0hjH4dGPh9Ao5p0MoRY6BVqtwCjhz6vI5LT8AJ55H+4g9/4vbHx1I54fS0XuclLhDHArPQCiMjDxjaL8fPxhw==",
+      "license": "BSD-2-Clause",
+      "engines": {
+        "node": ">=0.12"
+      },
+      "funding": {
+        "url": "https://github.com/fb55/entities?sponsor=1"
+      }
+    },
+    "node_modules/es-define-property": {
+      "version": "1.0.1",
+      "resolved": "https://registry.npmjs.org/es-define-property/-/es-define-property-1.0.1.tgz",
+      "integrity": "sha512-e3nRfgfUZ4rNGL232gUgX06QNyyez04KdjFrF+LTRoOXmrOgFKDg4BCdsjW8EnT69eqdYGmRpJwiPVYNrCaW3g==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.4"
+      }
+    },
+    "node_modules/es-errors": {
+      "version": "1.3.0",
+      "resolved": "https://registry.npmjs.org/es-errors/-/es-errors-1.3.0.tgz",
+      "integrity": "sha512-Zf5H2Kxt2xjTvbJvP2ZWLEICxA6j+hAmMzIlypy4xcBg1vKVnx89Wy0GbS+kf5cwCVFFzdCFh2XSCFNULS6csw==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.4"
+      }
+    },
+    "node_modules/es-object-atoms": {
+      "version": "1.1.1",
+      "resolved": "https://registry.npmjs.org/es-object-atoms/-/es-object-atoms-1.1.1.tgz",
+      "integrity": "sha512-FGgH2h8zKNim9ljj7dankFPcICIK9Cp5bm+c2gQSYePhpaG5+esrLODihIorn+Pe6FGJzWhXQotPv73jTaldXA==",
+      "license": "MIT",
+      "dependencies": {
+        "es-errors": "^1.3.0"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      }
+    },
+    "node_modules/escape-html": {
+      "version": "1.0.3",
+      "resolved": "https://registry.npmjs.org/escape-html/-/escape-html-1.0.3.tgz",
+      "integrity": "sha512-NiSupZ4OeuGwr68lGIeym/ksIZMJodUGOSCZ/FSnTxcrekbvqrgdUxlJOMpijaKZVjAJrWrGs/6Jy8OMuyj9ow==",
+      "license": "MIT"
+    },
+    "node_modules/etag": {
+      "version": "1.8.1",
+      "resolved": "https://registry.npmjs.org/etag/-/etag-1.8.1.tgz",
+      "integrity": "sha512-aIL5Fx7mawVa300al2BnEE4iNvo1qETxLrPI/o05L7z6go7fCw1J6EQmbK4FmJ2AS7kgVF/KEZWufBfdClMcPg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/express": {
+      "version": "4.22.1",
+      "resolved": "https://registry.npmjs.org/express/-/express-4.22.1.tgz",
+      "integrity": "sha512-F2X8g9P1X7uCPZMA3MVf9wcTqlyNp7IhH5qPCI0izhaOIYXaW9L535tGA3qmjRzpH+bZczqq7hVKxTR4NWnu+g==",
+      "license": "MIT",
+      "dependencies": {
+        "accepts": "~1.3.8",
+        "array-flatten": "1.1.1",
+        "body-parser": "~1.20.3",
+        "content-disposition": "~0.5.4",
+        "content-type": "~1.0.4",
+        "cookie": "~0.7.1",
+        "cookie-signature": "~1.0.6",
+        "debug": "2.6.9",
+        "depd": "2.0.0",
+        "encodeurl": "~2.0.0",
+        "escape-html": "~1.0.3",
+        "etag": "~1.8.1",
+        "finalhandler": "~1.3.1",
+        "fresh": "~0.5.2",
+        "http-errors": "~2.0.0",
+        "merge-descriptors": "1.0.3",
+        "methods": "~1.1.2",
+        "on-finished": "~2.4.1",
+        "parseurl": "~1.3.3",
+        "path-to-regexp": "~0.1.12",
+        "proxy-addr": "~2.0.7",
+        "qs": "~6.14.0",
+        "range-parser": "~1.2.1",
+        "safe-buffer": "5.2.1",
+        "send": "~0.19.0",
+        "serve-static": "~1.16.2",
+        "setprototypeof": "1.2.0",
+        "statuses": "~2.0.1",
+        "type-is": "~1.6.18",
+        "utils-merge": "1.0.1",
+        "vary": "~1.1.2"
+      },
+      "engines": {
+        "node": ">= 0.10.0"
+      },
+      "funding": {
+        "type": "opencollective",
+        "url": "https://opencollective.com/express"
+      }
+    },
+    "node_modules/finalhandler": {
+      "version": "1.3.2",
+      "resolved": "https://registry.npmjs.org/finalhandler/-/finalhandler-1.3.2.tgz",
+      "integrity": "sha512-aA4RyPcd3badbdABGDuTXCMTtOneUCAYH/gxoYRTZlIJdF0YPWuGqiAsIrhNnnqdXGswYk6dGujem4w80UJFhg==",
+      "license": "MIT",
+      "dependencies": {
+        "debug": "2.6.9",
+        "encodeurl": "~2.0.0",
+        "escape-html": "~1.0.3",
+        "on-finished": "~2.4.1",
+        "parseurl": "~1.3.3",
+        "statuses": "~2.0.2",
+        "unpipe": "~1.0.0"
+      },
+      "engines": {
+        "node": ">= 0.8"
+      }
+    },
+    "node_modules/forwarded": {
+      "version": "0.2.0",
+      "resolved": "https://registry.npmjs.org/forwarded/-/forwarded-0.2.0.tgz",
+      "integrity": "sha512-buRG0fpBtRHSTCOASe6hD258tEubFoRLb4ZNA6NxMVHNw2gOcwHo9wyablzMzOA5z9xA9L1KNjk/Nt6MT9aYow==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/fresh": {
+      "version": "0.5.2",
+      "resolved": "https://registry.npmjs.org/fresh/-/fresh-0.5.2.tgz",
+      "integrity": "sha512-zJ2mQYM18rEFOudeV4GShTGIQ7RbzA7ozbU9I/XBpm7kqgMywgmylMwXHxZJmkVoYkna9d2pVXVXPdYTP9ej8Q==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/function-bind": {
+      "version": "1.1.2",
+      "resolved": "https://registry.npmjs.org/function-bind/-/function-bind-1.1.2.tgz",
+      "integrity": "sha512-7XHNxH7qX9xG5mIwxkhumTox/MIRNcOgDrxWsMt2pAr23WHp6MrRlN7FBSFpCpr+oVO0F744iUgR82nJMfG2SA==",
+      "license": "MIT",
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/get-intrinsic": {
+      "version": "1.3.0",
+      "resolved": "https://registry.npmjs.org/get-intrinsic/-/get-intrinsic-1.3.0.tgz",
+      "integrity": "sha512-9fSjSaos/fRIVIp+xSJlE6lfwhES7LNtKaCBIamHsjr2na1BiABJPo0mOjjz8GJDURarmCPGqaiVg5mfjb98CQ==",
+      "license": "MIT",
+      "dependencies": {
+        "call-bind-apply-helpers": "^1.0.2",
+        "es-define-property": "^1.0.1",
+        "es-errors": "^1.3.0",
+        "es-object-atoms": "^1.1.1",
+        "function-bind": "^1.1.2",
+        "get-proto": "^1.0.1",
+        "gopd": "^1.2.0",
+        "has-symbols": "^1.1.0",
+        "hasown": "^2.0.2",
+        "math-intrinsics": "^1.1.0"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/get-proto": {
+      "version": "1.0.1",
+      "resolved": "https://registry.npmjs.org/get-proto/-/get-proto-1.0.1.tgz",
+      "integrity": "sha512-sTSfBjoXBp89JvIKIefqw7U2CCebsc74kiY6awiGogKtoSGbgjYE/G/+l9sF3MWFPNc9IcoOC4ODfKHfxFmp0g==",
+      "license": "MIT",
+      "dependencies": {
+        "dunder-proto": "^1.0.1",
+        "es-object-atoms": "^1.0.0"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      }
+    },
+    "node_modules/gopd": {
+      "version": "1.2.0",
+      "resolved": "https://registry.npmjs.org/gopd/-/gopd-1.2.0.tgz",
+      "integrity": "sha512-ZUKRh6/kUFoAiTAtTYPZJ3hw9wNxx+BIBOijnlG9PnrJsCcSjs1wyyD6vJpaYtgnzDrKYRSqf3OO6Rfa93xsRg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.4"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/has-symbols": {
+      "version": "1.1.0",
+      "resolved": "https://registry.npmjs.org/has-symbols/-/has-symbols-1.1.0.tgz",
+      "integrity": "sha512-1cDNdwJ2Jaohmb3sg4OmKaMBwuC48sYni5HUw2DvsC8LjGTLK9h+eb1X6RyuOHe4hT0ULCW68iomhjUoKUqlPQ==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.4"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/hasown": {
+      "version": "2.0.3",
+      "resolved": "https://registry.npmjs.org/hasown/-/hasown-2.0.3.tgz",
+      "integrity": "sha512-ej4AhfhfL2Q2zpMmLo7U1Uv9+PyhIZpgQLGT1F9miIGmiCJIoCgSmczFdrc97mWT4kVY72KA+WnnhJ5pghSvSg==",
+      "license": "MIT",
+      "dependencies": {
+        "function-bind": "^1.1.2"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      }
+    },
+    "node_modules/htmlparser2": {
+      "version": "10.1.0",
+      "resolved": "https://registry.npmjs.org/htmlparser2/-/htmlparser2-10.1.0.tgz",
+      "integrity": "sha512-VTZkM9GWRAtEpveh7MSF6SjjrpNVNNVJfFup7xTY3UpFtm67foy9HDVXneLtFVt4pMz5kZtgNcvCniNFb1hlEQ==",
+      "funding": [
+        "https://github.com/fb55/htmlparser2?sponsor=1",
+        {
+          "type": "github",
+          "url": "https://github.com/sponsors/fb55"
+        }
+      ],
+      "license": "MIT",
+      "dependencies": {
+        "domelementtype": "^2.3.0",
+        "domhandler": "^5.0.3",
+        "domutils": "^3.2.2",
+        "entities": "^7.0.1"
+      }
+    },
+    "node_modules/htmlparser2/node_modules/entities": {
+      "version": "7.0.1",
+      "resolved": "https://registry.npmjs.org/entities/-/entities-7.0.1.tgz",
+      "integrity": "sha512-TWrgLOFUQTH994YUyl1yT4uyavY5nNB5muff+RtWaqNVCAK408b5ZnnbNAUEWLTCpum9w6arT70i1XdQ4UeOPA==",
+      "license": "BSD-2-Clause",
+      "engines": {
+        "node": ">=0.12"
+      },
+      "funding": {
+        "url": "https://github.com/fb55/entities?sponsor=1"
+      }
+    },
+    "node_modules/http_ece": {
+      "version": "1.2.0",
+      "resolved": "https://registry.npmjs.org/http_ece/-/http_ece-1.2.0.tgz",
+      "integrity": "sha512-JrF8SSLVmcvc5NducxgyOrKXe3EsyHMgBFgSaIUGmArKe+rwr0uphRkRXvwiom3I+fpIfoItveHrfudL8/rxuA==",
+      "license": "MIT",
+      "engines": {
+        "node": ">=16"
+      }
+    },
+    "node_modules/http-errors": {
+      "version": "2.0.1",
+      "resolved": "https://registry.npmjs.org/http-errors/-/http-errors-2.0.1.tgz",
+      "integrity": "sha512-4FbRdAX+bSdmo4AUFuS0WNiPz8NgFt+r8ThgNWmlrjQjt1Q7ZR9+zTlce2859x4KSXrwIsaeTqDoKQmtP8pLmQ==",
+      "license": "MIT",
+      "dependencies": {
+        "depd": "~2.0.0",
+        "inherits": "~2.0.4",
+        "setprototypeof": "~1.2.0",
+        "statuses": "~2.0.2",
+        "toidentifier": "~1.0.1"
+      },
+      "engines": {
+        "node": ">= 0.8"
+      },
+      "funding": {
+        "type": "opencollective",
+        "url": "https://opencollective.com/express"
+      }
+    },
+    "node_modules/https-proxy-agent": {
+      "version": "7.0.6",
+      "resolved": "https://registry.npmjs.org/https-proxy-agent/-/https-proxy-agent-7.0.6.tgz",
+      "integrity": "sha512-vK9P5/iUfdl95AI+JVyUuIcVtd4ofvtrOr3HNtM2yxC9bnMbEdp3x01OhQNnjb8IJYi38VlTE3mBXwcfvywuSw==",
+      "license": "MIT",
+      "dependencies": {
+        "agent-base": "^7.1.2",
+        "debug": "4"
+      },
+      "engines": {
+        "node": ">= 14"
+      }
+    },
+    "node_modules/https-proxy-agent/node_modules/debug": {
+      "version": "4.4.3",
+      "resolved": "https://registry.npmjs.org/debug/-/debug-4.4.3.tgz",
+      "integrity": "sha512-RGwwWnwQvkVfavKVt22FGLw+xYSdzARwm0ru6DhTVA3umU5hZc28V3kO4stgYryrTlLpuvgI9GiijltAjNbcqA==",
+      "license": "MIT",
+      "dependencies": {
+        "ms": "^2.1.3"
+      },
+      "engines": {
+        "node": ">=6.0"
+      },
+      "peerDependenciesMeta": {
+        "supports-color": {
+          "optional": true
+        }
+      }
+    },
+    "node_modules/https-proxy-agent/node_modules/ms": {
+      "version": "2.1.3",
+      "resolved": "https://registry.npmjs.org/ms/-/ms-2.1.3.tgz",
+      "integrity": "sha512-6FlzubTLZG3J2a/NVCAleEhjzq5oxgHyaCU9yYXvcLsvoVaHJq/s5xXI6/XXP6tz7R9xAOtHnSO/tXtF3WRTlA==",
+      "license": "MIT"
+    },
+    "node_modules/iconv-lite": {
+      "version": "0.4.24",
+      "resolved": "https://registry.npmjs.org/iconv-lite/-/iconv-lite-0.4.24.tgz",
+      "integrity": "sha512-v3MXnZAcvnywkTUEZomIActle7RXXeedOR31wwl7VlyoXO4Qi9arvSenNQWne1TcRwhCL1HwLI21bEqdpj8/rA==",
+      "license": "MIT",
+      "dependencies": {
+        "safer-buffer": ">= 2.1.2 < 3"
+      },
+      "engines": {
+        "node": ">=0.10.0"
+      }
+    },
+    "node_modules/inherits": {
+      "version": "2.0.4",
+      "resolved": "https://registry.npmjs.org/inherits/-/inherits-2.0.4.tgz",
+      "integrity": "sha512-k/vGaX4/Yla3WzyMCvTQOXYeIHvqOKtnqBduzTHpzpQZzAskKMhZ2K+EnBiSM9zGSoIFeMpXKxa4dYeZIQqewQ==",
+      "license": "ISC"
+    },
+    "node_modules/ipaddr.js": {
+      "version": "1.9.1",
+      "resolved": "https://registry.npmjs.org/ipaddr.js/-/ipaddr.js-1.9.1.tgz",
+      "integrity": "sha512-0KI/607xoxSToH7GjN1FfSbLoU0+btTicjsQSWQlh/hZykN8KpmMf7uYwPW3R+akZ6R/w18ZlXSHBYXiYUPO3g==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.10"
+      }
+    },
+    "node_modules/jsbi": {
+      "version": "4.3.2",
+      "resolved": "https://registry.npmjs.org/jsbi/-/jsbi-4.3.2.tgz",
+      "integrity": "sha512-9fqMSQbhJykSeii05nxKl4m6Eqn2P6rOlYiS+C5Dr/HPIU/7yZxu5qzbs40tgaFORiw2Amd0mirjxatXYMkIew==",
+      "license": "Apache-2.0"
+    },
+    "node_modules/jwa": {
+      "version": "2.0.1",
+      "resolved": "https://registry.npmjs.org/jwa/-/jwa-2.0.1.tgz",
+      "integrity": "sha512-hRF04fqJIP8Abbkq5NKGN0Bbr3JxlQ+qhZufXVr0DvujKy93ZCbXZMHDL4EOtodSbCWxOqR8MS1tXA5hwqCXDg==",
+      "license": "MIT",
+      "dependencies": {
+        "buffer-equal-constant-time": "^1.0.1",
+        "ecdsa-sig-formatter": "1.0.11",
+        "safe-buffer": "^5.0.1"
+      }
+    },
+    "node_modules/jws": {
+      "version": "4.0.1",
+      "resolved": "https://registry.npmjs.org/jws/-/jws-4.0.1.tgz",
+      "integrity": "sha512-EKI/M/yqPncGUUh44xz0PxSidXFr/+r0pA70+gIYhjv+et7yxM+s29Y+VGDkovRofQem0fs7Uvf4+YmAdyRduA==",
+      "license": "MIT",
+      "dependencies": {
+        "jwa": "^2.0.1",
+        "safe-buffer": "^5.0.1"
+      }
+    },
+    "node_modules/math-intrinsics": {
+      "version": "1.1.0",
+      "resolved": "https://registry.npmjs.org/math-intrinsics/-/math-intrinsics-1.1.0.tgz",
+      "integrity": "sha512-/IXtbwEk5HTPyEwyKX6hGkYXxM9nbj64B+ilVJnC/R6B0pH5G4V3b0pVbL7DBj4tkhBAppbQUlf6F6Xl9LHu1g==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.4"
+      }
+    },
+    "node_modules/media-typer": {
+      "version": "0.3.0",
+      "resolved": "https://registry.npmjs.org/media-typer/-/media-typer-0.3.0.tgz",
+      "integrity": "sha512-dq+qelQ9akHpcOl/gUVRTxVIOkAJ1wR3QAvb4RsVjS8oVoFjDGTc679wJYmUmknUF5HwMLOgb5O+a3KxfWapPQ==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/merge-descriptors": {
+      "version": "1.0.3",
+      "resolved": "https://registry.npmjs.org/merge-descriptors/-/merge-descriptors-1.0.3.tgz",
+      "integrity": "sha512-gaNvAS7TZ897/rVaZ0nMtAyxNyi/pdbjbAwUpFQpN70GqnVfOiXpeUUMKRBmzXaSQ8DdTX4/0ms62r2K+hE6mQ==",
+      "license": "MIT",
+      "funding": {
+        "url": "https://github.com/sponsors/sindresorhus"
+      }
+    },
+    "node_modules/methods": {
+      "version": "1.1.2",
+      "resolved": "https://registry.npmjs.org/methods/-/methods-1.1.2.tgz",
+      "integrity": "sha512-iclAHeNqNm68zFtnZ0e+1L2yUIdvzNoauKU4WBA3VvH/vPFieF7qfRlwUZU+DA9P9bPXIS90ulxoUoCH23sV2w==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/mime": {
+      "version": "1.6.0",
+      "resolved": "https://registry.npmjs.org/mime/-/mime-1.6.0.tgz",
+      "integrity": "sha512-x0Vn8spI+wuJ1O6S7gnbaQg8Pxh4NNHb7KSINmEWKiPE4RKOplvijn+NkmYmmRgP68mc70j2EbeTFRsrswaQeg==",
+      "license": "MIT",
+      "bin": {
+        "mime": "cli.js"
+      },
+      "engines": {
+        "node": ">=4"
+      }
+    },
+    "node_modules/mime-db": {
+      "version": "1.52.0",
+      "resolved": "https://registry.npmjs.org/mime-db/-/mime-db-1.52.0.tgz",
+      "integrity": "sha512-sPU4uV7dYlvtWJxwwxHD0PuihVNiE7TyAbQ5SWxDCB9mUYvOgroQOwYQQOKPJ8CIbE+1ETVlOoK1UC2nU3gYvg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/mime-types": {
+      "version": "2.1.35",
+      "resolved": "https://registry.npmjs.org/mime-types/-/mime-types-2.1.35.tgz",
+      "integrity": "sha512-ZDY+bPm5zTTF+YpCrAU9nK0UgICYPT0QtT1NZWFv4s++TNkcgVaT0g6+4R2uI4MjQjzysHB1zxuWL50hzaeXiw==",
+      "license": "MIT",
+      "dependencies": {
+        "mime-db": "1.52.0"
+      },
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/minimalistic-assert": {
+      "version": "1.0.1",
+      "resolved": "https://registry.npmjs.org/minimalistic-assert/-/minimalistic-assert-1.0.1.tgz",
+      "integrity": "sha512-UtJcAD4yEaGtjPezWuO9wC4nwUnVH/8/Im3yEHQP4b67cXlD/Qr9hdITCU1xDbSEXg2XKNaP8jsReV7vQd00/A==",
+      "license": "ISC"
+    },
+    "node_modules/minimist": {
+      "version": "1.2.8",
+      "resolved": "https://registry.npmjs.org/minimist/-/minimist-1.2.8.tgz",
+      "integrity": "sha512-2yyAR8qBkN3YuheJanUpWC5U3bb5osDywNB8RzDVlDwDHbocAJveqqj1u8+SVD7jkWT4yvsHCpWqqWqAxb0zCA==",
+      "license": "MIT",
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/ms": {
+      "version": "2.0.0",
+      "resolved": "https://registry.npmjs.org/ms/-/ms-2.0.0.tgz",
+      "integrity": "sha512-Tpp60P6IUJDTuOq/5Z8cdskzJujfwqfOTkrwIwj7IRISpnkJnT6SyJ4PCPnGMoFjC9ddhal5KVIYtAt97ix05A==",
+      "license": "MIT"
+    },
+    "node_modules/negotiator": {
+      "version": "0.6.3",
+      "resolved": "https://registry.npmjs.org/negotiator/-/negotiator-0.6.3.tgz",
+      "integrity": "sha512-+EUsqGPLsM+j/zdChZjsnX51g4XrHFOIXwfnCVPGlQk/k5giakcKsuxCObBRu6DSm9opw/O6slWbJdghQM4bBg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/node-ical": {
+      "version": "0.26.1",
+      "resolved": "https://registry.npmjs.org/node-ical/-/node-ical-0.26.1.tgz",
+      "integrity": "sha512-KoYLpsz7Ga9lPDpt9vy0iKcgcb/9Ix7ICRZd0csLXMl2lZOSONGj7HrcktJFR7Jid1l44Zu1H4k/1nB04rWPgQ==",
+      "license": "Apache-2.0",
+      "dependencies": {
+        "rrule-temporal": "^1.5.3",
+        "temporal-polyfill": "^0.3.2"
+      },
+      "engines": {
+        "node": ">=20"
+      }
+    },
+    "node_modules/nth-check": {
+      "version": "2.1.1",
+      "resolved": "https://registry.npmjs.org/nth-check/-/nth-check-2.1.1.tgz",
+      "integrity": "sha512-lqjrjmaOoAnWfMmBPL+XNnynZh2+swxiX3WUE0s4yEHI6m+AwrK2UZOimIRl3X/4QctVqS8AiZjFqyOGrMXb/w==",
+      "license": "BSD-2-Clause",
+      "dependencies": {
+        "boolbase": "^1.0.0"
+      },
+      "funding": {
+        "url": "https://github.com/fb55/nth-check?sponsor=1"
+      }
+    },
+    "node_modules/object-assign": {
+      "version": "4.1.1",
+      "resolved": "https://registry.npmjs.org/object-assign/-/object-assign-4.1.1.tgz",
+      "integrity": "sha512-rJgTQnkUnH1sFw8yT6VSU3zD3sWmu6sZhIseY8VX+GRu3P6F7Fu+JNDoXfklElbLJSnc3FUQHVe4cU5hj+BcUg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">=0.10.0"
+      }
+    },
+    "node_modules/object-inspect": {
+      "version": "1.13.4",
+      "resolved": "https://registry.npmjs.org/object-inspect/-/object-inspect-1.13.4.tgz",
+      "integrity": "sha512-W67iLl4J2EXEGTbfeHCffrjDfitvLANg0UlX3wFUUSTx92KXRFegMHUVgSqE+wvhAbi4WqjGg9czysTV2Epbew==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.4"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/on-finished": {
+      "version": "2.4.1",
+      "resolved": "https://registry.npmjs.org/on-finished/-/on-finished-2.4.1.tgz",
+      "integrity": "sha512-oVlzkg3ENAhCk2zdv7IJwd/QUD4z2RxRwpkcGY8psCVcCYZNq4wYnVWALHM+brtuJjePWiYF/ClmuDr8Ch5+kg==",
+      "license": "MIT",
+      "dependencies": {
+        "ee-first": "1.1.1"
+      },
+      "engines": {
+        "node": ">= 0.8"
+      }
+    },
+    "node_modules/parse5": {
+      "version": "7.3.0",
+      "resolved": "https://registry.npmjs.org/parse5/-/parse5-7.3.0.tgz",
+      "integrity": "sha512-IInvU7fabl34qmi9gY8XOVxhYyMyuH2xUNpb2q8/Y+7552KlejkRvqvD19nMoUW/uQGGbqNpA6Tufu5FL5BZgw==",
+      "license": "MIT",
+      "dependencies": {
+        "entities": "^6.0.0"
+      },
+      "funding": {
+        "url": "https://github.com/inikulin/parse5?sponsor=1"
+      }
+    },
+    "node_modules/parse5-htmlparser2-tree-adapter": {
+      "version": "7.1.0",
+      "resolved": "https://registry.npmjs.org/parse5-htmlparser2-tree-adapter/-/parse5-htmlparser2-tree-adapter-7.1.0.
tgz",
+      "integrity": "sha512-ruw5xyKs6lrpo9x9rCZqZZnIUntICjQAd0Wsmp396Ul9lN/h+ifgVV1x1gZHi8euej6wTfpqX8j+BFQxF0NS/g==",
+      "license": "MIT",
+      "dependencies": {
+        "domhandler": "^5.0.3",
+        "parse5": "^7.0.0"
+      },
+      "funding": {
+        "url": "https://github.com/inikulin/parse5?sponsor=1"
+      }
+    },
+    "node_modules/parse5-parser-stream": {
+      "version": "7.1.2",
+      "resolved": "https://registry.npmjs.org/parse5-parser-stream/-/parse5-parser-stream-7.1.2.tgz",
+      "integrity": "sha512-JyeQc9iwFLn5TbvvqACIF/VXG6abODeB3Fwmv/TGdLk2LfbWkaySGY72at4+Ty7EkPZj854u4CrICqNk2qIbow==",
+      "license": "MIT",
+      "dependencies": {
+        "parse5": "^7.0.0"
+      },
+      "funding": {
+        "url": "https://github.com/inikulin/parse5?sponsor=1"
+      }
+    },
+    "node_modules/parse5/node_modules/entities": {
+      "version": "6.0.1",
+      "resolved": "https://registry.npmjs.org/entities/-/entities-6.0.1.tgz",
+      "integrity": "sha512-aN97NXWF6AWBTahfVOIrB/NShkzi5H7F9r1s9mD3cDj4Ko5f2qhhVoYMibXF7GlLveb/D2ioWay8lxI97Ven3g==",
+      "license": "BSD-2-Clause",
+      "engines": {
+        "node": ">=0.12"
+      },
+      "funding": {
+        "url": "https://github.com/fb55/entities?sponsor=1"
+      }
+    },
+    "node_modules/parseurl": {
+      "version": "1.3.3",
+      "resolved": "https://registry.npmjs.org/parseurl/-/parseurl-1.3.3.tgz",
+      "integrity": "sha512-CiyeOxFT/JZyN5m0z9PfXw4SCBJ6Sygz1Dpl0wqjlhDEGGBP1GnsUVEL0p63hoG1fcj3fHynXi9NYO4nWOL+qQ==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.8"
+      }
+    },
+    "node_modules/path-to-regexp": {
+      "version": "0.1.13",
+      "resolved": "https://registry.npmjs.org/path-to-regexp/-/path-to-regexp-0.1.13.tgz",
+      "integrity": "sha512-A/AGNMFN3c8bOlvV9RreMdrv7jsmF9XIfDeCd87+I8RNg6s78BhJxMu69NEMHBSJFxKidViTEdruRwEk/WIKqA==",
+      "license": "MIT"
+    },
+    "node_modules/proxy-addr": {
+      "version": "2.0.7",
+      "resolved": "https://registry.npmjs.org/proxy-addr/-/proxy-addr-2.0.7.tgz",
+      "integrity": "sha512-llQsMLSUDUPT44jdrU/O37qlnifitDP+ZwrmmZcoSKyLKvtZxpyV0n2/bD/N4tBAAZ/gJEdZU7KMraoK1+XYAg==",
+      "license": "MIT",
+      "dependencies": {
+        "forwarded": "0.2.0",
+        "ipaddr.js": "1.9.1"
+      },
+      "engines": {
+        "node": ">= 0.10"
+      }
+    },
+    "node_modules/qs": {
+      "version": "6.14.2",
+      "resolved": "https://registry.npmjs.org/qs/-/qs-6.14.2.tgz",
+      "integrity": "sha512-V/yCWTTF7VJ9hIh18Ugr2zhJMP01MY7c5kh4J870L7imm6/DIzBsNLTXzMwUA3yZ5b/KBqLx8Kp3uRvd7xSe3Q==",
+      "license": "BSD-3-Clause",
+      "dependencies": {
+        "side-channel": "^1.1.0"
+      },
+      "engines": {
+        "node": ">=0.6"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/range-parser": {
+      "version": "1.2.1",
+      "resolved": "https://registry.npmjs.org/range-parser/-/range-parser-1.2.1.tgz",
+      "integrity": "sha512-Hrgsx+orqoygnmhFbKaHE6c296J+HTAQXoxEF6gNupROmmGJRoyzfG3ccAveqCBrwr/2yxQ5BVd/GTl5agOwSg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/raw-body": {
+      "version": "2.5.3",
+      "resolved": "https://registry.npmjs.org/raw-body/-/raw-body-2.5.3.tgz",
+      "integrity": "sha512-s4VSOf6yN0rvbRZGxs8Om5CWj6seneMwK3oDb4lWDH0UPhWcxwOWw5+qk24bxq87szX1ydrwylIOp2uG1ojUpA==",
+      "license": "MIT",
+      "dependencies": {
+        "bytes": "~3.1.2",
+        "http-errors": "~2.0.1",
+        "iconv-lite": "~0.4.24",
+        "unpipe": "~1.0.0"
+      },
+      "engines": {
+        "node": ">= 0.8"
+      }
+    },
+    "node_modules/rrule-temporal": {
+      "version": "1.5.3",
+      "resolved": "https://registry.npmjs.org/rrule-temporal/-/rrule-temporal-1.5.3.tgz",
+      "integrity": "sha512-qALnXyu4MKNUeykkkO0r6Xxl5or3rM8Cf6ibKIe/29sgmq3tGm1oNq4G1Ddp8Ku3mnKmvC3+3yFAJ3OgOu6OJw==",
+      "license": "MIT",
+      "dependencies": {
+        "@js-temporal/polyfill": "^0.5.1"
+      }
+    },
+    "node_modules/safe-buffer": {
+      "version": "5.2.1",
+      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.2.1.tgz",
+      "integrity": "sha512-rp3So07KcdmmKbGvgaNxQSJr7bGVSVk5S9Eq1F+ppbRo70+YeaDxkw5Dd8NPN+GD6bjnYm2VuPuCXmpuYvmCXQ==",
+      "funding": [
+        {
+          "type": "github",
+          "url": "https://github.com/sponsors/feross"
+        },
+        {
+          "type": "patreon",
+          "url": "https://www.patreon.com/feross"
+        },
+        {
+          "type": "consulting",
+          "url": "https://feross.org/support"
+        }
+      ],
+      "license": "MIT"
+    },
+    "node_modules/safer-buffer": {
+      "version": "2.1.2",
+      "resolved": "https://registry.npmjs.org/safer-buffer/-/safer-buffer-2.1.2.tgz",
+      "integrity": "sha512-YZo3K82SD7Riyi0E1EQPojLz7kpepnSQI9IyPbHHg1XXXevb5dJI7tpyN2ADxGcQbHG7vcyRHk0cbwqcQriUtg==",
+      "license": "MIT"
+    },
+    "node_modules/send": {
+      "version": "0.19.2",
+      "resolved": "https://registry.npmjs.org/send/-/send-0.19.2.tgz",
+      "integrity": "sha512-VMbMxbDeehAxpOtWJXlcUS5E8iXh6QmN+BkRX1GARS3wRaXEEgzCcB10gTQazO42tpNIya8xIyNx8fll1OFPrg==",
+      "license": "MIT",
+      "dependencies": {
+        "debug": "2.6.9",
+        "depd": "2.0.0",
+        "destroy": "1.2.0",
+        "encodeurl": "~2.0.0",
+        "escape-html": "~1.0.3",
+        "etag": "~1.8.1",
+        "fresh": "~0.5.2",
+        "http-errors": "~2.0.1",
+        "mime": "1.6.0",
+        "ms": "2.1.3",
+        "on-finished": "~2.4.1",
+        "range-parser": "~1.2.1",
+        "statuses": "~2.0.2"
+      },
+      "engines": {
+        "node": ">= 0.8.0"
+      }
+    },
+    "node_modules/send/node_modules/ms": {
+      "version": "2.1.3",
+      "resolved": "https://registry.npmjs.org/ms/-/ms-2.1.3.tgz",
+      "integrity": "sha512-6FlzubTLZG3J2a/NVCAleEhjzq5oxgHyaCU9yYXvcLsvoVaHJq/s5xXI6/XXP6tz7R9xAOtHnSO/tXtF3WRTlA==",
+      "license": "MIT"
+    },
+    "node_modules/serve-static": {
+      "version": "1.16.3",
+      "resolved": "https://registry.npmjs.org/serve-static/-/serve-static-1.16.3.tgz",
+      "integrity": "sha512-x0RTqQel6g5SY7Lg6ZreMmsOzncHFU7nhnRWkKgWuMTu5NN0DR5oruckMqRvacAN9d5w6ARnRBXl9xhDCgfMeA==",
+      "license": "MIT",
+      "dependencies": {
+        "encodeurl": "~2.0.0",
+        "escape-html": "~1.0.3",
+        "parseurl": "~1.3.3",
+        "send": "~0.19.1"
+      },
+      "engines": {
+        "node": ">= 0.8.0"
+      }
+    },
+    "node_modules/setprototypeof": {
+      "version": "1.2.0",
+      "resolved": "https://registry.npmjs.org/setprototypeof/-/setprototypeof-1.2.0.tgz",
+      "integrity": "sha512-E5LDX7Wrp85Kil5bhZv46j8jOeboKq5JMmYM3gVGdGH8xFpPWXUMsNrlODCrkoxMEeNi/XZIwuRvY4XNwYMJpw==",
+      "license": "ISC"
+    },
+    "node_modules/side-channel": {
+      "version": "1.1.0",
+      "resolved": "https://registry.npmjs.org/side-channel/-/side-channel-1.1.0.tgz",
+      "integrity": "sha512-ZX99e6tRweoUXqR+VBrslhda51Nh5MTQwou5tnUDgbtyM0dBgmhEDtWGP/xbKn6hqfPRHujUNwz5fy/wbbhnpw==",
+      "license": "MIT",
+      "dependencies": {
+        "es-errors": "^1.3.0",
+        "object-inspect": "^1.13.3",
+        "side-channel-list": "^1.0.0",
+        "side-channel-map": "^1.0.1",
+        "side-channel-weakmap": "^1.0.2"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/side-channel-list": {
+      "version": "1.0.1",
+      "resolved": "https://registry.npmjs.org/side-channel-list/-/side-channel-list-1.0.1.tgz",
+      "integrity": "sha512-mjn/0bi/oUURjc5Xl7IaWi/OJJJumuoJFQJfDDyO46+hBWsfaVM65TBHq2eoZBhzl9EchxOijpkbRC8SVBQU0w==",
+      "license": "MIT",
+      "dependencies": {
+        "es-errors": "^1.3.0",
+        "object-inspect": "^1.13.4"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/side-channel-map": {
+      "version": "1.0.1",
+      "resolved": "https://registry.npmjs.org/side-channel-map/-/side-channel-map-1.0.1.tgz",
+      "integrity": "sha512-VCjCNfgMsby3tTdo02nbjtM/ewra6jPHmpThenkTYh8pG9ucZ/1P8So4u4FGBek/BjpOVsDCMoLA/iuBKIFXRA==",
+      "license": "MIT",
+      "dependencies": {
+        "call-bound": "^1.0.2",
+        "es-errors": "^1.3.0",
+        "get-intrinsic": "^1.2.5",
+        "object-inspect": "^1.13.3"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/side-channel-weakmap": {
+      "version": "1.0.2",
+      "resolved": "https://registry.npmjs.org/side-channel-weakmap/-/side-channel-weakmap-1.0.2.tgz",
+      "integrity": "sha512-WPS/HvHQTYnHisLo9McqBHOJk2FkHO/tlpvldyrnem4aeQp4hai3gythswg6p01oSoTl58rcpiFAjF2br2Ak2A==",
+      "license": "MIT",
+      "dependencies": {
+        "call-bound": "^1.0.2",
+        "es-errors": "^1.3.0",
+        "get-intrinsic": "^1.2.5",
+        "object-inspect": "^1.13.3",
+        "side-channel-map": "^1.0.1"
+      },
+      "engines": {
+        "node": ">= 0.4"
+      },
+      "funding": {
+        "url": "https://github.com/sponsors/ljharb"
+      }
+    },
+    "node_modules/statuses": {
+      "version": "2.0.2",
+      "resolved": "https://registry.npmjs.org/statuses/-/statuses-2.0.2.tgz",
+      "integrity": "sha512-DvEy55V3DB7uknRo+4iOGT5fP1slR8wQohVdknigZPMpMstaKJQWhwiYBACJE3Ul2pTnATihhBYnRhZQHGBiRw==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.8"
+      }
+    },
+    "node_modules/temporal-polyfill": {
+      "version": "0.3.2",
+      "resolved": "https://registry.npmjs.org/temporal-polyfill/-/temporal-polyfill-0.3.2.tgz",
+      "integrity": "sha512-TzHthD/heRK947GNiSu3Y5gSPpeUDH34+LESnfsq8bqpFhsB79HFBX8+Z834IVX68P3EUyRPZK5bL/1fh437Eg==",
+      "license": "MIT",
+      "dependencies": {
+        "temporal-spec": "0.3.1"
+      }
+    },
+    "node_modules/temporal-spec": {
+      "version": "0.3.1",
+      "resolved": "https://registry.npmjs.org/temporal-spec/-/temporal-spec-0.3.1.tgz",
+      "integrity": "sha512-B4TUhezh9knfSIMwt7RVggApDRJZo73uZdj8AacL2mZ8RP5KtLianh2MXxL06GN9ESYiIsiuoLQhgVfwe55Yhw==",
+      "license": "ISC"
+    },
+    "node_modules/toidentifier": {
+      "version": "1.0.1",
+      "resolved": "https://registry.npmjs.org/toidentifier/-/toidentifier-1.0.1.tgz",
+      "integrity": "sha512-o5sSPKEkg/DIQNmH43V0/uerLrpzVedkUh8tGNvaeXpfpuwjKenlSox/2O/BTlZUtEe+JG7s5YhEz608PlAHRA==",
+      "license": "MIT",
+      "engines": {
+        "node": ">=0.6"
+      }
+    },
+    "node_modules/type-is": {
+      "version": "1.6.18",
+      "resolved": "https://registry.npmjs.org/type-is/-/type-is-1.6.18.tgz",
+      "integrity": "sha512-TkRKr9sUTxEH8MdfuCSP7VizJyzRNMjj2J2do2Jr3Kym598JVdEksuzPQCnlFPW4ky9Q+iA+ma9BGm06XQBy8g==",
+      "license": "MIT",
+      "dependencies": {
+        "media-typer": "0.3.0",
+        "mime-types": "~2.1.24"
+      },
+      "engines": {
+        "node": ">= 0.6"
+      }
+    },
+    "node_modules/undici": {
+      "version": "7.25.0",
+      "resolved": "https://registry.npmjs.org/undici/-/undici-7.25.0.tgz",
+      "integrity": "sha512-xXnp4kTyor2Zq+J1FfPI6Eq3ew5h6Vl0F/8d9XU5zZQf1tX9s2Su1/3PiMmUANFULpmksxkClamIZcaUqryHsQ==",
+      "license": "MIT",
+      "engines": {
+        "node": ">=20.18.1"
+      }
+    },
+    "node_modules/unpipe": {
+      "version": "1.0.0",
+      "resolved": "https://registry.npmjs.org/unpipe/-/unpipe-1.0.0.tgz",
+      "integrity": "sha512-pjy2bYhSsufwWlKwPc+l3cN7+wuJlK6uz0YdJEOlQDbl6jo/YlPi4mb8agUkVC8BF7V8NuzeyPNqRksA3hztKQ==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.8"
+      }
+    },
+    "node_modules/utils-merge": {
+      "version": "1.0.1",
+      "resolved": "https://registry.npmjs.org/utils-merge/-/utils-merge-1.0.1.tgz",
+      "integrity": "sha512-pMZTvIkT1d+TFGvDOqodOclx0QWkkgi6Tdoa8gC8ffGAAqz9pzPTZWAybbsHHoED/ztMtkv/VoYTYyShUn81hA==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.4.0"
+      }
+    },
+    "node_modules/vary": {
+      "version": "1.1.2",
+      "resolved": "https://registry.npmjs.org/vary/-/vary-1.1.2.tgz",
+      "integrity": "sha512-BNGbWLfd0eUPabhkXUVm0j8uuvREyTh5ovRa/dyow/BqAbZJyC+5fU+IzQOzmAKzYqYRAISoRhdQr3eIZ/PXqg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">= 0.8"
+      }
+    },
+    "node_modules/web-push": {
+      "version": "3.6.7",
+      "resolved": "https://registry.npmjs.org/web-push/-/web-push-3.6.7.tgz",
+      "integrity": "sha512-OpiIUe8cuGjrj3mMBFWY+e4MMIkW3SVT+7vEIjvD9kejGUypv8GPDf84JdPWskK8zMRIJ6xYGm+Kxr8YkPyA0A==",
+      "license": "MPL-2.0",
+      "dependencies": {
+        "asn1.js": "^5.3.0",
+        "http_ece": "1.2.0",
+        "https-proxy-agent": "^7.0.0",
+        "jws": "^4.0.0",
+        "minimist": "^1.2.5"
+      },
+      "bin": {
+        "web-push": "src/cli.js"
+      },
+      "engines": {
+        "node": ">= 16"
+      }
+    },
+    "node_modules/whatwg-encoding": {
+      "version": "3.1.1",
+      "resolved": "https://registry.npmjs.org/whatwg-encoding/-/whatwg-encoding-3.1.1.tgz",
+      "integrity": "sha512-6qN4hJdMwfYBtE3YBTTHhoeuUrDBPZmbQaxWAqSALV/MeEnR5z1xd8UKud2RAkFoPkmB+hli1TZSnyi84xz1vQ==",
+      "deprecated": "Use @exodus/bytes instead for a more spec-conformant and faster implementation",
+      "license": "MIT",
+      "dependencies": {
+        "iconv-lite": "0.6.3"
+      },
+      "engines": {
+        "node": ">=18"
+      }
+    },
+    "node_modules/whatwg-encoding/node_modules/iconv-lite": {
+      "version": "0.6.3",
+      "resolved": "https://registry.npmjs.org/iconv-lite/-/iconv-lite-0.6.3.tgz",
+      "integrity": "sha512-4fCk79wshMdzMp2rH06qWrJE4iolqLhCUH+OiuIgU++RB0+94NlDL81atO7GX55uUKueo0txHNtvEyI6D7WdMw==",
+      "license": "MIT",
+      "dependencies": {
+        "safer-buffer": ">= 2.1.2 < 3.0.0"
+      },
+      "engines": {
+        "node": ">=0.10.0"
+      }
+    },
+    "node_modules/whatwg-mimetype": {
+      "version": "4.0.0",
+      "resolved": "https://registry.npmjs.org/whatwg-mimetype/-/whatwg-mimetype-4.0.0.tgz",
+      "integrity": "sha512-QaKxh0eNIi2mE9p2vEdzfagOKHCcj1pJ56EEHGQOVxp8r9/iszLUUV7v89x9O1p/T+NlTM5W7jW6+cz4Fq1YVg==",
+      "license": "MIT",
+      "engines": {
+        "node": ">=18"
+      }
+    }
+  }
+}
diff --git a/server/package.json b/server/package.json
new file mode 100644
index 0000000..849d355
--- /dev/null
+++ b/server/package.json
@@ -0,0 +1,16 @@
+{
+  "name": "snu-assignment-server",
+  "version": "1.0.0",
+  "description": "SNU eTL 과제 알림 앱 프록시 서버",
+  "main": "index.js",
+  "scripts": {
+    "start": "node index.js"
+  },
+  "dependencies": {
+    "cheerio": "^1.2.0",
+    "cors": "^2.8.5",
+    "express": "^4.18.2",
+    "node-ical": "^0.26.1",
+    "web-push": "^3.6.7"
+  }
+}
diff --git a/style.css b/style.css
new file mode 100644
index 0000000..1575c1d
--- /dev/null
+++ b/style.css
@@ -0,0 +1,1081 @@
+* { box-sizing: border-box; }
+
+:root {
+  --bg: #f3f6fb;
+  --app-bg: #ffffff;
+  --text: #1f2937;
+  --text-sub: #6b7280;
+  --text-muted: #9ca3af;
+  --border: #e5e7eb;
+  --tab-bg: #f3f4f6;
+  --tab-active-bg: #ffffff;
+  --tab-active-color: #2563eb;
+  --input-bg: #ffffff;
+  --input-border: #d1d5db;
+  --card-bg: #ffffff;
+  --card-border: #e5e7eb;
+  --card-shadow: 0 1px 4px rgba(0,0,0,0.06);
+  --settings-bg: #f9fafb;
+  --settings-border: #e5e7eb;
+  --shadow: 0 10px 30px rgba(0,0,0,0.08);
+  --news-bg: #f9fafb;
+}
+
+body.dark {
+  --bg: #0f172a;
+  --app-bg: #1e293b;
+  --text: #f1f5f9;
+  --text-sub: #94a3b8;
+  --text-muted: #64748b;
+  --border: #334155;
+  --tab-bg: #0f172a;
+  --tab-active-bg: #1e293b;
+  --tab-active-color: #60a5fa;
+  --input-bg: #1e293b;
+  --input-border: #475569;
+  --card-bg: #1e293b;
+  --card-border: #334155;
+  --card-shadow: 0 1px 4px rgba(0,0,0,0.3);
+  --settings-bg: #0f172a;
+  --settings-border: #334155;
+  --shadow: 0 10px 30px rgba(0,0,0,0.4);
+  --news-bg: #0f172a;
+}
+
+body {
+  margin: 0;
+  font-family: "Malgun Gothic", "Apple SD Gothic Neo", sans-serif;
+  background: var(--bg);
+  color: var(--text);
+  transition: background 0.2s, color 0.2s;
+}
+
+.app {
+  max-width: 760px;
+  margin: 40px auto;
+  padding: 24px;
+  background: var(--app-bg);
+  border-radius: 20px;
+  box-shadow: var(--shadow);
+  transition: background 0.2s;
+}
+
+/* 헤더 */
+.header-row {
+  display: flex;
+  justify-content: space-between;
+  align-items: center;
+  margin-bottom: 8px;
+}
+.app-header h1 {
+  margin: 0;
+  font-size: 32px;
+  font-weight: 800;
+}
+#settingsBtn {
+  background: none;
+  border: none;
+  font-size: 22px;
+  color: #9ca3af;
+  cursor: pointer;
+  padding: 4px 8px;
+  border-radius: 8px;
+}
+#settingsBtn:hover { background: #f3f4f6; color: #374151; }
+
+/* 탭 바 */
+.tab-bar {
+  display: flex;
+  gap: 4px;
+  margin-bottom: 20px;
+  background: #f3f4f6;
+  border-radius: 12px;
+  padding: 4px;
+}
+.tab-btn {
+  flex: 1;
+  border: none;
+  border-radius: 9px;
+  padding: 10px;
+  font-size: 14px;
+  font-weight: 700;
+  cursor: pointer;
+  background: transparent;
+  color: #6b7280;
+  transition: all 0.2s;
+  font-family: inherit;
+}
+.tab-btn.active {
+  background: #ffffff;
+  color: #4f46e5;
+  box-shadow: 0 1px 6px rgba(0,0,0,0.1);
+}
+
+/* 설정 드로어 오버레이 */
+.settings-overlay {
+  display: none;
+  position: fixed;
+  inset: 0;
+  background: rgba(0, 0, 0, 0.3);
+  z-index: 100;
+  backdrop-filter: blur(2px);
+}
+.settings-overlay.open { display: block; }
+
+/* 설정 패널 (오른쪽 드로어) */
+.settings-panel {
+  position: fixed;
+  top: 0;
+  right: 0;
+  height: 100%;
+  width: 320px;
+  max-width: 90vw;
+  background: #f8fafc;
+  border-left: 1px solid #e2e8f0;
+  padding: 24px 20px;
+  overflow-y: auto;
+  z-index: 101;
+  transform: translateX(100%);
+  transition: transform 0.28s cubic-bezier(0.4, 0, 0.2, 1);
+  box-shadow: -4px 0 24px rgba(0,0,0,0.1);
+}
+.settings-panel.open {
+  transform: translateX(0);
+}
+.settings-panel-header {
+  display: flex;
+  justify-content: space-between;
+  align-items: center;
+  margin-bottom: 20px;
+}
+.settings-panel-title {
+  font-size: 18px;
+  font-weight: 800;
+  margin: 0;
+}
+#settingsCloseBtn {
+  background: none;
+  border: none;
+  font-size: 20px;
+  color: #9ca3af;
+  cursor: pointer;
+  padding: 4px 8px;
+  border-radius: 8px;
+  transform: none;
+}
+#settingsCloseBtn:hover { background: #f3f4f6; transform: none; }
+.how-to {
+  background: #f8fafc;
+  border: 1px solid #e2e8f0;
+  border-radius: 12px;
+  padding: 16px 20px;
+  margin-bottom: 16px;
+}
+.how-to-title { margin: 0 0 10px; font-size: 14px; font-weight: 700; color: #374151; }
+.how-to ol { margin: 0; padding-left: 20px; font-size: 13px; color: #6b7280; line-height: 2; }
+.how-to strong { color: #4f46e5; }
+.etl-status { display: flex; align-items: center; gap: 8px; margin-bottom: 14px; font-size: 15px; font-weight: 700; }
+.status-dot { width: 8px; height: 8px; border-radius: 50%; background: #22c55e; flex-shrink: 0; }
+.sync-status { font-size: 13px; font-weight: 400; color: #6b7280; }
+.etl-actions { display: flex; gap: 10px; flex-wrap: wrap; }
+.etl-error { margin-top: 12px; padding: 10px 14px; background: #fee2e2; color: #b91c1c; border-radius: 10px; font-size
: 14px; }
+.token-section { margin-top: 16px; padding-top: 14px; border-top: 1px solid #e5e7eb; }
+.token-label { margin: 0 0 8px; font-size: 13px; font-weight: 700; color: #374151; }
+.token-optional { font-weight: 400; color: #9ca3af; }
+.token-input-row { display: flex; gap: 8px; }
+.token-input-row input { flex: 1; padding: 10px 12px; font-size: 13px; }
+.token-hint { margin: 8px 0 0; font-size: 12px; color: #9ca3af; line-height: 1.5; }
+
+/* 입력 */
+label { font-weight: 700; font-size: 14px; }
+input[type="text"], input[type="password"], input[type="date"] {
+  width: 100%;
+  padding: 12px 14px;
+  border: 1px solid #d1d5db;
+  border-radius: 12px;
+  font-size: 15px;
+  background: #ffffff;
+  font-family: inherit;
+}
+input[type="text"]:focus, input[type="password"]:focus, input[type="date"]:focus {
+  outline: none;
+  border-color: #4f46e5;
+  box-shadow: 0 0 0 4px rgba(79,70,229,0.12);
+}
+
+/* 버튼 공통 */
+button {
+  border: none;
+  border-radius: 12px;
+  padding: 11px 18px;
+  font-size: 14px;
+  font-weight: 700;
+  cursor: pointer;
+  transition: transform 0.15s ease, opacity 0.15s ease;
+  font-family: inherit;
+}
+button:hover { transform: translateY(-1px); opacity: 0.9; }
+button:active { transform: translateY(0); }
+button:disabled { opacity: 0.5; cursor: not-allowed; transform: none; }
+#etlSyncBtn, .complete-btn { background: #4f46e5; color: white; }
+.btn-secondary { background: #f3f4f6; color: #374151; }
+
+/* 섹션 */
+.list-section { margin-bottom: 28px; }
+.list-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; }
+.list-header h2 { margin: 0; }
+
+/* 과제 아이템 */
+.task-list { list-style: none; padding: 0; margin: 0; }
+.task-item {
+  display: flex;
+  justify-content: space-between;
+  align-items: center;
+  gap: 16px;
+  background: #f9fafb;
+  border: 1px solid #e5e7eb;
+  border-radius: 16px;
+  padding: 16px;
+  margin-bottom: 12px;
+}
+.task-main { flex: 1; }
+.task-title-row { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; }
+.task-title { margin: 0; font-size: 17px; font-weight: 800; color: inherit; text-decoration: none; }
+a.task-title:hover { text-decoration: underline; color: #4f46e5; }
+.course-label { display: block; font-size: 13px; color: #6366f1; font-weight: 600; margin-bottom: 6px; }
+.task-meta { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
+.due-date-text { color: #6b7280; font-size: 13px; }
+.source-tag { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 11px; font-weight: 800; white-
space: nowrap; }
+.etl-tag { background: #dbeafe; color: #1d4ed8; }
+.due-badge { display: inline-block; padding: 4px 10px; border-radius: 999px; font-size: 12px; font-weight: 800; }
+.due-red   { background: #fee2e2; color: #b91c1c; }
+.due-green { background: #dcfce7; color: #15803d; }
+.due-blue  { background: #dbeafe; color: #1d4ed8; }
+.due-black { background: #111827; color: #ffffff; }
+.empty-message { margin-top: 16px; color: #6b7280; }
+
+/* 메모 */
+.memo-btn {
+  background: none;
+  border: none;
+  padding: 2px 4px;
+  font-size: 14px;
+  cursor: pointer;
+  opacity: 0.5;
+  transition: opacity 0.15s;
+  transform: none;
+}
+.memo-btn:hover { opacity: 1; transform: none; }
+.memo-input {
+  width: 100%;
+  margin-top: 8px;
+  padding: 8px 10px;
+  font-size: 13px;
+  font-family: inherit;
+  border: 1px solid #d1d5db;
+  border-radius: 10px;
+  resize: none;
+  overflow: hidden;
+  min-height: 36px;
+  box-sizing: border-box;
+  background: #fff;
+  color: #374151;
+  line-height: 1.5;
+  display: block;
+}
+.memo-input:focus { outline: none; border-color: #4f46e5; box-shadow: 0 0 0 3px rgba(79,70,229,0.1); }
+
+/* 완료 */
+.completed-header { cursor: pointer; user-select: none; }
+.completed-header h2 { font-size: 16px; color: #6b7280; }
+.completed-header span { font-size: 12px; color: #9ca3af; }
+.completed-task-item { opacity: 0.55; }
+.restore-btn { background: #f3f4f6; color: #374151; white-space: nowrap; font-size: 13px; padding: 8px 14px; }
+
+/* ──────────────────────────────────────────
+   달력
+────────────────────────────────────────── */
+.cal-nav {
+  display: flex;
+  justify-content: space-between;
+  align-items: center;
+  margin-bottom: 12px;
+}
+.cal-title { font-size: 18px; font-weight: 800; color: #1f2937; }
+.cal-nav-btn {
+  background: none;
+  border: none;
+  font-size: 24px;
+  color: #6b7280;
+  padding: 4px 10px;
+  border-radius: 8px;
+  cursor: pointer;
+  line-height: 1;
+}
+.cal-nav-btn:hover { background: #f3f4f6; transform: none; opacity: 1; }
+
+.cal-weekdays {
+  display: grid;
+  grid-template-columns: repeat(7, 1fr);
+  margin-bottom: 4px;
+}
+.cal-weekdays span {
+  text-align: center;
+  font-size: 12px;
+  font-weight: 700;
+  color: #9ca3af;
+  padding: 4px 0;
+}
+.cal-weekdays span:first-child { color: #ef4444; }
+.cal-weekdays span:last-child  { color: #3b82f6; }
+
+.cal-days {
+  display: grid;
+  grid-template-columns: repeat(7, 1fr);
+  gap: 2px;
+  margin-bottom: 16px;
+}
+
+.cal-day {
+  display: flex;
+  flex-direction: column;
+  align-items: flex-start;
+  padding: 4px 3px 3px;
+  border-radius: 8px;
+  cursor: pointer;
+  min-height: 72px;
+  transition: background 0.15s;
+  overflow: hidden;
+}
+.cal-day:hover { background: #f3f4f6; }
+.cal-day.today { background: #4f46e5; color: white; }
+.cal-day.today:hover { background: #4338ca; }
+.cal-day.selected:not(.today) { background: #e0e7ff; }
+.cal-day.other-month .cal-day-num { color: #d1d5db; }
+.cal-day.sunday .cal-day-num { color: #ef4444; }
+.cal-day.saturday .cal-day-num { color: #3b82f6; }
+.cal-day.today .cal-day-num { color: white; }
+.cal-day.other-month.sunday .cal-day-num,
+.cal-day.other-month.saturday .cal-day-num { color: #e5e7eb; }
+
+.cal-day-num {
+  font-size: 13px;
+  font-weight: 700;
+  line-height: 1;
+  margin-bottom: 3px;
+  width: 100%;
+  text-align: center;
+}
+
+.cal-cell-events {
+  display: flex;
+  flex-direction: column;
+  gap: 1px;
+  width: 100%;
+}
+.cal-cell-event {
+  font-size: 9px;
+  font-weight: 600;
+  padding: 1px 3px;
+  border-radius: 3px;
+  white-space: pre;
+  overflow: hidden;
+  width: 100%;
+  line-height: 1.4;
+}
+.cal-cell-event.holiday    { background: #fee2e2; color: #b91c1c; }
+.cal-cell-event.academic   { background: #dbeafe; color: #1d4ed8; }
+.cal-cell-event.assignment { background: #fef3c7; color: #b45309; }
+.cal-cell-event.user       { background: #dcfce7; color: #15803d; }
+.cal-day.today .cal-cell-event { opacity: 0.9; }
+.cal-cell-more { font-size: 9px; color: #9ca3af; padding-left: 3px; line-height: 1.5; }
+
+/* 날짜 상세 */
+.cal-day-detail {
+  background: #f8fafc;
+  border: 1px solid #e2e8f0;
+  border-radius: 16px;
+  padding: 16px;
+  margin-bottom: 20px;
+}
+.cal-detail-header {
+  display: flex;
+  justify-content: space-between;
+  align-items: center;
+  margin-bottom: 12px;
+}
+.cal-selected-label { font-size: 16px; font-weight: 800; color: #1f2937; }
+.cal-add-btn {
+  background: #4f46e5;
+  color: white;
+  font-size: 13px;
+  padding: 6px 14px;
+  border-radius: 999px;
+}
+.cal-add-btn:hover { opacity: 0.85; transform: none; }
+
+.cal-event-list { list-style: none; padding: 0; margin: 0; }
+.cal-event-item {
+  display: flex;
+  align-items: center;
+  gap: 8px;
+  padding: 8px 0;
+  border-bottom: 1px solid #f1f5f9;
+}
+.cal-event-item:last-child { border-bottom: none; }
+.cal-event-dot {
+  width: 8px;
+  height: 8px;
+  border-radius: 50%;
+  flex-shrink: 0;
+}
+.cal-event-dot.holiday    { background: #dc2626; }
+.cal-event-dot.academic   { background: #1d4ed8; }
+.cal-event-dot.assignment { background: #f59e0b; }
+.cal-event-dot.user       { background: #15803d; }
+.cal-event-title {
+  flex: 1;
+  font-size: 14px;
+  font-weight: 600;
+  color: #1f2937;
+  text-decoration: none;
+}
+a.cal-event-title.link:hover { color: #4f46e5; text-decoration: underline; }
+.cal-event-tag {
+  font-size: 11px;
+  font-weight: 700;
+  padding: 2px 8px;
+  border-radius: 999px;
+}
+.holiday-tag  { background: #fee2e2; color: #b91c1c; }
+.academic-tag { background: #dbeafe; color: #1d4ed8; }
+.cal-delete-btn {
+  background: none;
+  border: none;
+  font-size: 13px;
+  color: #9ca3af;
+  padding: 2px 6px;
+  cursor: pointer;
+  border-radius: 6px;
+  transform: none;
+}
+.cal-delete-btn:hover { background: #fee2e2; color: #b91c1c; transform: none; }
+.cal-no-events { color: #9ca3af; font-size: 14px; padding: 8px 0; margin: 0; }
+
+/* 일정 추가 모달 */
+.cal-modal {
+  position: fixed;
+  inset: 0;
+  z-index: 100;
+  display: flex;
+  align-items: center;
+  justify-content: center;
+}
+.cal-modal-overlay {
+  position: absolute;
+  inset: 0;
+  background: rgba(0,0,0,0.4);
+}
+.cal-modal-box {
+  position: relative;
+  background: white;
+  border-radius: 20px;
+  padding: 24px;
+  width: 320px;
+  max-width: 90vw;
+  box-shadow: 0 20px 60px rgba(0,0,0,0.2);
+}
+.cal-modal-title { margin: 0 0 20px; font-size: 18px; font-weight: 800; }
+.cal-modal-field { margin-bottom: 14px; }
+.cal-modal-field label,
+.cal-modal-field #calModalDateLabel { display: block; margin-bottom: 6px; font-size: 13px; font-weight: 700; color: #3
74151; }
+.cal-modal-actions { display: flex; gap: 8px; margin-top: 20px; }
+.cal-modal-actions button { flex: 1; }
+
+/* 시간 피커 */
+.time-picker {
+  display: flex;
+  align-items: stretch;
+  border: 1px solid #e5e7eb;
+  border-radius: 12px;
+  overflow: hidden;
+  height: 132px;
+  position: relative;
+  background: white;
+}
+.time-picker::before,
+.time-picker::after {
+  content: '';
+  position: absolute;
+  left: 0; right: 0;
+  height: 44px;
+  pointer-events: none;
+  z-index: 2;
+}
+.time-picker::before { top: 0; background: linear-gradient(to bottom, rgba(255,255,255,1) 0%, rgba(255,255,255,0) 100%
); }
+.time-picker::after  { bottom: 0; background: linear-gradient(to top, rgba(255,255,255,1) 0%, rgba(255,255,255,0) 100%
); }
+.time-picker-highlight {
+  position: absolute;
+  left: 0; right: 0;
+  top: 50%; transform: translateY(-50%);
+  height: 44px;
+  background: #ede9fe;
+  border-top: 1px solid #c4b5fd;
+  border-bottom: 1px solid #c4b5fd;
+  pointer-events: none;
+  z-index: 0;
+}
+.time-scroll-col {
+  flex: 1;
+  overflow-y: scroll;
+  scroll-snap-type: y mandatory;
+  -webkit-overflow-scrolling: touch;
+  scrollbar-width: none;
+  position: relative;
+  z-index: 1;
+}
+.time-scroll-col::-webkit-scrollbar { display: none; }
+.time-scroll-inner { padding: 44px 0; }
+.time-item {
+  height: 44px;
+  display: flex;
+  align-items: center;
+  justify-content: center;
+  font-size: 16px;
+  font-weight: 600;
+  color: #1f2937;
+  scroll-snap-align: center;
+  user-select: none;
+}
+.time-colon {
+  width: 16px;
+  display: flex;
+  align-items: center;
+  justify-content: center;
+  font-size: 20px;
+  font-weight: 800;
+  color: #374151;
+  flex-shrink: 0;
+  position: relative;
+  z-index: 2;
+}
+body.dark .time-picker { background: #1e293b; border-color: #334155; }
+body.dark .time-picker::before { background: linear-gradient(to bottom, rgba(30,41,59,1) 0%, rgba(30,41,59,0) 100%); }
+body.dark .time-picker::after  { background: linear-gradient(to top, rgba(30,41,59,1) 0%, rgba(30,41,59,0) 100%); }
+body.dark .time-picker-highlight { background: #312e81; border-color: #4338ca; }
+body.dark .time-item { color: #f1f5f9; }
+body.dark .time-colon { color: #f1f5f9; }
+body.dark .cal-modal-field #calModalDateLabel { color: #f1f5f9; }
+
+/* 학교 소식 */
+.news-header { cursor: pointer; user-select: none; }
+.news-header span { font-size: 12px; color: #9ca3af; }
+.news-tabs { display: flex; gap: 8px; margin-bottom: 12px; }
+.news-tab {
+  background: #f3f4f6;
+  color: #6b7280;
+  font-size: 13px;
+  padding: 6px 14px;
+  border-radius: 999px;
+  font-weight: 600;
+}
+.news-tab.active { background: #4f46e5; color: #fff; }
+.news-item { display: flex; align-items: center; gap: 8px; padding: 10px 0; border-bottom: 1px solid #f3f4f6; flex-wra
p: wrap; }
+.news-item:last-child { border-bottom: none; }
+.schedule-item.past { opacity: 0.4; }
+.news-source-tag { display: inline-block; padding: 2px 7px; border-radius: 999px; font-size: 11px; font-weight: 800; w
hite-space: nowrap; flex-shrink: 0; }
+.snu-tag     { background: #e0f2fe; color: #0369a1; }
+.wesnu-tag   { background: #ede9fe; color: #6d28d9; }
+.dongari-tag { background: #dcfce7; color: #15803d; }
+.news-title { flex: 1; font-size: 14px; font-weight: 600; color: #1f2937; text-decoration: none; word-break: keep-all;
 }
+a.news-title:hover { text-decoration: underline; color: #4f46e5; }
+.news-date { font-size: 12px; color: #9ca3af; white-space: nowrap; flex-shrink: 0; }
+.news-loading, .news-error, .news-empty { font-size: 13px; color: #9ca3af; margin: 8px 0; }
+.news-error { color: #b91c1c; }
+
+/* 다크 모드 행 */
+.dark-mode-row {
+  display: flex;
+  justify-content: space-between;
+  align-items: center;
+  margin-top: 16px;
+  padding-top: 14px;
+  border-top: 1px solid #e5e7eb;
+}
+body.dark .dark-mode-row { border-color: #334155; }
+
+/* 다크 모드 오버라이드 */
+body.dark .app { background: #1e293b; }
+body.dark .settings-panel { background: #1e293b; border-color: #334155; }
+body.dark .settings-overlay { background: rgba(0,0,0,0.5); }
+body.dark #settingsCloseBtn { color: #64748b; }
+body.dark #settingsCloseBtn:hover { background: #334155; }
+body.dark .how-to { background: #0f172a; border-color: #334155; }
+body.dark .how-to-title { color: #f1f5f9; }
+body.dark .how-to ol { color: #94a3b8; }
+body.dark .tab-bar { background: #0f172a; }
+body.dark .tab-btn { color: #94a3b8; }
+body.dark .tab-btn.active { background: #1e293b; color: #60a5fa; }
+body.dark .task-item { background: #0f172a; border-color: #334155; }
+body.dark input[type="text"],
+body.dark input[type="password"],
+body.dark input[type="date"] { background: #0f172a; border-color: #475569; color: #f1f5f9; }
+body.dark .btn-secondary { background: #334155; color: #f1f5f9; }
+body.dark #settingsBtn { color: #64748b; }
+body.dark #settingsBtn:hover { background: #334155; color: #f1f5f9; }
+body.dark .due-date-text { color: #94a3b8; }
+body.dark .empty-message { color: #64748b; }
+body.dark .sync-status { color: #94a3b8; }
+body.dark .token-label { color: #f1f5f9; }
+body.dark .token-hint { color: #64748b; }
+body.dark .etl-error { background: #450a0a; color: #fca5a5; }
+body.dark .token-section { border-color: #334155; }
+body.dark .completed-header,
+body.dark .news-header { border-color: #334155; }
+body.dark .cal-nav { background: #0f172a; border-color: #334155; }
+body.dark .cal-title { color: #f1f5f9; }
+body.dark .cal-nav-btn { color: #94a3b8; }
+body.dark .cal-nav-btn:hover { background: #334155; }
+body.dark .cal-weekdays { color: #64748b; }
+body.dark .cal-day { border-color: #334155; }
+body.dark .cal-day.today { background: #1e3a5f; }
+body.dark .cal-day.selected { background: #1e3a5f; }
+body.dark .cal-day-num.sunday { color: #f87171; }
+body.dark .cal-day-detail { background: #0f172a; border-color: #334155; }
+body.dark .cal-detail-header { border-color: #334155; }
+body.dark .cal-selected-label { color: #f1f5f9; }
+body.dark .cal-event-item { border-color: #334155; }
+body.dark .cal-event-title { color: #f1f5f9; }
+body.dark .cal-modal-box { background: #1e293b; }
+body.dark .cal-modal-title { color: #f1f5f9; }
+body.dark .news-section { border-color: #334155; }
+body.dark .news-tabs { background: #0f172a; }
+body.dark .news-tab { color: #94a3b8; }
+body.dark .news-tab:hover { background: #334155; }
+body.dark .news-item { border-color: #334155; }
+body.dark .news-title { color: #f1f5f9; }
+body.dark .news-date { color: #64748b; }
+body.dark .news-loading,
+body.dark .news-empty { color: #64748b; }
+body.dark .memo-input { background: #0f172a; border-color: #334155; color: #f1f5f9; }
+body.dark .completed-task-item { opacity: 0.7; }
+
+/* 유틸 */
+.hidden { display: none; }
+
+/* ──────────────────────────────────────────
+   식당 탭
+   ────────────────────────────────────────── */
+
+#restaurantList {
+  padding: 8px 0 0;
+}
+
+.restaurant-loading,
+.restaurant-error {
+  text-align: center;
+  padding: 32px 0;
+  color: var(--text-sub);
+  font-size: 14px;
+}
+.restaurant-error { color: #ef4444; }
+
+/* 사이드바 + 디테일 레이아웃 */
+.rest-layout {
+  display: flex;
+  gap: 0;
+  min-height: 360px;
+  border: 1px solid var(--border);
+  border-radius: 14px;
+  overflow: hidden;
+  background: var(--card-bg);
+}
+
+/* 왼쪽 사이드바 */
+.rest-sidebar {
+  width: 108px;
+  flex-shrink: 0;
+  border-right: 1px solid var(--border);
+  overflow-y: auto;
+  background: var(--bg);
+}
+
+.rest-sidebar-group {
+  display: flex;
+  align-items: center;
+  gap: 5px;
+  padding: 10px 10px 6px;
+  font-size: 10px;
+  font-weight: 700;
+  color: var(--text-muted);
+  text-transform: uppercase;
+  letter-spacing: 0.04em;
+  border-bottom: 1px solid var(--border);
+  background: var(--bg);
+}
+.rest-sidebar-group.fave-group {
+  color: #f59e0b;
+}
+body.dark .rest-sidebar-group.fave-group { color: #fbbf24; }
+
+.rest-sidebar-item {
+  display: flex;
+  align-items: center;
+  gap: 5px;
+  padding: 10px 10px;
+  font-size: 12px;
+  color: var(--text-sub);
+  cursor: pointer;
+  border-bottom: 1px solid var(--border);
+  transition: background 0.15s, color 0.15s;
+  word-break: keep-all;
+  line-height: 1.4;
+}
+.rest-sidebar-item:hover { background: var(--card-bg); color: var(--text); }
+.rest-sidebar-item.active {
+  background: var(--card-bg);
+  color: var(--tab-active-color);
+  font-weight: 600;
+  border-right: 2px solid var(--tab-active-color);
+}
+body.dark .rest-sidebar-item.active { border-right-color: #60a5fa; }
+
+.rest-sidebar-label { flex: 1; min-width: 0; }
+
+/* 즐겨찾기 별표 버튼 */
+.rest-fave-btn {
+  flex-shrink: 0;
+  background: none;
+  border: none;
+  font-size: 13px;
+  color: var(--text-muted);
+  cursor: pointer;
+  padding: 0 0 0 2px;
+  line-height: 1;
+  opacity: 0;
+  transition: opacity 0.15s, color 0.15s;
+}
+.rest-sidebar-item:hover .rest-fave-btn { opacity: 1; }
+.rest-fave-btn.active {
+  opacity: 1;
+  color: #f59e0b;
+}
+body.dark .rest-fave-btn.active { color: #fbbf24; }
+
+/* 영업 상태 dot */
+.rest-dot {
+  width: 6px;
+  height: 6px;
+  border-radius: 50%;
+  flex-shrink: 0;
+}
+.rest-dot.open   { background: #16a34a; }
+.rest-dot.closed { background: #d1d5db; }
+
+/* 오른쪽 디테일 패널 */
+.rest-detail {
+  flex: 1;
+  padding: 16px 14px;
+  overflow-y: auto;
+}
+
+.rest-detail-title {
+  font-size: 16px;
+  font-weight: 700;
+  color: var(--text);
+  margin-bottom: 6px;
+}
+
+.rest-detail-phone {
+  font-size: 12px;
+  color: var(--text-muted);
+  margin: 0 0 10px;
+}
+
+.rest-detail-section {
+  margin-top: 14px;
+  padding-top: 12px;
+  border-top: 1px solid var(--border);
+}
+.rest-detail-section:first-of-type { margin-top: 10px; padding-top: 0; border-top: none; }
+
+.rest-detail-label {
+  font-size: 11px;
+  font-weight: 700;
+  color: var(--text-muted);
+  text-transform: uppercase;
+  letter-spacing: 0.05em;
+  margin: 0 0 6px;
+}
+
+.rest-detail-lines {
+  display: flex;
+  flex-direction: column;
+  gap: 3px;
+}
+
+.rest-menu-row {
+  font-size: 13px;
+  color: var(--text);
+  font-weight: 500;
+}
+.rest-menu-item {
+  font-size: 13px;
+  color: var(--text-sub);
+}
+.rest-menu-time {
+  font-size: 12px;
+  color: var(--text-muted);
+}
+
+.rest-detail-empty {
+  font-size: 13px;
+  color: var(--text-muted);
+  text-align: center;
+  padding: 24px 0;
+}
+
+/* 배지 */
+.rest-open {
+  display: inline-block;
+  font-size: 11px;
+  font-weight: 600;
+  color: #16a34a;
+  background: #dcfce7;
+  padding: 2px 7px;
+  border-radius: 99px;
+}
+body.dark .rest-open { background: #14532d; color: #86efac; }
+
+.rest-closed {
+  display: inline-block;
+  font-size: 11px;
+  font-weight: 600;
+  color: #9ca3af;
+  background: #f3f4f6;
+  padding: 2px 7px;
+  border-radius: 99px;
+}
+body.dark .rest-closed { background: #1e293b; color: #64748b; }
+
+.rest-tags {
+  display: flex;
+  flex-wrap: wrap;
+  gap: 4px;
+}
+.rest-tag {
+  font-size: 11px;
+  color: var(--text-sub);
+  background: var(--bg);
+  padding: 1px 6px;
+  border-radius: 99px;
+  border: 1px solid var(--border);
+}
+.rest-note {
+  font-size: 12px;
+  color: var(--text-muted);
+  margin: 4px 0 0;
+}
+
+/* 인스타그램 게시물 */
+.rest-ig-post {
+  display: flex;
+  flex-direction: column;
+  gap: 10px;
+  margin-top: 6px;
+}
+.rest-ig-img {
+  width: 100%;
+  max-height: 240px;
+  object-fit: cover;
+  border-radius: 10px;
+  background: var(--border);
+}
+.rest-ig-caption {
+  font-size: 13px;
+  color: var(--text-sub);
+  margin: 0;
+  white-space: pre-line;
+  line-height: 1.6;
+}
+.rest-ig-link {
+  font-size: 13px;
+  color: #2563eb;
+  text-decoration: none;
+  font-weight: 600;
+}
+body.dark .rest-ig-link { color: #60a5fa; }
+
+.rest-menu-error {
+  font-size: 13px;
+  color: #ef4444;
+  margin: 0;
+}
+
+/* 식사 탭 (조식/점심/저녁) */
+.rest-meal-tabs {
+  display: flex;
+  gap: 6px;
+  margin: 10px 0 12px;
+}
+.rest-meal-tab {
+  flex: 1;
+  padding: 6px 0;
+  font-size: 13px;
+  font-weight: 600;
+  font-family: inherit;
+  border: 1.5px solid var(--border);
+  border-radius: 8px;
+  background: var(--bg);
+  color: var(--text-sub);
+  cursor: pointer;
+  transition: background 0.15s, color 0.15s, border-color 0.15s;
+}
+.rest-meal-tab:hover {
+  background: var(--card-bg);
+  color: var(--text);
+}
+.rest-meal-tab.active {
+  background: var(--tab-active-color);
+  color: #fff;
+  border-color: var(--tab-active-color);
+}
+body.dark .rest-meal-tab.active {
+  background: #2563eb;
+  border-color: #2563eb;
+  color: #fff;
+}
+
+.rest-meal-content {
+  min-height: 60px;
+}
+
+/* ──────────────────────────────────────────
+   지도 탭
+   ────────────────────────────────────────── */
+
+#mapTab {
+  display: flex;
+  flex-direction: column;
+}
+
+.map-filter-bar {
+  display: flex;
+  gap: 8px;
+  padding: 10px 16px;
+  background: var(--app-bg);
+  border-bottom: 1px solid var(--border);
+  overflow-x: auto;
+  -webkit-overflow-scrolling: touch;
+  scrollbar-width: none;
+  flex-shrink: 0;
+}
+.map-filter-bar::-webkit-scrollbar { display: none; }
+
+.map-filter-btn {
+  display: inline-flex;
+  align-items: center;
+  gap: 4px;
+  padding: 7px 14px;
+  border-radius: 20px;
+  border: 1.5px solid var(--border);
+  background: var(--app-bg);
+  color: var(--text-sub);
+  font-size: 13px;
+  font-weight: 600;
+  font-family: inherit;
+  cursor: pointer;
+  white-space: nowrap;
+  transition: background 0.15s, color 0.15s, border-color 0.15s;
+}
+.map-filter-btn:hover { background: var(--bg); color: var(--text); }
+.map-filter-btn.active {
+  background: var(--tab-active-color);
+  color: #fff;
+  border-color: var(--tab-active-color);
+}
+body.dark .map-filter-btn { background: var(--app-bg); border-color: var(--border); color: var(--text-sub); }
+body.dark .map-filter-btn.active { background: #2563eb; border-color: #2563eb; }
+
+#mapContainer {
+  height: calc(100vh - 195px);
+  min-height: 380px;
+  position: relative;
+  z-index: 0;
+}
+
+/* Leaflet 팝업 커스텀 */
+.map-popup-inner { min-width: 160px; }
+.map-popup-name {
+  font-size: 14px;
+  font-weight: 700;
+  color: #1f2937;
+  margin: 0 0 3px;
+}
+.map-popup-note {
+  font-size: 12px;
+  color: #6b7280;
+  margin: 0 0 8px;
+}
+.map-popup-nav {
+  display: inline-block;
+  font-size: 13px;
+  font-weight: 600;
+  color: #2563eb;
+  text-decoration: none;
+  background: #eff6ff;
+  border: 1px solid #bfdbfe;
+  border-radius: 8px;
+  padding: 4px 10px;
+  transition: background 0.15s;
+}
+.map-popup-nav:hover { background: #dbeafe; }
+
+/* 현재 위치 버튼 */
+.map-locate-btn {
+  width: 34px;
+  height: 34px;
+  background: #fff;
+  border: 2px solid rgba(0,0,0,0.2);
+  border-radius: 4px;
+  font-size: 16px;
+  cursor: pointer;
+  display: flex;
+  align-items: center;
+  justify-content: center;
+  box-shadow: 0 1px 5px rgba(0,0,0,0.2);
+  margin-top: 4px;
+}
+.map-locate-btn:hover { background: #f4f4f4; }
+
+/* 마커 아이콘 (divIcon) */
+.map-custom-icon { background: none; border: none; }
+
+/* 길찾기 버튼 (식당 디테일 패널) */
+.rest-nav-btn {
+  display: inline-flex;
+  align-items: center;
+  gap: 5px;
+  font-size: 13px;
+  font-weight: 600;
+  color: #2563eb;
+  background: #eff6ff;
+  border: 1px solid #bfdbfe;
+  border-radius: 8px;
+  padding: 5px 12px;
+  text-decoration: none;
+  margin-bottom: 10px;
+  transition: background 0.15s;
+}
+.rest-nav-btn:hover { background: #dbeafe; }
+body.dark .rest-nav-btn { background: #1e3a5f; border-color: #1d4ed8; color: #93c5fd; }
+body.dark .rest-nav-btn:hover { background: #1e40af; }
+
+/* 반응형 */
+@media (max-width: 640px) {
+  .app { margin: 16px; padding: 18px; }
+  .app-header h1 { font-size: 26px; }
+  .task-item { flex-direction: column; align-items: stretch; }
+  .complete-btn, .restore-btn { width: 100%; }
+  .cal-day-num { font-size: 13px; }
+}
diff --git a/sw.js b/sw.js
new file mode 100644
index 0000000..2dd3d77
--- /dev/null
+++ b/sw.js
@@ -0,0 +1,43 @@
+self.addEventListener("install", (event) => {
+  self.skipWaiting();
+  event.waitUntil(
+    caches.open("assignment-app-v13").then((cache) => {
+      return cache.addAll([
+        "./",
+        "./index.html",
+        "./style.css",
+        "./script.js",
+        "./app.webmanifest",
+        "./icon-192.png",
+        "./icon-512.png"
+      ]);
+    })
+  );
+});
+
+self.addEventListener("activate", (event) => {
+  event.waitUntil(
+    caches.keys().then((keys) =>
+      Promise.all(keys.filter((k) => k !== "assignment-app-v13").map((k) => caches.delete(k)))
+    ).then(() => clients.claim())
+  );
+});
+
+self.addEventListener("fetch", (event) => {
+  event.respondWith(fetch(event.request));
+});
+
+self.addEventListener("push", (event) => {
+  const data = event.data ? event.data.json() : {};
+  const title = data.title || "SNU 과제 알림";
+  const options = {
+    body: data.body || "확인해주세요!",
+    icon: "./icon-192.png"
+  };
+  event.waitUntil(self.registration.showNotification(title, options));
+});
+
+self.addEventListener("notificationclick", (event) => {
+  event.notification.close();
+  event.waitUntil(clients.openWindow("./"));
+});
\ No newline at end of file

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git diff --name-only ca89c07128d9e4b438b0ae9
1a8dedfe6360be248' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 441ms:
.gitignore
app.webmanifest
icon-192.png
icon-512.png
index.html
script.js
server/id_tab.png
server/id_tab_clicked.png
server/index.js
server/login_flow.png
server/login_page.png
server/login_stealth.png
server/main_page.png
server/package-lock.json
server/package.json
style.css
sw.js

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content -Path server/index.js' in C:\Use
rs\tom07\Desktop\snu 과제 앱
 succeeded in 481ms:
const express = require("express");
const cors = require("cors");
const ical = require("node-ical");
const https = require("https");
const webpush = require("web-push");

// VAPID ?ㅼ젙
const VAPID_PUBLIC = process.env.VAPID_PUBLIC || "BNHX2y_hSe3MDv1TelFE8LSK6Kg2DY8Aa7gFAjvX9OAIyJu72OerTOMA7PNW3dVf-6lM9
DNUFkI9FOoAh_TTZOg";
const VAPID_PRIVATE = process.env.VAPID_PRIVATE || "zf1hxNgT-YzntEwS5CycYS9oynMTZeDIqmPlWUMrbU0";
webpush.setVapidDetails("mailto:admin@snu-app.com", VAPID_PUBLIC, VAPID_PRIVATE);

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors({ origin: "*" }));
app.use(express.json());

// ??????????????????????????????????????????
// URL fetch (?ㅻ뜑 吏?? 由щ떎?대젆???먮룞 泥섎━, POST 吏??
// ??????????????????????????????????????????
function fetchText(url, redirectCount = 0, extraHeaders = {}, method = "GET", body = null) {
  return new Promise((resolve, reject) => {
    if (redirectCount > 5) return reject(new Error("由щ떎?대젆?멸? ?덈Т 留롮뒿?덈떎."));

    const parsed = new URL(url);
    const bodyBuf = body ? Buffer.from(body, "utf8") : null;
    const options = {
      hostname: parsed.hostname,
      path: parsed.pathname + parsed.search,
      method: method,
      headers: {
        ...extraHeaders,
        ...(bodyBuf ? { "Content-Length": bodyBuf.length } : {}),
      },
    };

    const req = https.request(options, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        return fetchText(res.headers.location, redirectCount + 1, extraHeaders).then(resolve).catch(reject);
      }
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error(`HTTP ${res.statusCode}`));
      }
      res.setEncoding("utf8");
      let data = "";
      res.on("data", (chunk) => { data += chunk; });
      res.on("end", () => resolve(data));
    });

    req.on("error", reject);
    req.setTimeout(15000, () => req.destroy(new Error("?붿껌 ?쒓컙 珥덇낵 (15珥?")));
    if (bodyBuf) req.write(bodyBuf);
    req.end();
  });
}

// ??????????????????????????????????????????
// Canvas API: ?쒖텧 ?щ? ?뺤씤
// ??????????????????????????????????????????
async function isSubmitted(courseId, assignmentId, token) {
  try {
    const url = `https://myetl.snu.ac.kr/api/v1/courses/${courseId}/assignments/${assignmentId}/submissions/self`;
    const text = await fetchText(url, 0, { Authorization: `Bearer ${token}` });
    const data = JSON.parse(text);
    return ["submitted", "graded", "pending_review"].includes(data.workflow_state);
  } catch {
    return false; // ?뺤씤 ?ㅽ뙣 ??怨쇱젣 ?좎? (?덉쟾 湲곕낯媛?
  }
}

// ??????????????????????????????????????????
// Canvas iCal ?뚯떛 ?좏떥
// ??????????????????????????????????????????

function parseSummary(summary) {
  const match = (summary || "").match(/^(.*?)\s*\[([^\]]+)\]\s*$/);
  if (match) return { title: match[1].trim(), courseName: match[2].trim() };
  return { title: (summary || "").trim(), courseName: "" };
}

function buildAssignmentUrl(calendarUrl) {
  if (!calendarUrl) return "";
  const courseMatch = calendarUrl.match(/include_contexts=course_(\d+)/);
  const assignMatch = calendarUrl.match(/#assignment_(\d+)/);
  if (courseMatch && assignMatch) {
    return `https://myetl.snu.ac.kr/courses/${courseMatch[1]}/assignments/${assignMatch[1]}`;
  }
  return calendarUrl;
}

function parseEventDate(ev) {
  const start = ev.start;
  if (!start) return { date: null, dateOnly: false };
  if (start instanceof Date) {
    const isDateOnly = ev.start.dateOnly === true || (ev.dtstart && ev.dtstart.includes("VALUE=DATE"));
    if (isDateOnly) {
      // node-ical? VALUE=DATE瑜??쒕쾭 濡쒖뺄 ?먯젙?쇰줈 ?뚯떛??
      // eTL? KST 湲곗??대?濡?+9h 蹂댁젙?쇰줈 ?쒕쾭 ?쒓컙? 臾닿??섍쾶 KST ?좎쭨 異붿텧
      const kst = new Date(start.getTime() + 9 * 60 * 60 * 1000);
      const y = kst.getUTCFullYear();
      const m = kst.getUTCMonth();
      const d = kst.getUTCDate();
      const deadline = new Date(Date.UTC(y, m, d, 14, 59, 0));
      return { date: deadline, dateOnly: false };
    }
    return { date: start, dateOnly: false };
  }
  return { date: null, dateOnly: false };
}

// ??????????????????????????????????????????
// POST /api/sync-ical
// body: { icalUrl, apiToken? }
// ??????????????????????????????????????????
app.post("/api/sync-ical", async (req, res) => {
  let { icalUrl, apiToken } = req.body;

  if (!icalUrl) {
    return res.status(400).json({ error: "icalUrl???꾩슂?⑸땲??" });
  }

  icalUrl = icalUrl.trim().replace(/^webcal:\/\//i, "https://");

  if (!icalUrl.startsWith("https://")) {
    return res.status(400).json({ error: "?좏슚??eTL iCal URL???낅젰?댁＜?몄슂." });
  }

  try {
    console.log(`[sync] fetch: ${icalUrl.slice(0, 70)}...`);
    const text = await fetchText(icalUrl);
    console.log(`[sync] ?섏떊: ${text.length} bytes`);

    const events = ical.sync.parseICS(text);
    const now = new Date();
    const assignments = [];

    for (const key of Object.keys(events)) {
      const ev = events[key];
      if (ev.type !== "VEVENT") continue;

      const { date: dueDate, dateOnly } = parseEventDate(ev);
      if (!dueDate || isNaN(dueDate.getTime())) continue;

      const diffDays = (dueDate - now) / (1000 * 60 * 60 * 24);
      if (diffDays < 0 || diffDays > 7) continue;

      const { title, courseName } = parseSummary(ev.summary);
      if (!title) continue;

      const uidMatch = (ev.uid || "").match(/assignment-(\d+)/);
      const etlId = uidMatch ? uidMatch[1] : (ev.uid || key).slice(0, 20);
      const assignmentUrl = buildAssignmentUrl(ev.url);

      const courseMatch = assignmentUrl.match(/courses\/(\d+)/);
      const assignMatch = assignmentUrl.match(/assignments\/(\d+)/);

      assignments.push({
        etlId,
        title,
        courseName,
        dueDate: dueDate.toISOString(),
        dateOnly,
        url: assignmentUrl,
        courseId: courseMatch ? courseMatch[1] : null,
        assignmentId: assignMatch ? assignMatch[1] : null,
      });
    }

    // API ?좏겙???덉쑝硫??쒖텧??怨쇱젣 ?꾪꽣留?
    let filtered = assignments;
    if (apiToken) {
      console.log(`[sync] ?쒖텧 ?щ? ?뺤씤 以?(${assignments.length}媛?...`);
      const results = await Promise.all(
        assignments.map(async (a) => {
          if (!a.courseId || !a.assignmentId) return true;
          const submitted = await isSubmitted(a.courseId, a.assignmentId, apiToken);
          return !submitted;
        })
      );
      filtered = assignments.filter((_, i) => results[i]);
      console.log(`[sync] ?쒖텧 ?쒖쇅 ?? ${filtered.length}媛?);
    }

    // courseId/assignmentId???대씪?댁뼵?몄뿉 遺덊븘?뷀븯誘濡??쒓굅
    const output = filtered.map(({ courseId, assignmentId, ...rest }) => rest);

    output.sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate));
    console.log(`[sync] ?꾨즺: ${output.length}媛?怨쇱젣`);
    res.json(output);

  } catch (err) {
    console.error(`[sync] ?ㅻ쪟: ${err.message}`);
    res.status(500).json({ error: `iCal 遺덈윭?ㅺ린 ?ㅽ뙣: ${err.message}` });
  }
});

// ??????????????????????????????????????????
// ?숆탳 ?뚯떇 ?щ·留?
// ??????????????????????????????????????????

const cheerio = require("cheerio");

// ?숈궗?쇱젙 湲곕낯媛?(怨듭떇 ?ъ씠???щ·留??ㅽ뙣 ???ъ슜)
const fallbackSchedule = [
  { title: "遊꾪븰湲?媛쒓컯", date: "2026-03-02", source: "snu" },
  { title: "?섍컯蹂寃?湲곌컙", date: "2026-03-02", endDate: "2026-03-13", source: "snu" },
  { title: "以묎컙怨좎궗", date: "2026-04-20", endDate: "2026-04-25", source: "snu" },
  { title: "?섍컯痍⑥냼 湲곌컙", date: "2026-04-27", endDate: "2026-05-01", source: "snu" },
  { title: "湲곕쭚怨좎궗", date: "2026-06-15", endDate: "2026-06-20", source: "snu" },
  { title: "遊꾪븰湲?醫낃컯", date: "2026-06-19", source: "snu" },
  { title: "愿?낆젣", date: "2026-05-12", endDate: "2026-05-14", source: "snu" },
];

// SNU 怨듭떇 ?대깽???섏씠吏 ?щ·留?(YYYY.MM.DD ?뺤떇 ?뚯떛)
function parseSnuDate(str) {
  const m = str.match(/(\d{4})\.(\d{2})\.(\d{2})/);
  if (!m) return null;
  return `${m[1]}-${m[2]}-${m[3]}`;
}

async function fetchSnuEvents() {
  try {
    const html = await fetchText("https://www.snu.ac.kr/snunow/events", 0, { "User-Agent": "Mozilla/5.0" });
    const $ = cheerio.load(html);
    const items = [];
    $("span.texts").each((i, el) => {
      const title = $(el).find("span.title").text().trim();
      const pointText = $(el).find("span.point").text().trim();
      if (!title || !pointText) return;
      const dates = pointText.match(/\d{4}\.\d{2}\.\d{2}/g) || [];
      const startDate = parseSnuDate(dates[0]);
      const endDate = dates[1] ? parseSnuDate(dates[1]) : null;
      if (!startDate) return;
      items.push({ title, date: startDate, ...(endDate ? { endDate } : {}), source: "snu_events" });
    });
    console.log(`[events] SNU 怨듭떇 ?대깽??${items.length}媛??щ·留??꾨즺`);
    return items;
  } catch (err) {
    console.error("[events] SNU ?대깽???щ·留??ㅻ쪟:", err.message);
    return [];
  }
}

function parseRSS(xml) {
  const items = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/g;
  let match;
  while ((match = itemRegex.exec(xml)) !== null) {
    const block = match[1];
    const getTag = (tag) => {
      const m = block.match(new RegExp(`<${tag}>(?:<!\\[CDATA\\[)?([\\s\\S]*?)(?:\\]\\]>)?<\\/${tag}>`));
      return m ? m[1].trim() : "";
    };
    const title = getTag("title");
    const link = getTag("link") || block.match(/<link\s*\/?>(.*?)<\/link>/)?.[1]?.trim() || "";
    const pubDate = getTag("pubDate");
    const category = getTag("category");
    if (title) items.push({ title, link, pubDate, category });
  }
  return items;
}

async function fetchWeSnuRSS() {
  try {
    const xml = await fetchText("https://we.snu.ac.kr/feed/");
    const items = parseRSS(xml);
    return items.slice(0, 10).map((item) => ({
      title: item.title,
      url: item.link,
      date: item.pubDate ? new Date(item.pubDate).toISOString() : null,
      category: item.category || "珥앺븰?앺쉶",
      source: "wesnu",
    }));
  } catch (err) {
    console.error("[events] 珥앺븰 RSS ?ㅻ쪟:", err.message);
    return [];
  }
}

async function fetchDongariNotices() {
  try {
    const html = await fetchText("https://dongari.snu.ac.kr/%EA%B3%B5%EC%A7%80%EC%82%AC%ED%95%AD/?mod=list");
    const $ = cheerio.load(html);
    const items = [];
    $("ul.board_body li").each((i, el) => {
      const title = $(el).find("div.cut-strings").text().trim();
      const href = $(el).find("div.subject a").attr("href");
      const date = $(el).find("span.date").text().trim();
      if (title && date) {
        items.push({
          title,
          url: href ? `https://dongari.snu.ac.kr${href}` : null,
          date: new Date(date).toISOString(),
          category: "?숈븘由ъ뿰?⑺쉶",
          source: "dongari",
        });
      }
    });
    return items.slice(0, 10);
  } catch (err) {
    console.error("[events] ?숈븘由ъ뿰?⑺쉶 ?ㅻ쪟:", err.message);
    return [];
  }
}

app.get("/api/events", async (req, res) => {
  const [wesnu, dongari, snuEvents] = await Promise.all([
    fetchWeSnuRSS(),
    fetchDongariNotices(),
    fetchSnuEvents(),
  ]);

  const notices = [...wesnu, ...dongari].sort((a, b) => {
    if (!a.date) return 1;
    if (!b.date) return -1;
    return new Date(b.date) - new Date(a.date);
  });

  // SNU 怨듭떇 ?대깽?멸? ?덉쑝硫??ъ슜, ?놁쑝硫?fallback
  const schedule = snuEvents.length > 0
    ? [...fallbackSchedule, ...snuEvents]
    : fallbackSchedule;

  res.json({ schedule, notices });
});

// ??????????????????????????????????????????
// ?몄떆 ?뚮┝
// ??????????????????????????????????????????

// { endpoint ??{ subscription, tasks: [{etlId, dueDate, title, courseName}] } }
const pushStore = new Map();
const sentKeys = new Set(); // "endpoint:etlId:Nh" - 以묐났 諛쒖넚 諛⑹?

app.get("/api/push/vapid-public-key", (req, res) => {
  res.json({ key: VAPID_PUBLIC });
});

app.post("/api/push/subscribe", (req, res) => {
  const { subscription, tasks } = req.body;
  if (!subscription?.endpoint) return res.status(400).json({ error: "subscription ?꾩슂" });
  pushStore.set(subscription.endpoint, { subscription, tasks: tasks || [] });
  console.log(`[push] 援щ룆 ?깅줉: ${pushStore.size}媛?);
  res.json({ ok: true });
});

// 5遺꾨쭏???뚮┝ 泥댄겕 (怨쇱젣: 24h/5h/1h, ?ъ슜???쇱젙: task.targets ?ъ슜)
const DEFAULT_TARGETS = [24, 5, 1];
setInterval(async () => {
  const now = new Date();
  const WINDOW = 6 / 60; // 짹6遺??덉슜

  for (const [endpoint, { subscription, tasks }] of pushStore) {
    for (const task of tasks) {
      const due = new Date(task.dueDate);
      const diffH = (due - now) / (1000 * 60 * 60);
      if (diffH < 0) continue;

      const targets = task.targets || DEFAULT_TARGETS;
      for (const h of targets) {
        if (diffH <= h + WINDOW && diffH > h - WINDOW) {
          const key = `${endpoint}:${task.etlId}:${h}`;
          if (sentKeys.has(key)) continue;
          sentKeys.add(key);

          const label = h === 1 ? "1?쒓컙" : h === 5 ? "5?쒓컙" : "24?쒓컙";
          const name = task.courseName || task.title;
          const isUserEvent = !!task.targets;
          try {
            await webpush.sendNotification(subscription, JSON.stringify({
              title: isUserEvent ? `?뱟 ?쇱젙 ${label} ?? : `?뱴 留덇컧 ${label} ??,
              body: isUserEvent
                ? `"${name}" ?쇱젙??${label} ?꾩엯?덈떎.`
                : `${name} 怨쇱젣 留덇컧??${label} ?꾩엯?덈떎.`,
            }));
            console.log(`[push] ?뚮┝ 諛쒖넚: ${name} (${h}h)`);
          } catch (err) {
            console.error(`[push] 諛쒖넚 ?ㅽ뙣:`, err.message);
            if (err.statusCode === 410) pushStore.delete(endpoint);
          }
        }
      }
    }
  }
}, 5 * 60 * 1000);

// ??????????????????????????????????????????
// Instagram 怨듭떇 API (OAuth 諛⑹떇)
// ??????????????????????????????????????????

const IG_APP_ID     = process.env.IG_APP_ID     || "975791108172537";
const IG_APP_SECRET = process.env.IG_APP_SECRET || "";
const IG_REDIRECT   = process.env.IG_REDIRECT   || "https://snu-assignment-server.onrender.com/api/instagram/callback";

// ?≪꽭???좏겙 ???(硫붾え由?+ ?섍꼍蹂???대갚)
// ?쒕쾭 ?ъ떆???꾩뿉???좎??섎룄濡??섍꼍蹂??IG_ACCESS_TOKEN ?ъ슜
let igAccessToken = process.env.IG_ACCESS_TOKEN || "";
const igPostCache = new Map(); // 寃뚯떆臾?罹먯떆 (30遺?

// ??? OAuth 肄쒕갚 (?ъ옣?섏씠 ?뱀씤 ??由щ떎?대젆?몃릺??怨? ???
app.get("/api/instagram/callback", async (req, res) => {
  const { code, error } = req.query;
  if (error || !code) {
    return res.send("Instagram ?곌껐 ?ㅽ뙣: " + (error || "肄붾뱶 ?놁쓬"));
  }
  try {
    // ?④린 ?좏겙 諛쒓툒
    const params = new URLSearchParams({
      client_id:     IG_APP_ID,
      client_secret: IG_APP_SECRET,
      grant_type:    "authorization_code",
      redirect_uri:  IG_REDIRECT,
      code,
    });
    const shortRes = await fetchText(
      `https://api.instagram.com/oauth/access_token`,
      0,
      { "Content-Type": "application/x-www-form-urlencoded" },
      "POST",
      params.toString()
    );
    const { access_token: shortToken } = JSON.parse(shortRes);

    // ?κ린 ?좏겙?쇰줈 援먰솚 (60???좏슚)
    const longRes = await fetchText(
      `https://graph.instagram.com/access_token?grant_type=ig_exchange_token&client_secret=${IG_APP_SECRET}&access_toke
n=${shortToken}`
    );
    const { access_token: longToken } = JSON.parse(longRes);
    igAccessToken = longToken;

    console.log("[ig] ?≪꽭???좏겙 諛쒓툒 ?꾨즺!");
    console.log("[ig] ?좏겙 (Render ?섍꼍蹂??IG_ACCESS_TOKEN????ν븯?몄슂):", longToken);
    res.send(`
      <h2>??Instagram ?곌껐 ?꾨즺!</h2>
      <p>?꾨옒 ?좏겙??Render ?섍꼍蹂??<b>IG_ACCESS_TOKEN</b>????ν븯?몄슂.</p>
      <textarea rows="4" cols="80">${longToken}</textarea>
    `);
  } catch (err) {
    console.error("[ig] ?좏겙 諛쒓툒 ?ㅻ쪟:", err.message);
    res.status(500).send("?좏겙 諛쒓툒 ?ㅽ뙣: " + err.message);
  }
});

// ??? 寃뚯떆臾?議고쉶 ???
async function fetchInstagramPosts() {
  if (!igAccessToken) throw new Error("?≪꽭???좏겙 ?놁쓬 ???ъ옣???뱀씤 ?꾩슂");

  const cached = igPostCache.get("posts");
  if (cached && Date.now() - cached.fetchedAt < 30 * 60 * 1000) {
    console.log("[ig] 罹먯떆 ?ъ슜");
    return cached.posts;
  }

  console.log("[ig] Instagram API ?붿껌");
  const text = await fetchText(
    `https://graph.instagram.com/v21.0/me/media?fields=id,caption,media_type,media_url,thumbnail_url,timestamp,permalin
k&limit=5&access_token=${igAccessToken}`
  );
  const data = JSON.parse(text);
  if (data.error) throw new Error(data.error.message);

  const posts = (data.data || []).map((p) => ({
    id:        p.id,
    url:       p.permalink,
    imageUrl:  p.media_url || p.thumbnail_url || "",
    caption:   p.caption || "",
    date:      p.timestamp,
  }));

  igPostCache.set("posts", { posts, fetchedAt: Date.now() });
  console.log(`[ig] 寃뚯떆臾?${posts.length}媛??섏쭛`);
  return posts;
}

// ??? ?몄쬆 URL ?앹꽦 (?ъ옣?섏뿉寃?蹂대궪 留곹겕) ???
app.get("/api/instagram/auth-url", (req, res) => {
  const url = `https://www.instagram.com/oauth/authorize?client_id=${IG_APP_ID}&redirect_uri=${encodeURIComponent(IG_RE
DIRECT)}&response_type=code&scope=instagram_business_basic`;
  res.json({ url });
});

app.get("/api/instagram/posts", async (req, res) => {
  try {
    const posts = await fetchInstagramPosts();
    res.json(posts);
  } catch (err) {
    console.error(`[ig] ?ㅻ쪟: ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

// ??????????????????????????????????????????
// ?앸떦 硫붾돱
// ??????????????????????????????????????????

// ??? SNU ?숈깮?앸떦 (snuco.snu.ac.kr) ???
const snucoCache = new Map();

async function fetchSnucoMenu() {
  const cacheKey = new Date().toISOString().slice(0, 10); // ?좎쭨 湲곗? 罹먯떆
  if (snucoCache.has(cacheKey)) return snucoCache.get(cacheKey);

  const html = await fetchText("https://snuco.snu.ac.kr/ko/foodmenu", 0, { "User-Agent": "Mozilla/5.0" });
  const $ = cheerio.load(html);

  const restaurants = [];

  // <br> ??\n 蹂?????띿뒪??異붿텧?섎뒗 ?ы띁
  function cellText(el) {
    // <br> ?쒓렇瑜?以꾨컮轅덉쑝濡?移섑솚
    $(el).find("br").replaceWith("\n");
    return $(el).text()
      .split("\n")
      .map(l => l.trim())
      .filter(Boolean)
      .join("\n");
  }

  // snuco.snu.ac.kr ?ㅼ젣 援ъ“: #celeb-mealtable table.menu-table tbody tr
  $("#celeb-mealtable table.menu-table tbody tr").each((i, row) => {
    const name      = $(row).find("td.title").text().trim().replace(/\s+/g, " ");
    const breakfast = cellText($(row).find("td.breakfast"));
    const lunch     = cellText($(row).find("td.lunch"));
    const dinner    = cellText($(row).find("td.dinner"));
    if (name && (breakfast || lunch || dinner)) {
      restaurants.push({
        name,
        breakfast: breakfast || "",
        lunch:     lunch     || "?뺣낫 ?놁쓬",
        dinner:    dinner    || "",
      });
    }
  });

  const result = { restaurants, fetchedAt: new Date().toISOString() };
  snucoCache.set(cacheKey, result);
  return result;
}

app.get("/api/restaurant/snuco", async (req, res) => {
  try {
    const data = await fetchSnucoMenu();
    res.json(data);
  } catch (err) {
    console.error("[snuco] ?ㅻ쪟:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// ??? 媛뺤뿬?ъ쭛諛?Instagram 寃뚯떆臾????
app.get("/api/restaurant/gangyeo", async (req, res) => {
  try {
    const posts = await fetchInstagramPosts();
    res.json({ posts });
  } catch (err) {
    console.error("[gangyeo] ?ㅻ쪟:", err.message);
    res.status(500).json({ error: err.message, needsAuth: !igAccessToken });
  }
});

// ??? 怨좎젙 ?앸떦 ?뺣낫 (?ㅽ뵂?쒓컙 ?? ???
const RESTAURANTS_INFO = [
  {
    id: "gangyeo",
    name: "媛뺤뿬?ъ쭛諛?,
    type: "instagram",
    tags: ["?쒖떇", "諛깅컲"],
    address: "?쒖슱 愿?낃뎄 ?좊┝濡?92-1",
    hours: { weekday: "11:00??4:00", weekend: "?대Т" },
    instagram: "@sgon1476",
    note: "留ㅼ씪 硫붾돱 蹂?????몄뒪?洹몃옩 ?뺤씤",
  },
  {
    id: "snuco",
    name: "SNU ?숈깮?앸떦",
    type: "snuco",
    tags: ["?숈떇", "援щ궡?앸떦"],
    address: "?쒖슱??숆탳 ??,
    hours: {
      breakfast: "07:30??9:00",
      lunch: "11:00??4:00",
      dinner: "17:00??9:00",
    },
    note: "嫄대Ъ留덈떎 ?댁쁺 ?쒓컙 ?곸씠",
  },
  {
    id: "boodang",
    name: "遺덈떦",
    type: "static",
    tags: ["?쒖떇", "遺꾩떇"],
    address: "?쒖슱 愿?낃뎄 愿?낅줈 1",
    hours: { weekday: "11:00??0:00", weekend: "11:00??7:00" },
    note: "??숈썝 湲곗닕???멸렐",
  },
];

// ?꾩옱 ?ㅽ뵂 ?щ? 怨꾩궛
function isOpenNow(info) {
  const now = new Date();
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000); // UTC?묷ST
  const day = kst.getUTCDay(); // 0=?? 6=??
  const hhmm = kst.getUTCHours() * 100 + kst.getUTCMinutes();

  function parseRange(str) {
    if (!str || str === "?대Т") return null;
    const m = str.match(/(\d{1,2}):(\d{2})[??-~](\d{1,2}):(\d{2})/);
    if (!m) return null;
    return {
      open:  parseInt(m[1]) * 100 + parseInt(m[2]),
      close: parseInt(m[3]) * 100 + parseInt(m[4]),
    };
  }

  const hours = info.hours;
  if (!hours) return null;

  if (info.id === "snuco") {
    if (day === 0 || day === 6) return false; // 二쇰쭚 ?대Т
    const ranges = [hours.breakfast, hours.lunch, hours.dinner].map(parseRange).filter(Boolean);
    return ranges.some(r => hhmm >= r.open && hhmm < r.close);
  }

  const rangeStr = (day === 0 || day === 6) ? (hours.weekend || hours.weekday) : hours.weekday;
  const r = parseRange(rangeStr);
  if (!r) return false;
  return hhmm >= r.open && hhmm < r.close;
}

app.get("/api/restaurant/list", (req, res) => {
  const list = RESTAURANTS_INFO.map(r => ({
    ...r,
    isOpen: isOpenNow(r),
  }));
  res.json(list);
});

app.get("/health", (req, res) => res.json({ ok: true }));

app.listen(PORT, () => {
  console.log(`??SNU 怨쇱젣 ?쒕쾭 ?ㅽ뻾 以? http://localhost:${PORT}`);
});

2026-05-12T14:27:11.717618Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command 'node --check server/index.js'` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'node --check server/index.js' in C:\Users\to
m07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'node --check server/index.js'` rejected: bl
ocked by policy
2026-05-12T14:27:17.194794Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command '$i=1; Get-Content server/index.js | ForEach-Object { if($i -ge 150 -and $i -le 210){ '"'{0,4}: 
{1}' -f "'$i, $_}; $i++ }'` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command '$i=1; Get-Content server/index.js | ForEach-
Object { if($i -ge 150 -and $i -le 210){ '"'{0,4}: {1}' -f "'$i, $_}; $i++ }' in C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command '$i=1; Get-Content server/index.js | ForEach
-Object { if($i -ge 150 -and $i -le 210){ '"'{0,4}: {1}' -f "'$i, $_}; $i++ }'` rejected: blocked by policy
2026-05-12T14:27:24.731422Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command "@'
from pathlib import Path
for i,line in enumerate(Path('server/index.js').read_text(encoding='utf-8', errors='replace').splitlines(),1):
    if 150<=i<=210:
        print(f'{i:4}: {line}')
'@ | python -"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "@'
from pathlib import Path
for i,line in enumerate(Path('server/index.js').read_text(encoding='utf-8', errors='replace').splitlines(),1):
    if 150<=i<=210:
        print(f'{i:4}: {line}')
'@ | python -" in C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "@'
from pathlib import Path
for i,line in enumerate(Path('server/index.js').read_text(encoding='utf-8', errors='replace').splitlines(),1):
    if 150<=i<=210:
        print(f'{i:4}: {line}')
'@ | python -"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content server/index.js | Select-Object 
-First 210 | Select-Object -Last 60' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 381ms:

      const uidMatch = (ev.uid || "").match(/assignment-(\d+)/);
      const etlId = uidMatch ? uidMatch[1] : (ev.uid || key).slice(0, 20);
      const assignmentUrl = buildAssignmentUrl(ev.url);

      const courseMatch = assignmentUrl.match(/courses\/(\d+)/);
      const assignMatch = assignmentUrl.match(/assignments\/(\d+)/);

      assignments.push({
        etlId,
        title,
        courseName,
        dueDate: dueDate.toISOString(),
        dateOnly,
        url: assignmentUrl,
        courseId: courseMatch ? courseMatch[1] : null,
        assignmentId: assignMatch ? assignMatch[1] : null,
      });
    }

    // API ?좏겙???덉쑝硫??쒖텧??怨쇱젣 ?꾪꽣留?
    let filtered = assignments;
    if (apiToken) {
      console.log(`[sync] ?쒖텧 ?щ? ?뺤씤 以?(${assignments.length}媛?...`);
      const results = await Promise.all(
        assignments.map(async (a) => {
          if (!a.courseId || !a.assignmentId) return true;
          const submitted = await isSubmitted(a.courseId, a.assignmentId, apiToken);
          return !submitted;
        })
      );
      filtered = assignments.filter((_, i) => results[i]);
      console.log(`[sync] ?쒖텧 ?쒖쇅 ?? ${filtered.length}媛?);
    }

    // courseId/assignmentId???대씪?댁뼵?몄뿉 遺덊븘?뷀븯誘濡??쒓굅
    const output = filtered.map(({ courseId, assignmentId, ...rest }) => rest);

    output.sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate));
    console.log(`[sync] ?꾨즺: ${output.length}媛?怨쇱젣`);
    res.json(output);

  } catch (err) {
    console.error(`[sync] ?ㅻ쪟: ${err.message}`);
    res.status(500).json({ error: `iCal 遺덈윭?ㅺ린 ?ㅽ뙣: ${err.message}` });
  }
});

// ??????????????????????????????????????????
// ?숆탳 ?뚯떇 ?щ·留?
// ??????????????????????????????????????????

const cheerio = require("cheerio");

// ?숈궗?쇱젙 湲곕낯媛?(怨듭떇 ?ъ씠???щ·留??ㅽ뙣 ???ъ슜)
const fallbackSchedule = [
  { title: "遊꾪븰湲?媛쒓컯", date: "2026-03-02", source: "snu" },
  { title: "?섍컯蹂寃?湲곌컙", date: "2026-03-02", endDate: "2026-03-13", source: "snu" },
  { title: "以묎컙怨좎궗", date: "2026-04-20", endDate: "2026-04-25", source: "snu" },
  { title: "?섍컯痍⑥냼 湲곌컙", date: "2026-04-27", endDate: "2026-05-01", source: "snu" },

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:\"filtered.length\" server\\in
dex.js" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 399ms:
183:      console.log(`[sync] 제출 제외 후: ${filtered.length}개`);

2026-05-12T14:27:43.669992Z ERROR codex_core::tools::router: error=`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\po
wershell.exe" -Command "findstr /n /c:\"name:\" /c:\"address:\" /c:\"title:\" server\\index.js | more"` rejected: block
ed by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:\"name:\" /c:\"address:\" /c:\
"title:\" server\\index.js | more" in C:\Users\tom07\Desktop\snu 과제 앱
 declined in 0ms:
`"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:\"name:\" /c:\"address:\" /c:
\"title:\" server\\index.js | more"` rejected: blocked by policy
exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:\"gangyeo\" /c:\"snuco\" serve
r\\index.js" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 391ms:
496:// ─── SNU 학생식당 (snuco.snu.ac.kr) ───
497:const snucoCache = new Map();
501:  if (snucoCache.has(cacheKey)) return snucoCache.get(cacheKey);
503:  const html = await fetchText("https://snuco.snu.ac.kr/ko/foodmenu", 0, { "User-Agent": "Mozilla/5.0" });
519:  // snuco.snu.ac.kr 실제 구조: #celeb-mealtable table.menu-table tbody tr
536:  snucoCache.set(cacheKey, result);
540:app.get("/api/restaurant/snuco", async (req, res) => {
545:    console.error("[snuco] 오류:", err.message);
551:app.get("/api/restaurant/gangyeo", async (req, res) => {
556:    console.error("[gangyeo] 오류:", err.message);
564:    id: "gangyeo",
574:    id: "snuco",
576:    type: "snuco",
617:  if (info.id === "snuco") {

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content server/index.js | Select-Object 
-First 590 | Select-Object -Last 45' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 493ms:
    res.status(500).json({ error: err.message });
  }
});

// ??? 媛뺤뿬?ъ쭛諛?Instagram 寃뚯떆臾????
app.get("/api/restaurant/gangyeo", async (req, res) => {
  try {
    const posts = await fetchInstagramPosts();
    res.json({ posts });
  } catch (err) {
    console.error("[gangyeo] ?ㅻ쪟:", err.message);
    res.status(500).json({ error: err.message, needsAuth: !igAccessToken });
  }
});

// ??? 怨좎젙 ?앸떦 ?뺣낫 (?ㅽ뵂?쒓컙 ?? ???
const RESTAURANTS_INFO = [
  {
    id: "gangyeo",
    name: "媛뺤뿬?ъ쭛諛?,
    type: "instagram",
    tags: ["?쒖떇", "諛깅컲"],
    address: "?쒖슱 愿?낃뎄 ?좊┝濡?92-1",
    hours: { weekday: "11:00??4:00", weekend: "?대Т" },
    instagram: "@sgon1476",
    note: "留ㅼ씪 硫붾돱 蹂?????몄뒪?洹몃옩 ?뺤씤",
  },
  {
    id: "snuco",
    name: "SNU ?숈깮?앸떦",
    type: "snuco",
    tags: ["?숈떇", "援щ궡?앸떦"],
    address: "?쒖슱??숆탳 ??,
    hours: {
      breakfast: "07:30??9:00",
      lunch: "11:00??4:00",
      dinner: "17:00??9:00",
    },
    note: "嫄대Ъ留덈떎 ?댁쁺 ?쒓컙 ?곸씠",
  },
  {
    id: "boodang",
    name: "遺덈떦",
    type: "static",
    tags: ["?쒖떇", "遺꾩떇"],

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:\"강여\" /c:\"address:\" server\
\index.js" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 333ms:
568:    address: "서울 관악구 신림로 92-1",
578:    address: "서울대학교 내",
591:    address: "서울 관악구 관악로 1",

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:\"name:\" server\\index.js" in
 C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 638ms:
28:      hostname: parsed.hostname,
565:    name: "강여사집밥",
575:    name: "SNU 학생식당",
588:    name: "불당",

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git diff --stat ca89c07128d9e4b438b0ae91a8de
dfe6360be248' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 866ms:
 .gitignore                |    4 +
 app.webmanifest           |   20 +
 icon-192.png              |  Bin 0 -> 43960 bytes
 icon-512.png              |  Bin 0 -> 201195 bytes
 index.html                |  220 +++++++
 script.js                 | 1545 +++++++++++++++++++++++++++++++++++++++++++++
 server/id_tab.png         |  Bin 0 -> 71617 bytes
 server/id_tab_clicked.png |  Bin 0 -> 64376 bytes
 server/index.js           |  641 +++++++++++++++++++
 server/login_flow.png     |  Bin 0 -> 134244 bytes
 server/login_page.png     |  Bin 0 -> 5402 bytes
 server/login_stealth.png  |  Bin 0 -> 5402 bytes
 server/main_page.png      |  Bin 0 -> 108497 bytes
 server/package-lock.json  | 1372 ++++++++++++++++++++++++++++++++++++++++
 server/package.json       |   16 +
 style.css                 | 1081 +++++++++++++++++++++++++++++++
 sw.js                     |   43 ++
 17 files changed, 4942 insertions(+)

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content server/package.json' in C:\Users
\tom07\Desktop\snu 과제 앱
 succeeded in 552ms:
{
  "name": "snu-assignment-server",
  "version": "1.0.0",
  "description": "SNU eTL 怨쇱젣 ?뚮┝ ???꾨줉???쒕쾭",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "cheerio": "^1.2.0",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "node-ical": "^0.26.1",
    "web-push": "^3.6.7"
  }
}

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'findstr /n /c:"fetch(" /c:"subscribe" /c:"pu
sh" script.js' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 588ms:
7:  setInterval(() => fetch(`${SERVER_URL}/health`).catch(() => {}), 10 * 60 * 1000);
116:  for (let i = 0; i < clean.length; i += 4) lines.push(clean.slice(i, i + 4));
327:      tasks.push(restored);
645:  calendarEvents.push({
652:  subscribePush();
747:    const res = await fetch(`${SERVER_URL}/api/events`);
856:    const res = await fetch(`${SERVER_URL}/api/sync-ical`, {
869:      tasks.push({
884:    subscribePush();
913:async function subscribePush() {
919:    const keyRes = await fetch(`${SERVER_URL}/api/push/vapid-public-key`);
922:    const sub = await reg.pushManager.subscribe({
944:    await fetch(`${SERVER_URL}/api/push/subscribe`, {
950:    console.warn("[push] 구독 실패:", err.message);
957:  if (result === "granted") await subscribePush();
1055:      allItems.push({ id: "snuco_header", label: "SNU 학생식당", isHeader: true, isOpen: info.isOpen });
1061:          allItems.push({ id: `snuco_${i}`, label: name, isHeader: false, isOpen: null });
1065:      allItems.push({ id: info.id, label: info.name, isHeader: false, isOpen: info.isOpen });
1215:      leafletMarkers.push({ marker, type: loc.type, id: loc.id });
1431:      fetch(`${SERVER_URL}/api/restaurant/list`).then(r => r.json()),
1432:      fetch(`${SERVER_URL}/api/restaurant/snuco`).then(r => r.json()),
1433:      fetch(`${SERVER_URL}/api/restaurant/gangyeo`).then(r => r.json()),
1530:if (Notification.permission === "granted") subscribePush();
1545:setInterval(() => { fetch(`${SERVER_URL}/health`).catch(() => {}); }, 14 * 60 * 1000);

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content script.js | Select-Object -First
 980 | Select-Object -Last 150' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 844ms:
  hideEtlError();
  icalUrlInput.value = "";
  openSettings();
});

if (apiTokenSaveBtn) {
  apiTokenSaveBtn.addEventListener("click", async () => {
    const token = apiTokenInput.value.trim();
    canvasToken = token || null;
    if (token) {
      localStorage.setItem(CANVAS_TOKEN_KEY, token);
      apiTokenSaveBtn.textContent = "??λ맖 ??;
    } else {
      localStorage.removeItem(CANVAS_TOKEN_KEY);
      apiTokenSaveBtn.textContent = "??젣??;
    }
    setTimeout(() => { apiTokenSaveBtn.textContent = "???; }, 2000);
    if (icalUrl) await syncIcal();
  });
}

async function syncIcal(retrying = false) {
  if (!icalUrl) return false;
  if (retrying) etlSyncStatus.textContent = "?쒕쾭 以鍮?以?.. ?ъ떆??以?;
  try {
    const res = await fetch(`${SERVER_URL}/api/sync-ical`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ icalUrl, apiToken: canvasToken || undefined }),
    });
    const data = await res.json();
    if (!res.ok) {
      showEtlError(data.error || "怨쇱젣 遺덈윭?ㅺ린 ?ㅽ뙣");
      etlSyncStatus.textContent = "?숆린???ㅽ뙣";
      return false;
    }
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
    if (!calendarTab.classList.contains("hidden")) renderCalendar();
    checkDeadlines();
    subscribePush();
    const now = new Date();
    const t = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
    etlSyncStatus.textContent = `留덉?留??숆린?? ${t} (${data.length}媛?`;
    return true;
  } catch {
    if (!retrying) {
      etlSyncStatus.textContent = "?쒕쾭 源⑥슦??以?.. (理쒕? 30珥?";
      hideEtlError();
      setTimeout(() => syncIcal(true), 10000);
      return false;
    }
    showEtlError("?쒕쾭???곌껐?????놁뒿?덈떎. ?좎떆 ???ㅼ떆 ?쒕룄?댁＜?몄슂.");
    etlSyncStatus.textContent = "?숆린???ㅽ뙣";
    return false;
  }
}

// ??????????????????????????????????????????
// ?뚮┝ (Web Push)
// ??????????????????????????????????????????

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = atob(base64);
  return Uint8Array.from([...rawData].map((c) => c.charCodeAt(0)));
}

async function subscribePush() {
  if (!("PushManager" in window) || !("serviceWorker" in navigator)) return;
  if (Notification.permission !== "granted") return;

  try {
    const reg = await navigator.serviceWorker.ready;
    const keyRes = await fetch(`${SERVER_URL}/api/push/vapid-public-key`);
    const { key } = await keyRes.json();

    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(key),
    });

    const etlTasks = tasks.filter((t) => t.source === "etl").map((t) => ({
      etlId: t.etlId || t.id,
      dueDate: t.dueDate,
      title: t.title,
      courseName: cleanCourseName(t.courseName),
    }));

    const userEventTasks = calendarEvents
      .filter((e) => e.time)
      .map((e) => ({
        etlId: e.id,
        dueDate: e.time,
        title: e.title,
        courseName: null,
        targets: [24, 5],
      }));

    await fetch(`${SERVER_URL}/api/push/subscribe`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ subscription: sub, tasks: [...etlTasks, ...userEventTasks] }),
    });
  } catch (err) {
    console.warn("[push] 援щ룆 ?ㅽ뙣:", err.message);
  }
}

async function requestNotificationPermission() {
  if (!("Notification" in window)) return;
  const result = await Notification.requestPermission();
  if (result === "granted") await subscribePush();
}

function checkDeadlines() {
  if (Notification.permission !== "granted") return;

  // ETL 怨쇱젣: 24h / 5h / 1h (짹6遺?李쎌뿉 ?ㅼ뼱???뚮쭔 諛쒖넚)
  const WINDOW_H = 1 / 60;
  const etlTasks = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
  etlTasks.forEach((task) => {
    const dueDate = parseDateValue(task.dueDate);
    if (!dueDate) return;
    const diffHours = (dueDate - new Date()) / (1000 * 60 * 60);
    if (diffHours < 0) return;
    [
      { h: 24, key: `notified_24h_${task.id}` },
      { h: 5,  key: `notified_5h_${task.id}` },
      { h: 1,  key: `notified_1h_${task.id}` },
    ].forEach(({ h, key }) => {
      if (diffHours <= h + WINDOW_H && diffHours > h - WINDOW_H && !localStorage.getItem(key)) {
        navigator.serviceWorker.ready.then((reg) => {
          const name = cleanCourseName(task.courseName) || task.title;
          reg.showNotification(`?뱴 留덇컧 ${h}?쒓컙 ??, {
            body: `${name} 怨쇱젣 留덇컧??${h}?쒓컙 ?꾩엯?덈떎.`,

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'findstr /n /c:"#mapTab" /c:".hidden" style.c
ss' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 629ms:
664:.hidden { display: none; }
957:#mapTab {

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:\"parseRange\" /c:\"match\" se
rver\\index.js" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 660ms:
78:  const match = (summary || "").match(/^(.*?)\s*\[([^\]]+)\]\s*$/);
79:  if (match) return { title: match[1].trim(), courseName: match[2].trim() };
85:  const courseMatch = calendarUrl.match(/include_contexts=course_(\d+)/);
86:  const assignMatch = calendarUrl.match(/#assignment_(\d+)/);
152:      const uidMatch = (ev.uid || "").match(/assignment-(\d+)/);
156:      const courseMatch = assignmentUrl.match(/courses\/(\d+)/);
157:      const assignMatch = assignmentUrl.match(/assignments\/(\d+)/);
218:  const m = str.match(/(\d{4})\.(\d{2})\.(\d{2})/);
232:      const dates = pointText.match(/\d{4}\.\d{2}\.\d{2}/g) || [];
249:  let match;
250:  while ((match = itemRegex.exec(xml)) !== null) {
251:    const block = match[1];
253:      const m = block.match(new RegExp(`<${tag}>(?:<!\\[CDATA\\[)?([\\s\\S]*?)(?:\\]\\]>)?<\\/${tag}>`));
257:    const link = getTag("link") || block.match(/<link\s*\/?>(.*?)<\/link>/)?.[1]?.trim() || "";
604:  function parseRange(str) {
606:    const m = str.match(/(\d{1,2}):(\d{2})[–\-~](\d{1,2}):(\d{2})/);
619:    const ranges = [hours.breakfast, hours.lunch, hours.dinner].map(parseRange).filter(Boolean);
624:  const r = parseRange(rangeStr);

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content script.js | Select-Object -First
 260 | Select-Object -Last 110' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 973ms:

// ??????????????????????????????????????????
// ???
// ??????????????????????????????????????????

function saveTasks() { localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks)); }
function saveMemos() { localStorage.setItem(MEMO_KEY, JSON.stringify(memos)); }
function saveCompleted() { localStorage.setItem(COMPLETED_KEY, JSON.stringify(completedTasks)); }
function saveCalendarEvents() { localStorage.setItem(CALENDAR_KEY, JSON.stringify(calendarEvents)); }

// ??????????????????????????????????????????
// ???꾪솚
// ??????????????????????????????????????????

const alertsTab = document.getElementById("alertsTab");
const calendarTab = document.getElementById("calendarTab");
const restaurantTab = document.getElementById("restaurantTab");
const mapTab = document.getElementById("mapTab");

document.querySelectorAll(".tab-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab-btn").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    const tab = btn.dataset.tab;
    alertsTab.classList.toggle("hidden", tab !== "alerts");
    calendarTab.classList.toggle("hidden", tab !== "calendar");
    restaurantTab.classList.toggle("hidden", tab !== "restaurant");
    mapTab.classList.toggle("hidden", tab !== "map");
    if (tab === "calendar") renderCalendar();
    if (tab === "restaurant") renderRestaurantTab();
    if (tab === "map") renderMapTab();
  });
});

// ??????????????????????????????????????????
// 怨쇱젣 ?뚮뜑留?
// ??????????????????????????????????????????

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

  const now = new Date();
  const visible = tasks.filter((t) => {
    const due = parseDateValue(t.dueDate);
    if (!due) return true;
    const diffDays = (due - now) / (1000 * 60 * 60 * 24);
    return diffDays >= 0 && diffDays <= 7;
  });

  emptyMessage.classList.toggle("hidden", visible.length > 0);

  visible.forEach((task) => {
    const badge = getBadgeInfo(task.dueDate);
    const li = document.createElement("li");
    li.className = "task-item";

    const memo = memos[task.id] || "";
    const mainLabel = cleanCourseName(task.courseName) || task.title;
    const subLabel = task.courseName ? task.title : ""  // subLabel? ?먮낯 title ?좎?;
    const sourceTag = task.source === "etl"
      ? `<span class="source-tag etl-tag">eTL</span>`
      : "";
    const mainLink = task.url
      ? `<a class="task-title" href="${escapeHtml(task.url)}" target="_blank">${escapeHtml(mainLabel)}</a>`
      : `<p class="task-title">${escapeHtml(mainLabel)}</p>`;
    const subLabelHtml = subLabel
      ? `<span class="course-label">${escapeHtml(subLabel)}</span>`
      : "";

    li.innerHTML = `
      <div class="task-main">
        <div class="task-title-row">${sourceTag}${mainLink}</div>
        ${subLabelHtml}
        <div class="task-meta">
          <span class="due-date-text">留덇컧?? ${formatDateTime(task.dueDate, task.dateOnly)}</span>
          <span class="due-badge ${badge.className}">${badge.text}</span>
          <button class="memo-btn" data-id="${task.id}" title="硫붾え">?륅툘</button>
        </div>
        <textarea class="memo-input${memo ? "" : " hidden"}" placeholder="硫붾え ?낅젰..." data-id="${task.id}">${escapeHtml
(memo)}</textarea>
      </div>
      <button class="complete-btn" data-id="${task.id}">?꾨즺</button>
    `;

    const memoTextarea = li.querySelector(".memo-input");
    const memoBtn = li.querySelector(".memo-btn");

    function autoResize() {
      memoTextarea.style.height = "36px";
      memoTextarea.style.height = Math.max(36, memoTextarea.scrollHeight) + "px";
    }

    memoBtn.addEventListener("click", () => {
      memoTextarea.classList.toggle("hidden");
      if (!memoTextarea.classList.contains("hidden")) {
        autoResize();
        memoTextarea.focus();
      }
    });

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'findstr /n /c:"innerHTML" script.js' in C:\U
sers\tom07\Desktop\snu 과제 앱
 succeeded in 658ms:
202:  taskList.innerHTML = "";
232:    li.innerHTML = `
292:  completedList.innerHTML = "";
314:    li.innerHTML = `
378:  calDaysEl.innerHTML = "";
448:    cell.innerHTML = `
480:  eventListEl.innerHTML = "";
483:    eventListEl.innerHTML = '<li class="cal-no-events">일정이 없습니다.</li>';
490:    li.innerHTML = `
501:    li.innerHTML = `
517:    li.innerHTML = `
529:    li.innerHTML = `
700:  newsSchedule.innerHTML = "";
710:    div.innerHTML = `
720:  newsNotices.innerHTML = "";
722:    newsNotices.innerHTML = `<p class="news-empty">불러온 공지가 없습니다.</p>`;
730:    div.innerHTML = `
1233:        btn.innerHTML = "📍";
1400:  document.querySelector(".rest-meal-content").innerHTML = content;
1413:  document.getElementById("restDetailPanel").innerHTML = buildDetailHtml(id, list, snucoData, gangyeoData);
1427:  restaurantListEl.innerHTML = `<div class="restaurant-loading">불러오는 중...</div>`;
1441:      restaurantListEl.innerHTML = `<p class="restaurant-error">식당 정보를 불러오지 못했습니다.</p>`;
1448:    restaurantListEl.innerHTML = `<p class="restaurant-error">오류: ${escapeHtml(err.message)}</p>`;
1482:  restaurantListEl.innerHTML = `

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content script.js | Select-Object -First
 740 | Select-Object -Last 70' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 863ms:
const newsSchedule = document.getElementById("newsSchedule");
const newsNotices = document.getElementById("newsNotices");
const newsLoading = document.getElementById("newsLoading");
const newsError = document.getElementById("newsError");

newsToggle.addEventListener("click", () => {
  const hidden = newsBody.classList.toggle("hidden");
  newsToggleIcon.textContent = hidden ? "?? : "??;
});

document.querySelectorAll(".news-tab").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".news-tab").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    const tab = btn.dataset.tab;
    newsSchedule.classList.toggle("hidden", tab !== "schedule");
    newsNotices.classList.toggle("hidden", tab !== "notices");
  });
});

function formatNewsDate(isoString) {
  if (!isoString) return "";
  const d = new Date(isoString);
  if (isNaN(d)) return isoString;
  return `${String(d.getMonth() + 1).padStart(2, "0")}.${String(d.getDate()).padStart(2, "0")}`;
}

function renderSchedule(schedule) {
  const now = new Date();
  newsSchedule.innerHTML = "";
  schedule.forEach((item) => {
    const start = new Date(item.date || item.startDate);
    const end = item.endDate ? new Date(item.endDate) : null;
    const isPast = end ? end < now : start < now;
    const div = document.createElement("div");
    div.className = `news-item schedule-item${isPast ? " past" : ""}`;
    const dateText = item.endDate
      ? `${formatNewsDate(item.startDate || item.date)} ~ ${formatNewsDate(item.endDate)}`
      : formatNewsDate(item.date);
    div.innerHTML = `
      <span class="news-source-tag snu-tag">怨듭떇</span>
      <span class="news-title">${escapeHtml(item.title)}</span>
      <span class="news-date">${dateText}</span>
    `;
    newsSchedule.appendChild(div);
  });
}

function renderNotices(notices) {
  newsNotices.innerHTML = "";
  if (notices.length === 0) {
    newsNotices.innerHTML = `<p class="news-empty">遺덈윭??怨듭?媛 ?놁뒿?덈떎.</p>`;
    return;
  }
  notices.forEach((item) => {
    const div = document.createElement("div");
    div.className = "news-item";
    const sourceClass = item.source === "wesnu" ? "wesnu-tag" : "dongari-tag";
    const sourceLabel = item.source === "wesnu" ? "珥앺븰" : "?숈븘由?;
    div.innerHTML = `
      <span class="news-source-tag ${sourceClass}">${sourceLabel}</span>
      ${item.url
        ? `<a class="news-title" href="${escapeHtml(item.url)}" target="_blank">${escapeHtml(item.title)}</a>`
        : `<span class="news-title">${escapeHtml(item.title)}</span>`}
      <span class="news-date">${formatNewsDate(item.date)}</span>
    `;
    newsNotices.appendChild(div);
  });
}


exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content script.js | Select-Object -First
 535 | Select-Object -Last 65' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 851ms:
  selectedDateEl.textContent = `${m}??${d}??;

  document.getElementById("calAddBtn").dataset.date = dateStr;

  const holidays = getHolidaysForDate(dateStr);
  const academic = getAcademicForDate(dateStr);
  const assignments = getAssignmentsForDate(dateStr);
  const userEvts = getUserEventsForDate(dateStr);

  eventListEl.innerHTML = "";

  if (holidays.length === 0 && academic.length === 0 && assignments.length === 0 && userEvts.length === 0) {
    eventListEl.innerHTML = '<li class="cal-no-events">?쇱젙???놁뒿?덈떎.</li>';
    return;
  }

  holidays.forEach((ev) => {
    const li = document.createElement("li");
    li.className = "cal-event-item";
    li.innerHTML = `
      <span class="cal-event-dot holiday"></span>
      <span class="cal-event-title">${escapeHtml(ev.title)}</span>
      <span class="cal-event-tag holiday-tag">怨듯쑕??/span>
    `;
    eventListEl.appendChild(li);
  });

  academic.forEach((ev) => {
    const li = document.createElement("li");
    li.className = "cal-event-item";
    li.innerHTML = `
      <span class="cal-event-dot academic"></span>
      <span class="cal-event-title">${escapeHtml(ev.title)}</span>
      <span class="cal-event-tag academic-tag">?숈궗</span>
    `;
    eventListEl.appendChild(li);
  });

  assignments.forEach((task) => {
    const li = document.createElement("li");
    li.className = "cal-event-item";
    const badge = getBadgeInfo(task.dueDate);
    const calLabel = cleanCourseName(task.courseName) || task.title;
    const titleEl = task.url
      ? `<a class="cal-event-title link" href="${escapeHtml(task.url)}" target="_blank">${escapeHtml(calLabel)}</a>`
      : `<span class="cal-event-title">${escapeHtml(calLabel)}</span>`;
    li.innerHTML = `
      <span class="cal-event-dot assignment"></span>
      ${titleEl}
      <span class="due-badge ${badge.className}" style="font-size:11px;padding:2px 8px">${badge.text}</span>
    `;
    eventListEl.appendChild(li);
  });

  userEvts.forEach((ev) => {
    const li = document.createElement("li");
    li.className = "cal-event-item";
    const timeLabel = ev.time ? `<span class="due-date-text" style="font-size:12px">${formatDateTime(ev.time)}</span>` 
: "";
    li.innerHTML = `
      <span class="cal-event-dot user"></span>
      <span class="cal-event-title">${escapeHtml(ev.title)}</span>
      ${timeLabel}
      <button class="cal-delete-btn" data-id="${ev.id}">??/button>
    `;
    li.querySelector(".cal-delete-btn").addEventListener("click", () => {

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'findstr /n /c:"#mapTab" /c:"display: flex" s
tyle.css' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 632ms:
65:  display: flex;
88:  display: flex;
146:  display: flex;
177:.etl-status { display: flex; align-items: center; gap: 8px; margin-bottom: 14px; font-size: 15px; font-weight: 700;
 }
180:.etl-actions { display: flex; gap: 10px; flex-wrap: wrap; }
185:.token-input-row { display: flex; gap: 8px; }
225:.list-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; }
231:  display: flex;
242:.task-title-row { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; }
246:.task-meta { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
299:  display: flex;
340:  display: flex;
371:  display: flex;
402:  display: flex;
419:  display: flex;
470:  display: flex;
492:.cal-modal-actions { display: flex; gap: 8px; margin-top: 20px; }
497:  display: flex;
541:  display: flex;
552:  display: flex;
573:.news-tabs { display: flex; gap: 8px; margin-bottom: 12px; }
583:.news-item { display: flex; align-items: center; gap: 8px; padding: 10px 0; border-bottom: 1px solid #f3f4f6; flex-
wrap: wrap; }
598:  display: flex;
685:  display: flex;
704:  display: flex;
722:  display: flex;
812:  display: flex;
862:  display: flex;
882:  display: flex;
917:  display: flex;
957:#mapTab {
958:  display: flex;
963:  display: flex;
1043:  display: flex;

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content style.css | Select-Object -First
 965 | Select-Object -Last 15' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 856ms:
}

/* ??????????????????????????????????????????
   吏????
   ?????????????????????????????????????????? */

#mapTab {
  display: flex;
  flex-direction: column;
}

.map-filter-bar {
  display: flex;
  gap: 8px;
  padding: 10px 16px;

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'findstr /n /c:"requestNotificationPermission
" /c:"checkDeadlines" script.js' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 584ms:
653:  checkDeadlines();
883:    checkDeadlines();
954:async function requestNotificationPermission() {
960:function checkDeadlines() {
1528:requestNotificationPermission();
1533:checkDeadlines();
1534:setInterval(checkDeadlines, 60000);

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:\"VAPID_PRIVATE\" server\\inde
x.js" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 685ms:
9:const VAPID_PRIVATE = process.env.VAPID_PRIVATE || "zf1hxNgT-YzntEwS5CycYS9oynMTZeDIqmPlWUMrbU0";
10:webpush.setVapidDetails("mailto:admin@snu-app.com", VAPID_PUBLIC, VAPID_PRIVATE);

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:\"dtstart\" server\\index.js" 
in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 580ms:
97:    const isDateOnly = ev.start.dateOnly === true || (ev.dtstart && ev.dtstart.includes("VALUE=DATE"));

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-ChildItem -Force' in C:\Users\tom07\Desk
top\snu 과제 앱
 succeeded in 869ms:


    디렉터리: C:\Users\tom07\Desktop\snu 과제 앱


Mode                 LastWriteTime         Length Name                                                                 
----                 -------------         ------ ----                                                                 
d--h--        2026-05-12  오후 11:20                .git                                                                 
d-----        2026-05-12  오후 11:07                server                                                               
-a----        2026-05-12  오후 11:07             50 .gitignore                                                           
-a----        2026-05-12  오후 11:07            404 app.webmanifest                                                      
-a----        2026-05-12  오후 11:26              0 CODEX_REVIEW.md                                                      
-a----        2026-05-12  오후 11:07          43960 icon-192.png                                                         
-a----        2026-05-12  오후 11:07         201195 icon-512.png                                                         
-a----        2026-05-12  오후 11:07           8773 index.html                                                           
-a----        2026-05-12  오후 11:07           1092 LICENSE                                                              
-a----        2026-05-12  오후 11:07            109 README.md                                                            
-a----        2026-05-12  오후 11:07          62694 script.js                                                            
-a----        2026-05-12  오후 11:07          30036 style.css                                                            
-a----        2026-05-12  오후 11:07           1188 sw.js                                                                



exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content README.md' in C:\Users\tom07\Des
ktop\snu 과제 앱
 succeeded in 554ms:
# snu-assignment
This app alerts users to assignment deadlines so they do not forget to submit their work.

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:'\"node\"' server\\package-loc
k.json | Select-Object -First 20" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 826ms:
14:        "node-ical": "^0.26.1",
18:    "node_modules/@js-temporal/polyfill": {
27:        "node": ">=12"
30:    "node_modules/accepts": {
40:        "node": ">= 0.6"
43:    "node_modules/agent-base": {
49:        "node": ">= 14"
52:    "node_modules/array-flatten": {
58:    "node_modules/asn1.js": {
70:    "node_modules/bn.js": {
76:    "node_modules/body-parser": {
96:        "node": ">= 0.8",
100:    "node_modules/body-parser/node_modules/qs": {
109:        "node": ">=0.6"
115:    "node_modules/boolbase": {
121:    "node_modules/buffer-equal-constant-time": {
127:    "node_modules/bytes": {
133:        "node": ">= 0.8"
136:    "node_modules/call-bind-apply-helpers": {
146:        "node": ">= 0.4"

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command "findstr /n /c:'node_modules/cheerio' /c:'\"c
heerio\"' /c:'>=20' server\\package-lock.json" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 759ms:
11:        "cheerio": "^1.2.0",
165:    "node_modules/cheerio": {
167:      "resolved": "https://registry.npmjs.org/cheerio/-/cheerio-1.2.0.tgz",
171:        "cheerio-select": "^2.1.0",
184:        "node": ">=20.18.1"
187:        "url": "https://github.com/cheeriojs/cheerio?sponsor=1"
190:    "node_modules/cheerio-select": {
192:      "resolved": "https://registry.npmjs.org/cheerio-select/-/cheerio-select-2.1.0.tgz",
327:        "url": "https://github.com/cheeriojs/dom-serializer?sponsor=1"
914:        "node": ">=20"
1288:        "node": ">=20.18.1"

codex
The map tab visibility bug breaks the initial/tabbed UI, and the server also exposes a production-sensitive private pus
h key. These are actionable issues that should be fixed before considering the patch correct.

Full review comments:

- [P2] Make the map tab respect the hidden class — C:\Users\tom07\Desktop\snu 과제 앱\style.css:957-959
  Because `#mapTab` has higher specificity than `.hidden`, this `display: flex` rule overrides `class="hidden"` on init
ial load and after tab switches. As a result, the map filter/container remains visible even when the active tab is not 
the map tab; use a lower-specificity selector or add a `#mapTab.hidden { display: none; }` override.

- [P2] Do not commit the VAPID private key — C:\Users\tom07\Desktop\snu 과제 앱\server\index.js:9-9
  When `VAPID_PRIVATE` is not configured, the server falls back to this checked-in private key, so anyone with the repo
sitory can sign Web Push requests as this application. Require the key from the environment and rotate the exposed key 
pair before using push notifications in production.
The map tab visibility bug breaks the initial/tabbed UI, and the server also exposes a production-sensitive private pus
h key. These are actionable issues that should be fixed before considering the patch correct.

Full review comments:

- [P2] Make the map tab respect the hidden class — C:\Users\tom07\Desktop\snu 과제 앱\style.css:957-959
  Because `#mapTab` has higher specificity than `.hidden`, this `display: flex` rule overrides `class="hidden"` on init
ial load and after tab switches. As a result, the map filter/container remains visible even when the active tab is not 
the map tab; use a lower-specificity selector or add a `#mapTab.hidden { display: none; }` override.

- [P2] Do not commit the VAPID private key — C:\Users\tom07\Desktop\snu 과제 앱\server\index.js:9-9
  When `VAPID_PRIVATE` is not configured, the server falls back to this checked-in private key, so anyone with the repo
sitory can sign Web Push requests as this application. Require the key from the environment and rotate the exposed key 
pair before using push notifications in production.

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content script.js | Select-Object -First
 1290 | Select-Object -Last 90' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 897ms:
      marker.addTo(leafletMap);
    } else {
      marker.remove();
    }
  });
}

function renderMapTab() {
  if (!leafletMap) {
    leafletMap = L.map("mapContainer", { zoomControl: true }).setView([37.4651, 126.9507], 15);
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "짤 <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a>",
      maxZoom: 19,
    }).addTo(leafletMap);

    startLocationWatch();

    const locateCtrl = L.control({ position: "topright" });
    locateCtrl.onAdd = function () {
      const btn = L.DomUtil.create("button", "map-locate-btn");
      btn.innerHTML = "?뱧";
      btn.title = "???꾩튂";
      L.DomEvent.on(btn, "click", () => {
        if (locationDot) leafletMap.setView(locationDot.getLatLng(), 17);
        requestOrientationPermission();
      });
      return btn;
    };
    locateCtrl.addTo(leafletMap);
  }

  setTimeout(() => leafletMap.invalidateSize(), 120);
}

function startLocationWatch() {
  if (!navigator.geolocation) return;

  let firstFix = true;

  navigator.geolocation.watchPosition(
    (pos) => {
      const { latitude: lat, longitude: lng, accuracy } = pos.coords;
      const latlng = [lat, lng];

      if (!locationDot) {
        accuracyCircle = L.circle(latlng, {
          radius: accuracy,
          color: "#2563eb",
          fillColor: "#2563eb",
          fillOpacity: 0.08,
          weight: 1,
          interactive: false,
        }).addTo(leafletMap);

        locationDot = L.marker(latlng, {
          icon: L.divIcon({
            className: "map-location-icon",
            html: `<svg viewBox="-16 -28 32 44" width="32" height="44" overflow="visible">
              <path class="map-heading-cone" d="M0,-26 L-10,-6 L10,-6 Z"
                fill="rgba(37,99,235,0.5)" stroke="none" display="none"/>
              <circle cx="0" cy="0" r="8" fill="#2563eb" stroke="white" stroke-width="2.5"/>
            </svg>`,
            iconSize: [32, 44],
            iconAnchor: [16, 28],
          }),
          interactive: false,
          zIndexOffset: 100,
        }).addTo(leafletMap);
      } else {
        locationDot.setLatLng(latlng);
        accuracyCircle.setLatLng(latlng).setRadius(accuracy);
      }

      if (firstFix) {
        leafletMap.setView(latlng, 17);
        firstFix = false;
      }
    },
    () => {},
    { enableHighAccuracy: true, maximumAge: 5000 }
  );

  onOrientationHandler = function (e) {
    const el = locationDot?.getElement();
    if (!el) return;
    let heading = null;
    if (typeof e.webkitCompassHeading === "number") {
      heading = e.webkitCompassHeading;
    } else if (typeof e.alpha === "number") {
      heading = (360 - e.alpha) % 360;

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'Get-Content script.js | Select-Object -First
 1330 | Select-Object -Last 50' in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 973ms:
  );

  onOrientationHandler = function (e) {
    const el = locationDot?.getElement();
    if (!el) return;
    let heading = null;
    if (typeof e.webkitCompassHeading === "number") {
      heading = e.webkitCompassHeading;
    } else if (typeof e.alpha === "number") {
      heading = (360 - e.alpha) % 360;
    }
    if (heading === null) return;
    const svg = el.querySelector("svg");
    const cone = el.querySelector(".map-heading-cone");
    if (!svg || !cone) return;
    cone.removeAttribute("display");
    svg.style.transform = `rotate(${heading}deg)`;
  };

  // 鍮꼒OS??利됱떆 ?깅줉
  if (typeof DeviceOrientationEvent === "undefined" ||
      typeof DeviceOrientationEvent.requestPermission !== "function") {
    window.addEventListener("deviceorientationabsolute", onOrientationHandler, true);
    window.addEventListener("deviceorientation", onOrientationHandler, true);
    orientationListenerAdded = true;
  }
}

function requestOrientationPermission() {
  if (orientationListenerAdded) return;
  if (typeof DeviceOrientationEvent === "undefined") return;
  if (typeof DeviceOrientationEvent.requestPermission !== "function") return;
  DeviceOrientationEvent.requestPermission()
    .then(state => {
      if (state === "granted" && onOrientationHandler) {
        window.addEventListener("deviceorientation", onOrientationHandler);
        orientationListenerAdded = true;
      }
    })
    .catch(() => {});
}

// ??? ?뷀뀒???⑤꼸 HTML ???
function buildDetailHtml(id, list, snucoData, gangyeoData) {
  // snuco ?몃? ?앸떦
  if (id && id.startsWith("snuco_") && id !== "snuco_header") {
    const idx = parseInt(id.replace("snuco_", ""), 10);
    if (!snucoData || !snucoData.restaurants) return `<p class="rest-detail-empty">硫붾돱 ?뺣낫 ?놁쓬</p>`;
    const r = snucoData.restaurants[idx];
    if (!r) return `<p class="rest-detail-empty">硫붾돱 ?뺣낫 ?놁쓬</p>`;

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'findstr /n /c:"if (!VAPID_PUBLIC" /c:"proces
s.exit" /c:"watchPosition" script.js server'"\\index.js" in C:\Users\tom07\Desktop\snu 과제 앱
 succeeded in 709ms:
script.js:1240:  navigator.geolocation.watchPosition(
server\index.js:10:if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
server\index.js:12:  process.exit(1);

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'type PLAN_REVIEW.md' in C:\Users\tom07\Deskt
op\snu 과제 앱
 succeeded in 867ms:
?꾩옱??援ы쁽??吏꾪뻾?????놁뒿?덈떎. ?묒뾽 ?대뜑??李얠븯?듬땲??

`C:\Users\tom07\Desktop\snu 怨쇱젣 ??

?섏?留????몄뀡??sandbox媛 `read-only`?닿퀬 approval??`never`?쇱꽌 `PLAN.md`, `script.js`, `style.css`, `index.html`???섏젙?????놁뒿
?덈떎.

?뺤씤???꾩옱 ?곹깭:

- `script.js`?먮뒗 ?대? `SNU_LOCATIONS`, `leafletMarkers`, `renderMapTab()`??湲곗〈 留덉빱/?꾪꽣 濡쒖쭅???덉뒿?덈떎.
- ?꾩옱 ?꾩튂 踰꾪듉? `getCurrentPosition()`?쇰줈 留ㅻ쾲 ??`L.circleMarker`瑜?異붽??섎뒗 諛⑹떇?낅땲??
- ?붿껌?섏떊 援ы쁽? `watchPosition()`?쇰줈 ?섎굹???꾩옱 ?꾩튂 留덉빱瑜?怨꾩냽 媛깆떊?섍퀬, `deviceorientation`?쇰줈 heading 留덉빱瑜??뚯쟾?쒗궎??蹂寃쎌엯?덈떎.
- `style.css`?먮뒗 ?대? ?ъ슜??蹂寃쎌쑝濡?蹂댁씠??`#mapTab.hidden { display: none; }`媛 ?덉뒿?덈떎.
- `server/index.js`?먮룄 unrelated 蹂寃쎌씠 ?덉쑝誘濡?嫄대뱶由ъ? ?딆븘???⑸땲??

吏꾪뻾?섎젮硫??곌린 沅뚰븳???덈뒗 ?몄뀡?쇰줈 ?ㅼ떆 ?댁뼱二쇱꽭?? 洹몃윭硫?AGENTS 吏移⑤?濡?

1. `PLAN.md` ?묒꽦/?뺣━
2. `codex_plan_review.ps1` ?ㅽ뻾
3. `script.js`, `style.css`, `index.html` 理쒖냼 ?섏젙
4. 媛?ν븯硫?釉뚮씪?곗?/?뺤쟻 ?뺤씤
5. git repo?대?濡?`codex review --uncommitted`

?쒖꽌濡??앷퉴吏 泥섎━?섍쿋?듬땲??

exec
"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command 'git diff --check' in C:\Users\tom07\Desktop\
snu 과제 앱
 succeeded in 839ms:
codex
The server can now fail to start entirely in environments that have not been updated with VAPID secrets, taking unrelat
ed application functionality offline.

Review comment:

- [P2] Avoid aborting the server when push keys are absent — C:\Users\tom07\Desktop\snu 과제 앱\server\index.js:10-12
  If the existing local/dev or deployed environment has not already been provisioned with both VAPID variables, this ne
w check exits before any route is registered, so non-push features such as health checks, calendar sync, and restaurant
 APIs become unavailable too. Either ensure the env setup is added with this change or keep the server running with pus
h disabled when keys are missing.
The server can now fail to start entirely in environments that have not been updated with VAPID secrets, taking unrelated application functionality offline.

Review comment:

- [P2] Avoid aborting the server when push keys are absent — C:\Users\tom07\Desktop\snu 과제 앱\server\index.js:10-12
  If the existing local/dev or deployed environment has not already been provisioned with both VAPID variables, this new check exits before any route is registered, so non-push features such as health checks, calendar sync, and restaurant APIs become unavailable too. Either ensure the env setup is added with this change or keep the server running with push disabled when keys are missing.
