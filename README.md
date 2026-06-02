# Sharap (샤랍)

Android app for Seoul National University (SNU) students. Aggregates assignments, timetable, calendar, notices, campus restaurant menus, and an interactive campus map into a single interface.

## Features

| Tab | Description |
|-----|-------------|
| Assignments (과제) | eTL / Canvas assignment deadlines with push notifications |
| Timetable (시간표) | Weekly class schedule imported from mySNU or ICS file |
| Calendar (달력) | Personal and academic events |
| Notices (공지) | SNU department notice board |
| Restaurant (식당) | Campus dining hall menus |
| Map (지도) | Naver Map with building, restaurant, and convenience store markers |

## Prerequisites

- Flutter SDK at `C:\Users\tom07\flutter_sdk` (Dart SDK >= 3.3.0)
- Android device or emulator with USB debugging enabled
- `adb` on PATH
- `dart_defines.json` in the project root (see below)

## Environment variables

The app reads two variables at build time via `--dart-define-from-file`. Without them the build succeeds but the Map tab renders nothing (Naver Map auth fails silently).

Copy the example file and fill in your values:

```
copy dart_defines.example.json dart_defines.json
```

`dart_defines.json` format:

```json
{
  "SERVER_URL": "https://snu-assignment-server.onrender.com",
  "NAVER_MAP_CLIENT_ID": "YOUR_NAVER_MAP_CLIENT_ID_HERE"
}
```

`dart_defines.json` is gitignored. Never commit it.

| Variable | Required | Notes |
|----------|----------|-------|
| `NAVER_MAP_CLIENT_ID` | Yes | Obtain from [Naver Cloud Platform](https://console.ncloud.com/). Without it the Map tab is blank. |
| `SERVER_URL` | No | Defaults to `https://snu-assignment-server.onrender.com` |

## Build

```powershell
flutter build apk --release --dart-define-from-file=dart_defines.json
```

Output: `build\app\outputs\flutter-apk\app-release.apk`

## Install

Use `adb install -r`, not `flutter install`.

`flutter install` does a full uninstall/reinstall, which wipes SharedPreferences data: eTL URL, Canvas token, and onboarding state. `adb install -r` replaces only the APK and preserves app data.

```powershell
adb install -r "build\app\outputs\flutter-apk\app-release.apk"
```

## Run in debug mode

```powershell
flutter run --dart-define-from-file=dart_defines.json
```

## Project structure

```
lib/
  core/           # Theme, analytics, shared constants
  features/       # One folder per tab (assignments, calendar, map, ...)
  shared/         # Providers, models used across features
assets/           # Map marker images, static data files
```

## Key dependencies

- `flutter_naver_map` — campus map
- `flutter_riverpod` — state management
- `firebase_messaging` / `firebase_analytics` / `firebase_crashlytics` — push notifications and observability
- `shared_preferences` / `flutter_secure_storage` — local persistence
- `webview_flutter` — mySNU timetable login
