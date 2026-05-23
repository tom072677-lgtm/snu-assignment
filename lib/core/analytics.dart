import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// 앱 전체에서 사용하는 Analytics 이벤트 래퍼.
/// static 메서드로 제공 → 어디서든 Analytics.xxx() 형태로 호출.
class Analytics {
  Analytics._();

  static final _fa = FirebaseAnalytics.instance;

  /// 개발자 모드 ON/OFF.
  /// ON → Analytics/Crashlytics 수집 중단 (내 데이터가 실제 유저 데이터에 섞이지 않음)
  /// OFF → 정상 수집
  static Future<void> setDevMode(bool enabled) async {
    await _fa.setAnalyticsCollectionEnabled(!enabled);
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!enabled);
    // DebugView 태그: 개발자 기기임을 Firebase Console에서 식별 가능
    if (!enabled) {
      await _fa.setUserProperty(name: 'user_type', value: null);
    } else {
      await _fa.setUserProperty(name: 'user_type', value: 'developer');
    }
  }

  /// MaterialApp에 전달할 NavigationObserver (화면 전환 자동 추적)
  static FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _fa);

  // ─── 탭 전환 ──────────────────────────────────────────────────────────────

  static void tabSelected(int index) {
    _fa.logEvent(name: 'tab_selected', parameters: {
      'tab_index': index,
      'tab_name': _tabName(index),
    }).ignore();
  }

  static String _tabName(int i) => switch (i) {
        0 => 'assignments',
        1 => 'calendar',
        2 => 'restaurant',
        3 => 'map',
        4 => 'shuttle',
        _ => 'unknown',
      };

  // ─── 과제 ─────────────────────────────────────────────────────────────────

  /// 과제 완료 처리 시
  static void assignmentCompleted({
    required String courseName,
    required int hoursBeforeDeadline,
  }) {
    _fa.logEvent(name: 'assignment_completed', parameters: {
      'course_name': courseName,
      // 마감 몇 시간 전에 완료했는지 (행동 패턴 파악)
      'hours_before_deadline': hoursBeforeDeadline,
    }).ignore();
  }

  /// 과제 상세 화면 진입 시
  static void assignmentDetailViewed({required String courseName}) {
    _fa.logEvent(name: 'assignment_detail_viewed', parameters: {
      'course_name': courseName,
    }).ignore();
  }

  // ─── 식당 ─────────────────────────────────────────────────────────────────

  /// 식당 상세 화면 진입 시
  static void venueViewed({
    required String venueName,
    required String category,
    required bool isOpen,
  }) {
    _fa.logEvent(name: 'venue_viewed', parameters: {
      'venue_name': venueName,
      'category': category,
      'is_open': isOpen ? 1 : 0,
    }).ignore();
  }

  /// 즐겨찾기 토글 시
  static void venueFavoriteToggled({
    required String venueName,
    required bool nowFavorite,
  }) {
    _fa.logEvent(name: 'venue_favorite_toggled', parameters: {
      'venue_name': venueName,
      'now_favorite': nowFavorite ? 1 : 0,
    }).ignore();
  }

  /// 식당 카테고리 목록 진입 시
  static void venueListViewed({required String category}) {
    _fa.logEvent(name: 'venue_list_viewed', parameters: {
      'category': category,
    }).ignore();
  }

  // ─── 지도 / 경로 ──────────────────────────────────────────────────────────

  /// 경로 검색 완료 시 (한 번 검색할 때 transit/walk/bike/car 모두 발화하지 않도록
  /// transit 결과가 처음 도착했을 때만 호출)
  static void routeSearched({
    required String destName,
    required String mode,
  }) {
    _fa.logEvent(name: 'route_searched', parameters: {
      'dest_name': destName,
      'mode': mode,
    }).ignore();
  }

  // ─── 설정 / 온보딩 ────────────────────────────────────────────────────────

  /// eTL 캘린더 + Canvas 토큰 연동 완료 시 (핵심 전환점)
  static void etlConnected({required bool hasCanvasToken}) {
    _fa.logEvent(name: 'etl_connected', parameters: {
      'has_canvas_token': hasCanvasToken ? 1 : 0,
    }).ignore();
  }

  /// 테마 변경 시
  static void themeModeChanged(String mode) {
    _fa.logEvent(name: 'theme_mode_changed', parameters: {
      'mode': mode,
    }).ignore();
  }

  /// 과제 조회 기간 변경 시
  static void assignmentDaysChanged(int days) {
    _fa.logEvent(name: 'assignment_days_changed', parameters: {
      'days': days,
    }).ignore();
  }
}
