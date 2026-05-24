import 'package:flutter/foundation.dart';

// 실기기에서 localhost는 기기 자신의 loopback이라 서버에 닿지 않음.
// 로컬 서버 테스트가 필요하면: flutter run --dart-define SERVER_URL=http://10.0.2.2:3001
const String serverUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'https://snu-assignment-server.onrender.com',
);

const String naverMapClientId = 'NAVER_MAP_CLIENT_ID';

const String appVersion = '1.0.0';

// SharedPreferences keys
const String kIcalUrl = 'snu_etl_ical_url';
const String kCanvasToken = 'snu_etl_canvas_token';
const String kDarkMode = 'dark_mode'; // legacy — migrated to kThemeMode
const String kThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'
const String kAssignmentDays = 'assignment_days'; // 7 | 14 | 30
const String kFavVenues = 'fav_venues'; // List<String> venue IDs
const String kCompletedTasks = 'snu_assignment_app_completed';
const String kMemos = 'snu_assignment_app_memos';
const String kCalendarEvents = 'snu_calendar_events';
const String kFcmToken = 'fcm_token';
const String kDevMode = 'dev_mode'; // true → Analytics 비활성화 (개발자 기기)
const String kNewAssignmentNotif = 'new_assignment_notif'; // true → 새 과제 push ON
