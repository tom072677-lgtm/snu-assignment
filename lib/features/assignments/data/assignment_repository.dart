import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../../../shared/providers/notification_service.dart';
import '../../../shared/providers/settings_provider.dart';
import '../domain/assignment.dart';

const _kAssignmentsCache = 'cache_assignments_v1';

class AssignmentsNotifier
    extends AutoDisposeAsyncNotifier<List<Assignment>> {
  @override
  Future<List<Assignment>> build() async {
    final icalUrl = ref.watch(icalUrlProvider);
    final apiToken = ref.watch(canvasTokenProvider);

    if (icalUrl == null || icalUrl.isEmpty) return [];

    final cached = _loadCache(icalUrl);
    if (cached != null) {
      // 캐시 즉시 반환 + 백그라운드에서 최신 데이터 갱신
      Future.microtask(() => _backgroundRefresh(icalUrl, apiToken));
      return cached;
    }

    // 캐시 없음 → 서버에서 blocking 호출
    return _fetch(icalUrl, apiToken);
  }

  Future<void> _backgroundRefresh(String icalUrl, String? apiToken) async {
    try {
      final fresh = await _fetch(icalUrl, apiToken);
      state = AsyncData(fresh);
    } catch (_) {
      // 실패 시 캐시 데이터 유지
    }
  }

  Future<List<Assignment>> _fetch(String icalUrl, String? apiToken) async {
    final response = await DioClient.instance.post(
      '/api/sync-ical',
      data: {
        'icalUrl': icalUrl,
        if (apiToken != null && apiToken.isNotEmpty) 'apiToken': apiToken,
      },
    );
    final list = (response.data as List)
        .map((e) => Assignment.fromJson(e as Map<String, dynamic>))
        .toList();
    _saveCache(icalUrl, list);
    // FCM 알림 스케줄 서버 동기화
    _syncNotifications(list);
    return list;
  }

  void _syncNotifications(List<Assignment> list) {
    final notifService = ref.read(notificationServiceProvider);
    final tasks = list
        .map((a) => {
              'etlId': a.etlId,
              'title': a.title,
              'courseName': a.courseName,
              'dueDate': a.dueDate.toIso8601String(),
              'url': a.url,
            })
        .toList();
    notifService.syncTasksForNotification(tasks).ignore();
  }

  List<Assignment>? _loadCache(String currentIcalUrl) {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_kAssignmentsCache);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['icalUrl'] != currentIcalUrl) return null;
      // 30분 TTL: 초과 시 캐시 무효화
      final cachedAt = DateTime.tryParse(json['cachedAt'] as String? ?? '');
      if (cachedAt == null ||
          DateTime.now().difference(cachedAt).inMinutes > 30) {
        return null;
      }
      return (json['data'] as List)
          .map((e) => Assignment.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  void _saveCache(String icalUrl, List<Assignment> list) {
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setString(
      _kAssignmentsCache,
      jsonEncode({
        'icalUrl': icalUrl,
        'cachedAt': DateTime.now().toIso8601String(),
        'data': list
            .map((a) => {
                  'etlId': a.etlId,
                  'title': a.title,
                  'courseName': a.courseName,
                  'dueDate': a.dueDate.toIso8601String(),
                  'dateOnly': a.dateOnly,
                  'url': a.url,
                })
            .toList(),
      }),
    );
  }

  /// pull-to-refresh: 로딩 스피너 없이 조용히 갱신
  Future<void> refresh() async {
    final icalUrl = ref.read(icalUrlProvider);
    final apiToken = ref.read(canvasTokenProvider);
    if (icalUrl == null || icalUrl.isEmpty) return;
    try {
      final fresh = await _fetch(icalUrl, apiToken);
      state = AsyncData(fresh);
    } catch (e, st) {
      if (state is! AsyncData) state = AsyncError(e, st);
    }
  }
}

final assignmentsProvider =
    AsyncNotifierProvider.autoDispose<AssignmentsNotifier, List<Assignment>>(
  AssignmentsNotifier.new,
);
