import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants.dart';
import '../../../shared/providers/settings_provider.dart';
import '../domain/calendar_event.dart';

const _uuid = Uuid();

class CalendarRepository extends StateNotifier<List<CalendarEvent>> {
  CalendarRepository(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static List<CalendarEvent> _load(SharedPreferences prefs) {
    final raw = prefs.getString(kCalendarEvents);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void add(String title, DateTime dateTime) {
    final event = CalendarEvent(
      id: _uuid.v4(),
      title: title,
      dateTime: dateTime,
      source: 'user',
    );
    state = [...state, event];
    _save();
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
    _save();
  }

  void _save() {
    _prefs.setString(
      kCalendarEvents,
      jsonEncode(state.map((e) => e.toJson()).toList()),
    );
  }
}

final calendarRepositoryProvider =
    StateNotifierProvider<CalendarRepository, List<CalendarEvent>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return CalendarRepository(prefs);
});

// 날짜별 이벤트 맵 (user events only; assignments는 별도로 합침)
final calendarEventsMapProvider =
    Provider<Map<DateTime, List<CalendarEvent>>>((ref) {
  final events = ref.watch(calendarRepositoryProvider);
  final map = <DateTime, List<CalendarEvent>>{};
  for (final e in events) {
    final day = DateTime(e.dateTime.year, e.dateTime.month, e.dateTime.day);
    map.putIfAbsent(day, () => []).add(e);
  }
  return map;
});
