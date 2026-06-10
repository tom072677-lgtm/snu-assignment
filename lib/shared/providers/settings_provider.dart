import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../features/timetable/domain/timetable_models.dart';
import 'notification_service.dart';

// SharedPreferences 인스턴스 provider (main에서 override)
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden in main');
});

// ─── 과제 조회 기간 (7 / 14 / 30일) ─────────────────────────────────────────

class AssignmentDaysNotifier extends Notifier<int> {
  late SharedPreferences _prefs;

  @override
  int build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return _prefs.getInt(kAssignmentDays) ?? 14;
  }

  void set(int days) {
    state = days;
    _prefs.setInt(kAssignmentDays, days);
  }
}

final assignmentDaysProvider =
    NotifierProvider<AssignmentDaysNotifier, int>(AssignmentDaysNotifier.new);

// ─── eTL 설정 ─────────────────────────────────────────────────────────────────

class IcalUrlNotifier extends Notifier<String?> {
  late SharedPreferences _prefs;

  @override
  String? build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return _prefs.getString(kIcalUrl);
  }

  void set(String? value) {
    state = value;
    if (value == null) {
      _prefs.remove(kIcalUrl);
    } else {
      _prefs.setString(kIcalUrl, value);
    }
  }
}

final icalUrlProvider =
    NotifierProvider<IcalUrlNotifier, String?>(IcalUrlNotifier.new);

// Canvas API 토큰 — flutter_secure_storage 사용.
// canvasTokenInitProvider를 main.dart에서 override해서 초기값 주입.
final canvasTokenInitProvider = Provider<String?>((ref) => null);

class CanvasTokenNotifier extends Notifier<String?> {
  static const _storage = FlutterSecureStorage();

  @override
  String? build() => ref.watch(canvasTokenInitProvider);

  void set(String? value) {
    state = value;
    if (value == null) {
      _storage.delete(key: kCanvasToken).ignore();
    } else {
      _storage.write(key: kCanvasToken, value: value).ignore();
    }
  }
}

final canvasTokenProvider =
    NotifierProvider<CanvasTokenNotifier, String?>(CanvasTokenNotifier.new);

// ─── 완료된 과제 ID 목록 (60일 이상 경과 시 자동 정리) ──────────────────────

class CompletedTasksNotifier extends Notifier<Set<String>> {
  late SharedPreferences _prefs;
  final Map<String, DateTime> _timestamps = {};

  static const _purgeDays = 60;

  @override
  Set<String> build() {
    _prefs = ref.watch(sharedPrefsProvider);
    _timestamps.clear();
    return _loadAndPurge();
  }

  Set<String> _loadAndPurge() {
    final raw = _prefs.getString(kCompletedTasks);
    if (raw == null) return {};

    try {
      final decoded = jsonDecode(raw);
      final cutoff =
          DateTime.now().subtract(const Duration(days: _purgeDays));
      int beforeCount = 0;

      if (decoded is List) {
        // 구 포맷(List<String>) → 마이그레이션: 지금을 완료 시각으로 기록
        for (final e in decoded) {
          _timestamps[e.toString()] = DateTime.now();
        }
        beforeCount = decoded.length;
      } else {
        final map = decoded as Map<String, dynamic>;
        beforeCount = map.length;
        for (final e in map.entries) {
          final ts = DateTime.tryParse(e.value as String);
          if (ts != null && ts.isAfter(cutoff)) {
            _timestamps[e.key] = ts;
          }
        }
      }

      final purged = beforeCount != _timestamps.length;
      if (decoded is List || purged) {
        _save();
      }

      return _timestamps.keys.toSet();
    } catch (_) {
      return {};
    }
  }

  void complete(String etlId) {
    _timestamps[etlId] = DateTime.now();
    state = {...state, etlId};
    _save();
    NotificationService.cancelOngoingNotification(etlId).ignore();
  }

  void undo(String etlId) {
    _timestamps.remove(etlId);
    state = state.difference({etlId});
    _save();
  }

  void _save() {
    final map = {
      for (final e in _timestamps.entries) e.key: e.value.toIso8601String(),
    };
    _prefs.setString(kCompletedTasks, jsonEncode(map));
  }
}

final completedTasksProvider =
    NotifierProvider<CompletedTasksNotifier, Set<String>>(
  CompletedTasksNotifier.new,
);

// ─── 개발자 모드 (Analytics 비활성화) ───────────────────────────────────────

class DevModeNotifier extends Notifier<bool> {
  late SharedPreferences _prefs;

  @override
  bool build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return _prefs.getBool(kDevMode) ?? false;
  }

  void toggle() {
    state = !state;
    _prefs.setBool(kDevMode, state);
  }
}

