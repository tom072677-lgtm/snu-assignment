import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import 'notification_service.dart';

// SharedPreferences 인스턴스 provider (main에서 override)
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden in main');
});

// 다크모드
final darkModeProvider = StateNotifierProvider<DarkModeNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return DarkModeNotifier(prefs);
});

class DarkModeNotifier extends StateNotifier<bool> {
  DarkModeNotifier(this._prefs) : super(_prefs.getBool(kDarkMode) ?? false);
  final SharedPreferences _prefs;

  void toggle() {
    state = !state;
    _prefs.setBool(kDarkMode, state);
  }
}

// eTL 설정
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

// 완료된 과제 ID 목록
final completedTasksProvider =
    StateNotifierProvider<CompletedTasksNotifier, Set<String>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return CompletedTasksNotifier(prefs);
});

class CompletedTasksNotifier extends StateNotifier<Set<String>> {
  CompletedTasksNotifier(this._prefs)
      : super(_load(_prefs));
  final SharedPreferences _prefs;

  static Set<String> _load(SharedPreferences prefs) {
    final raw = prefs.getString(kCompletedTasks);
    if (raw == null) return {};
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  void complete(String etlId) {
    state = {...state, etlId};
    _save();
    // 완료 즉시 고정 알림 취소 (다음 fetch 기다리지 않음)
    NotificationService.cancelOngoingNotification(etlId).ignore();
  }

  void undo(String etlId) {
    state = state.difference({etlId});
    _save();
  }

  void _save() {
    _prefs.setString(kCompletedTasks, jsonEncode(state.toList()));
  }
}

// 과제별 메모
final memosProvider = StateNotifierProvider<MemosNotifier, Map<String, String>>((ref) {
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
