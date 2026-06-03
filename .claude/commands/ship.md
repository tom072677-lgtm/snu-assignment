---
description: Build the release APK, install it on the phone (data-preserving), force-stop so the new build loads, and verify.
argument-hint: "[optional dept code(s) to also check live, e.g. civil medicine]"
allowed-tools: Bash, PowerShell, Read
---

Build → install → verify the **sharap** APK on the connected Android phone.
Report the verification level honestly (built / installed / device-verified — global rule 10); do NOT claim "device-verified" for runtime behavior the user must confirm on the phone.

1. **Device check:** `adb devices`. If no device is attached/authorized, STOP and tell me to plug in and unlock the phone (this happens — adb drops on lock).

2. **Build + install** (data-preserving; uses the required dart-define). Run the existing script:
   `powershell -File "$env:USERPROFILE\.claude\scripts\flutter_install.ps1"`
   It builds `--release --dart-define-from-file=dart_defines.json` and `adb install -r`. If it fails, surface the **actual** error — never fall back to `flutter install`, never omit the dart-define (global rule 6).

3. **Force-stop** so the next launch loads the new build (install -r doesn't restart a running app):
   `adb shell am force-stop com.tom07.sharap`

4. **Verify:** confirm the install reported `Success` and report the APK timestamp + size. If `$ARGUMENTS` names dept code(s), also `curl` `https://snu-assignment-server.onrender.com/api/dept-notices?dept=<code>` for each and report source/items count (catches server breakage). Finish by telling me exactly what to open/tap on the phone to confirm the change.

Extra context for this run: $ARGUMENTS
