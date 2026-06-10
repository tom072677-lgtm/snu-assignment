---
tags: [sharap, architecture]
---
# Architecture

**sharap** is a **monorepo** with two halves:

| Part | Path | Ships via | Notes |
|---|---|---|---|
| Flutter app | `lib/` | **APK install** (`adb install -r`) | package `com.tom07.sharap`, Android |
| Node/Express server | `server/` | **`git push origin main` → Render** | `snu-assignment-server.onrender.com` |

Git remote: `github.com/tom072677-lgtm/snu-assignment` (branch `main`).

## ⚠️ The deployed server is THIS repo's `server/`
Live server = `server/index.js` (+ `server/deptNotices.js`). **`~/Desktop/snu 과제 앱` is a DEAD old copy — never edit or deploy it** (its git history diverged; editing it once cost real time). If unsure which is live: check `git remote -v`, the branch, and that `server/index.js` is the big one (~2000 lines, has `partner-restaurants`, bus/subway APIs). Full story in [[Debugging Notes]].

## Build / install / deploy
- **App → phone:** `/ship` (or `flutter_install.ps1`) — builds `--release --dart-define-from-file=dart_defines.json`, then `adb install -r` (data-preserving). Never `flutter install`; never drop the dart-define (NaverMap auth breaks). Then `adb shell am force-stop com.tom07.sharap` so the new build actually loads.
- **Server → Render:** `git push origin main`. The app is **not** deployed via push — it's installed as an APK.
- `serverUrl` → `lib/core/constants.dart` (default = the Render URL).

## Key locations
- Notices feature → `lib/features/notices/` — see [[Department Notices]]
- Dept registry → `lib/features/notices/domain/department_notice_source.dart`
- On-device parsers + cert pin → `lib/features/notices/data/notice_repository.dart`
- Server scraper → `server/deptNotices.js`; route in `server/index.js`

See also: [[Decisions]], [[Department Notices]].
