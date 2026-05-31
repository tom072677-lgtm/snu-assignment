import 'package:flutter/foundation.dart';

// 빌드 시 dart_defines.json 파일로 환경변수 주입:
//   flutter run --dart-define-from-file=dart_defines.json
//   flutter build apk --dart-define-from-file=dart_defines.json
const String serverUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'https://snu-assignment-server.onrender.com',
);

const String naverMapClientId = String.fromEnvironment(
  'NAVER_MAP_CLIENT_ID',
);

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
const String kNewAnnouncementNotif = 'new_announcement_notif'; // true → 공지사항 push ON
const String kCustomEvents = 'custom_events'; // List<CustomEvent> JSON
const String kMySNUSessions = 'mysnu_sessions'; // List<ClassSession> JSON (mySNU 시간표)
const String kCollegeCode = 'college_code';
const String kDepartmentCode = 'department_code';
const String kOnboardingComplete = 'onboarding_complete';
const String kPartnerRestaurantsCache = 'partner_restaurants_cache';
const String kPartnerRestaurantsFetchedAt = 'partner_restaurants_fetched_at';
const String kPartnerRestaurantsSeedVersion = 'partner_restaurants_seed_version';
const String kFavPartners = 'fav_partners';
