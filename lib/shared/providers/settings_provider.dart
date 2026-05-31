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

final assignmentDaysProvider =
    StateNotifierProvider<AssignmentDaysNotifier, int>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return AssignmentDaysNotifier(prefs);
});

class AssignmentDaysNotifier extends StateNotifier<int> {
  AssignmentDaysNotifier(this._prefs)
      : super(_prefs.getInt(kAssignmentDays) ?? 14);
  final SharedPreferences _prefs;

  void set(int days) {
    state = days;
    _prefs.setInt(kAssignmentDays, days);
  }
}

// ─── eTL 설정 ─────────────────────────────────────────────────────────────────

final icalUrlProvider = StateNotifierProvider<StringSettingNotifier, String?>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return StringSettingNotifier(prefs, kIcalUrl);
});

// Canvas API 토큰 — flutter_secure_storage 사용 (main.dart에서 override)
final canvasTokenProvider =
    StateNotifierProvider<CanvasTokenNotifier, String?>((ref) {
  throw UnimplementedError('canvasTokenProvider must be overridden in main');
});

class CanvasTokenNotifier extends StateNotifier<String?> {
  CanvasTokenNotifier(String? initial) : super(initial);
  static const _storage = FlutterSecureStorage();

  void set(String? value) {
    state = value;
    if (value == null) {
      _storage.delete(key: kCanvasToken).ignore();
    } else {
      _storage.write(key: kCanvasToken, value: value).ignore();
    }
  }
}

class StringSettingNotifier extends StateNotifier<String?> {
  StringSettingNotifier(this._prefs, this._key) : super(_prefs.getString(_key));
  final SharedPreferences _prefs;
  final String _key;

  void set(String? value) {
    state = value;
    if (value == null) {
      _prefs.remove(_key);
    } else {
      _prefs.setString(_key, value);
    }
  }
}

// ─── 완료된 과제 ID 목록 (60일 이상 경과 시 자동 정리) ──────────────────────

final completedTasksProvider =
    StateNotifierProvider<CompletedTasksNotifier, Set<String>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return CompletedTasksNotifier(prefs);
});

class CompletedTasksNotifier extends StateNotifier<Set<String>> {
  CompletedTasksNotifier(this._prefs)
      : _timestamps = {},
        super({}) {
    _loadAndPurge();
  }

  final SharedPreferences _prefs;

  // etlId → 완료 처리 시각 (60일 auto-purge용)
  final Map<String, DateTime> _timestamps;

  static const _purgeDays = 60;

  void _loadAndPurge() {
    final raw = _prefs.getString(kCompletedTasks);
    if (raw == null) return;

    try {
      final decoded = jsonDecode(raw);
      final cutoff = DateTime.now().subtract(const Duration(days: _purgeDays));
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

      state = _timestamps.keys.toSet();

      // 오래된 항목이 정리된 경우 새 포맷으로 저장
      final purged = beforeCount != _timestamps.length;
      if (decoded is List || purged) {
        _save();
      }
    } catch (_) {}
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

// ─── 개발자 모드 (Analytics 비활성화) ───────────────────────────────────────

final devModeProvider =
    StateNotifierProvider<DevModeNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return DevModeNotifier(prefs);
});

class DevModeNotifier extends StateNotifier<bool> {
  DevModeNotifier(this._prefs) : super(_prefs.getBool(kDevMode) ?? false);
  final SharedPreferences _prefs;

  void toggle() {
    state = !state;
    _prefs.setBool(kDevMode, state);
  }
}

// ─── 새 과제 알림 ON/OFF ─────────────────────────────────────────────────────

final newAssignmentNotifProvider =
    StateNotifierProvider<BoolSettingNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return BoolSettingNotifier(prefs, kNewAssignmentNotif, defaultValue: true);
});

// ─── 공지사항 알림 ON/OFF ──────────────────────────────────────────────────────

final newAnnouncementNotifProvider =
    StateNotifierProvider<BoolSettingNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return BoolSettingNotifier(prefs, kNewAnnouncementNotif, defaultValue: true);
});

class BoolSettingNotifier extends StateNotifier<bool> {
  BoolSettingNotifier(this._prefs, this._key, {bool defaultValue = false})
      : super(_prefs.getBool(_key) ?? defaultValue);
  final SharedPreferences _prefs;
  final String _key;