final devModeProvider =
    NotifierProvider<DevModeNotifier, bool>(DevModeNotifier.new);

// ─── 새 과제 알림 ON/OFF / 공지사항 알림 ON/OFF ───────────────────────────────

class NewAssignmentNotifNotifier extends Notifier<bool> {
  late SharedPreferences _prefs;

  @override
  bool build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return _prefs.getBool(kNewAssignmentNotif) ?? true;
  }

  void set(bool value) {
    state = value;
    _prefs.setBool(kNewAssignmentNotif, value);
  }
}

final newAssignmentNotifProvider =
    NotifierProvider<NewAssignmentNotifNotifier, bool>(
  NewAssignmentNotifNotifier.new,
);

class NewAnnouncementNotifNotifier extends Notifier<bool> {
  late SharedPreferences _prefs;

  @override
  bool build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return _prefs.getBool(kNewAnnouncementNotif) ?? true;
  }

  void set(bool value) {
    state = value;
    _prefs.setBool(kNewAnnouncementNotif, value);
  }
}

final newAnnouncementNotifProvider =
    NotifierProvider<NewAnnouncementNotifNotifier, bool>(
  NewAnnouncementNotifNotifier.new,
);

// ─── 커스텀 일정 (학원·과외 등) ───────────────────────────────────────────────

class CustomEventsNotifier extends Notifier<List<CustomEvent>> {
  late SharedPreferences _prefs;

  @override
  List<CustomEvent> build() {
    _prefs = ref.watch(sharedPrefsProvider);
    final raw = _prefs.getString(kCustomEvents);
    if (raw == null) return [];
    return CustomEvent.decodeList(raw);
  }

  void add(CustomEvent event) {
    state = [...state, event];
    _prefs.setString(kCustomEvents, CustomEvent.encodeList(state));
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
    _prefs.setString(kCustomEvents, CustomEvent.encodeList(state));
  }
}

final customEventsProvider =
    NotifierProvider<CustomEventsNotifier, List<CustomEvent>>(
  CustomEventsNotifier.new,
);

// ─── mySNU 시간표 세션 (WebView 로그인 후 추출) ──────────────────────────────

class MySNUSessionsNotifier extends Notifier<List<ClassSession>> {
  late SharedPreferences _prefs;

  @override
  List<ClassSession> build() {
    _prefs = ref.watch(sharedPrefsProvider);
    final raw = _prefs.getString(kMySNUSessions);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ClassSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void setSessions(List<ClassSession> sessions) {
    state = sessions;
    _prefs.setString(
      kMySNUSessions,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }

  void clear() {
    state = [];
    _prefs.remove(kMySNUSessions);
  }

  /// 같은 과목명(summary) 세션을 모두 제거(드랍한 과목 통째). 제거분 반환(실행취소용).
  List<ClassSession> removeCourse(String summary) {
    final removed = state.where((s) => s.summary == summary).toList();
    if (removed.isEmpty) return const [];
    final next = state.where((s) => s.summary != summary).toList();
    state = next;
    _prefs.setString(
      kMySNUSessions,
      jsonEncode(next.map((s) => s.toJson()).toList()),
    );
    return removed;
  }

  /// 실행취소: 제거분을 다시 합쳐 저장.
  void restoreSessions(List<ClassSession> restored) {
    if (restored.isEmpty) return;
    setSessions([...state, ...restored]);
  }
}

final mySNUSessionsProvider =
    NotifierProvider<MySNUSessionsNotifier, List<ClassSession>>(
  MySNUSessionsNotifier.new,
);

// ─── mySNU 시간표 캡처 시점 / 스누즈 / stale 판정 ────────────────────────────

class MySNUCapturedAtNotifier extends Notifier<DateTime?> {
  late SharedPreferences _prefs;

  @override
  DateTime? build() {
    _prefs = ref.watch(sharedPrefsProvider);
    final raw = _prefs.getString(kMySNUCapturedAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  void set(DateTime t) {
    state = t;
    _prefs.setString(kMySNUCapturedAt, t.toIso8601String());
  }

  void clear() {
    state = null;
    _prefs.remove(kMySNUCapturedAt);
  }
}

final mySNUCapturedAtProvider =
    NotifierProvider<MySNUCapturedAtNotifier, DateTime?>(
  MySNUCapturedAtNotifier.new,
);

class MySNUSnoozedSemesterNotifier extends Notifier<String?> {
  late SharedPreferences _prefs;

  @override
  String? build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return _prefs.getString(kMySNUSnoozedSemester);
  }

  void set(String semesterKeyValue) {
    state = semesterKeyValue;
    _prefs.setString(kMySNUSnoozedSemester, semesterKeyValue);
  }

  void clear() {
    state = null;
    _prefs.remove(kMySNUSnoozedSemester);
  }
}

final mySNUSnoozedSemesterProvider =
    NotifierProvider<MySNUSnoozedSemesterNotifier, String?>(
  MySNUSnoozedSemesterNotifier.new,
);
// stale 판정은 DateTime.now()가 매 build마다 신선해야 하므로 캐시되는 Provider로
// 두지 않고, 화면 build에서 isTimetableStale(...)을 직접 호출한다(학기 경계 반응성).

// ─── 단과대 / 학과 코드 ────────────────────────────────────────────────────────

class CollegeCodeNotifier extends Notifier<String?> {
  late SharedPreferences _prefs;

  @override
  String? build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return _prefs.getString(kCollegeCode);
  }

  void set(String? value) {
    state = value;
    if (value == null) {
      _prefs.remove(kCollegeCode);
    } else {
      _prefs.setString(kCollegeCode, value);
    }
  }
}

final collegeCodeProvider =
    NotifierProvider<CollegeCodeNotifier, String?>(CollegeCodeNotifier.new);

class DepartmentCodeNotifier extends Notifier<String?> {
  late SharedPreferences _prefs;

  @override
  String? build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return _prefs.getString(kDepartmentCode);
  }

  void set(String? value) {
    state = value;
    if (value == null) {
      _prefs.remove(kDepartmentCode);
    } else {
      _prefs.setString(kDepartmentCode, value);
    }
  }
}

final departmentCodeProvider =
    NotifierProvider<DepartmentCodeNotifier, String?>(DepartmentCodeNotifier.new);

// ─── 학적 (학사 / 석사 / 박사) ───────────────────────────────────────────────

class AcademicStatusNotifier extends Notifier<String?> {
  late SharedPreferences _prefs;

