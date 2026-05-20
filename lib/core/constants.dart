import 'package:flutter/foundation.dart';

const String serverUrl = kDebugMode
    ? 'http://localhost:3001'
    : 'https://snu-assignment-server.onrender.com';

const String naverMapClientId = 'NAVER_MAP_CLIENT_ID';

const String appVersion = '1.0.0';

// SharedPreferences keys
const String kIcalUrl = 'snu_etl_ical_url';
const String kCanvasToken = 'snu_etl_canvas_token';
const String kDarkMode = 'dark_mode';
const String kCompletedTasks = 'snu_assignment_app_completed';
const String kMemos = 'snu_assignment_app_memos';
const String kCalendarEvents = 'snu_calendar_events';
const String kFcmToken = 'fcm_token';