  void set(bool value) {
    state = value;
    _prefs.setBool(_key, value);
  }
}

// ─── 커스텀 일정 (학원·과외 등) ───────────────────────────────────────────────

final customEventsProvider =
    StateNotifierProvider<CustomEventsNotifier, List<CustomEvent>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return CustomEventsNotifier(prefs);
});

class CustomEventsNotifier extends StateNotifier<List<CustomEvent>> {
  CustomEventsNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;

  static List<CustomEvent> _load(SharedPreferences prefs) {
    final raw = prefs.getString(kCustomEvents);
    if (raw == null) return [];
    return CustomEvent.decodeList(raw); // 파싱 실패 시 [] 반환
  }

  void add(CustomEvent event) {
    state = [...state, event];
    _save();
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
    _save();
  }

  void _save() {
    _prefs.setString(kCustomEvents, CustomEvent.encodeList(state));
  }
}

// ─── mySNU 시간표 세션 (WebView 로그인 후 추출) ──────────────────────────────

final mySNUSessionsProvider =
    StateNotifierProvider<MySNUSessionsNotifier, List<ClassSession>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return MySNUSessionsNotifier(prefs);
});

class MySNUSessionsNotifier extends StateNotifier<List<ClassSession>> {
  MySNUSessionsNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;

  static List<ClassSession> _load(SharedPreferences prefs) {
    final raw = prefs.getString(kMySNUSessions);
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
}

// ─── 단과대 / 학과 코드 ────────────────────────────────────────────────────────

final collegeCodeProvider =
    StateNotifierProvider<StringSettingNotifier, String?>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return StringSettingNotifier(prefs, kCollegeCode);
});

final departmentCodeProvider =
    StateNotifierProvider<StringSettingNotifier, String?>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return StringSettingNotifier(prefs, kDepartmentCode);
});

// ─── 온보딩 완료 여부 ─────────────────────────────────────────────────────────

final onboardingCompleteProvider =
    StateNotifierProvider<BoolSettingNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return BoolSettingNotifier(prefs, kOnboardingComplete);
});

// ─── 즐겨찾기 제휴 식당 ─────────────────────────────────────────────────────────

final favPartnersProvider =
    StateNotifierProvider<FavPartnersNotifier, Set<String>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return FavPartnersNotifier(prefs);
});

class FavPartnersNotifier extends StateNotifier<Set<String>> {
  FavPartnersNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;

  static Set<String> _load(SharedPreferences prefs) =>
      (prefs.getStringList(kFavPartners) ?? []).toSet();

  void toggle(String id) {
    if (state.contains(id)) {
      state = state.difference({id});
    } else {
      state = {...state, id};
    }
    _prefs.setStringList(kFavPartners, state.toList());
  }
}

// ─── 즐겨찾기 장소 ────────────────────────────────────────────────────────────

final favVenuesProvider =
    StateNotifierProvider<FavVenuesNotifier, Set<String>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return FavVenuesNotifier(prefs);
});

class FavVenuesNotifier extends StateNotifier<Set<String>> {
  FavVenuesNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;

  static Set<String> _load(SharedPreferences prefs) =>
      (prefs.getStringList(kFavVenues) ?? []).toSet();

  void toggle(String venueId) {
    if (state.contains(venueId)) {
      state = state.difference({venueId});
    } else {
      state = {...state, venueId};
    }
    _prefs.setStringList(kFavVenues, state.toList());
  }
}

// ─── 과제별 메모 ──────────────────────────────────────────────────────────────

final memosProvider =
    StateNotifierProvider<MemosNotifier, Map<String, String>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return MemosNotifier(prefs);
});

class MemosNotifier extends StateNotifier<Map<String, String>> {
  MemosNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;

  static Map<String, String> _load(SharedPreferences prefs) {
    final raw = prefs.getString(kMemos);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  void set(String etlId, String memo) {
    state = {...state, etlId: memo};
    _save();
  }

  void remove(String etlId) {
    final next = Map<String, String>.from(state);
    next.remove(etlId);
    state = next;
    _save();
  }

  void _save() {
    _prefs.setString(kMemos, jsonEncode(state));
  }
}