  @override
  String? build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return _prefs.getString(kAcademicStatus);
  }

  void set(String? value) {
    state = value;
    if (value == null) {
      _prefs.remove(kAcademicStatus);
    } else {
      _prefs.setString(kAcademicStatus, value);
    }
  }
}

final academicStatusProvider =
    NotifierProvider<AcademicStatusNotifier, String?>(AcademicStatusNotifier.new);

// ─── 온보딩 완료 여부 ─────────────────────────────────────────────────────────

class OnboardingCompleteNotifier extends Notifier<bool> {
  late SharedPreferences _prefs;

  @override
  bool build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return _prefs.getBool(kOnboardingComplete) ?? false;
  }

  void set(bool value) {
    state = value;
    _prefs.setBool(kOnboardingComplete, value);
  }
}

final onboardingCompleteProvider =
    NotifierProvider<OnboardingCompleteNotifier, bool>(
  OnboardingCompleteNotifier.new,
);

// ─── 즐겨찾기 제휴 식당 ─────────────────────────────────────────────────────────

class FavPartnersNotifier extends Notifier<Set<String>> {
  late SharedPreferences _prefs;

  @override
  Set<String> build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return (_prefs.getStringList(kFavPartners) ?? []).toSet();
  }

  void toggle(String id) {
    if (state.contains(id)) {
      state = state.difference({id});
    } else {
      state = {...state, id};
    }
    _prefs.setStringList(kFavPartners, state.toList());
  }
}

final favPartnersProvider =
    NotifierProvider<FavPartnersNotifier, Set<String>>(FavPartnersNotifier.new);

// ─── 즐겨찾기 장소 ────────────────────────────────────────────────────────────

class FavVenuesNotifier extends Notifier<Set<String>> {
  late SharedPreferences _prefs;

  @override
  Set<String> build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return (_prefs.getStringList(kFavVenues) ?? []).toSet();
  }

  void toggle(String venueId) {
    if (state.contains(venueId)) {
      state = state.difference({venueId});
    } else {
      state = {...state, venueId};
    }
    _prefs.setStringList(kFavVenues, state.toList());
  }
}

final favVenuesProvider =
    NotifierProvider<FavVenuesNotifier, Set<String>>(FavVenuesNotifier.new);

// ─── 과제별 메모 ──────────────────────────────────────────────────────────────

class MemosNotifier extends Notifier<Map<String, String>> {
  late SharedPreferences _prefs;

  @override
  Map<String, String> build() {
    _prefs = ref.watch(sharedPrefsProvider);
    final raw = _prefs.getString(kMemos);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  void set(String etlId, String memo) {
    state = {...state, etlId: memo};
    _prefs.setString(kMemos, jsonEncode(state));
  }

  void remove(String etlId) {
    final next = Map<String, String>.from(state);
    next.remove(etlId);
    state = next;
    _prefs.setString(kMemos, jsonEncode(state));
  }
}

final memosProvider =
    NotifierProvider<MemosNotifier, Map<String, String>>(MemosNotifier.new);
