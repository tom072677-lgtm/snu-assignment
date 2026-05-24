import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../../../core/widget_service.dart';
import '../../../shared/providers/notification_service.dart';
import '../../../shared/providers/settings_provider.dart';
import '../domain/assignment.dart';
import '../domain/assignment_detail.dart';

const _kAssignmentsCache = 'cache_assignments_v2';

class AssignmentsNotifier
    extends AutoDisposeAsyncNotifier<List<Assignment>> {
  @override
  Future<List<Assignment>> build() async {
    final icalUrl = ref.watch(icalUrlProvider);
    final apiToken = ref.watch(canvasTokenProvider);
    // assignmentDays가 바뀌면 자동으로 rebuild → 새 기간으로 재조회
    ref.watch(assignmentDaysProvider);

    // 완료 상태가 바뀌면 위젯만 갱신 (네트워크 재호출 없음)
    ref.listen(completedTasksProvider, (_, completedIds) {
      if (state case AsyncData(:final value)) {
        WidgetService.updateWidget(value, completedIds: completedIds).ignore();
      }
    });

    if (icalUrl == null || icalUrl.isEmpty) return [];

    final cached = _loadCache(icalUrl);
    if (cached != null) {
      // 캐시 즉시 반환 + 위젯 업데이트 + 백그라운드에서 최신 데이터 갱신
      final completed = ref.read(completedTasksProvider);
      WidgetService.updateWidget(cached, completedIds: completed).ignore();
      Future.microtask(() => _backgroundRefresh(icalUrl, apiToken));
      return cached;
    }

    // 캐시 없음 → 서버에서 blocking 호출
    try {
      return await _fetch(icalUrl, apiToken);
    } catch (e) {
      // 네트워크 실패 시 만료된 캐시라도 반환 (오프라인 fallback)
      final stale = _loadStaleCache(icalUrl);
      if (stale != null) return stale;
      rethrow;
    }
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
    final days = ref.read(assignmentDaysProvider);
    final response = await DioClient.instance.post(
      '/api/sync-ical',
      data: {
        'icalUrl': icalUrl,
        'days': days,
        if (apiToken != null && apiToken.isNotEmpty) 'apiToken': apiToken,
      },
    );
    final list = (response.data as List)
        .map((e) => Assignment.fromJson(e as Map<String, dynamic>))
        .toList();
    _saveCache(icalUrl, list);
    // FCM 알림 스케줄 서버 동기화
    _syncNotifications(list);
    // 새 과제 감지 구독 (eTL URL 서버 등록)
    _subscribeEtl(icalUrl, apiToken);
    // 홈 위젯 업데이트
    final completed = ref.read(completedTasksProvider);
    WidgetService.updateWidget(list, completedIds: completed).ignore();
    return list;
  }

  void _subscribeEtl(String icalUrl, String? apiToken) {
    // 새 과제 알림이 OFF면 구독하지 않음
    final notifEnabled = ref.read(newAssignmentNotifProvider);
    if (!notifEnabled) return;
    final notifService = ref.read(notificationServiceProvider);
    notifService.subscribeEtl(
      icalUrl: icalUrl,
      canvasToken: apiToken,
    ).ignore();
  }

  void _syncNotifications(List<Assignment> list) {
    final notifService = ref.read(notificationServiceProvider);
    final completed = ref.read(completedTasksProvider);
    final prefs = ref.read(sharedPrefsProvider);

    // 24h 이내 + 미완료 + 미만료 과제만 ongoing 알림 대상
    final shouldBeActive = <String>{
      for (final a in list)
        if (!a.isOverdue &&
            !completed.contains(a.etlId) &&
            a.remaining.inHours < 24)
          a.etlId,
    };

    // 이전에 활성화된 알림 Set 로드
    final prevActive =
        (prefs.getStringList('active_ongoing_etlIds') ?? []).toSet();

    // 더 이상 필요 없는 ongoing 알림 취소 (완료·만료·목록 제거된 과제)
    for (final etlId in prevActive) {
      if (!shouldBeActive.contains(etlId)) {
        NotificationService.cancelOngoingNotification(etlId).ignore();
      }
    }

    // 대상 과제 ongoing 알림 표시/갱신
    for (final a in list) {
      if (shouldBeActive.contains(a.etlId)) {
        notifService.showOngoingNotification(
          etlId: a.etlId,
          title: a.title,
          courseName: a.courseName,
          remaining: a.remaining,
        ).ignore();
      }
    }

    // 현재 활성 Set 저장
    prefs
        .setStringList('active_ongoing_etlIds', shouldBeActive.toList())
        .ignore();

    // 서버에 FCM 스케줄 동기화
    final tasks = list
        .map((a) => {
              'etlId': a.etlId,
              'title': a.title,
              'courseName': a.courseName,
              'dueDate': a.dueDate.toUtc().toIso8601String(),
              'dateOnly': a.dateOnly,
              'url': a.url,
            })
        .toList();
    notifService.syncTasksForNotification(tasks).ignore();
  }

  /// TTL 내 유효한 캐시 반환 (없으면 null)
  List<Assignment>? _loadCache(String currentIcalUrl) {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_kAssignmentsCache);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['icalUrl'] != currentIcalUrl) return null;
      // days가 바뀌면 캐시 무효화 (7→30일 전환 시 잘못된 캐시 반환 방지)
      final currentDays = ref.read(assignmentDaysProvider);
      if ((json['days'] as int?) != currentDays) return null;
      // 30분 TTL: 초과 시 캐시 무효화 (백그라운드 갱신은 별도)
      final cachedAt = DateTime.tryParse(json['cachedAt'] as String? ?? '');
      if (cachedAt == null ||
          DateTime.now().difference(cachedAt).inMinutes > 30) {
        return null;
      }
      return _parseAssignments(json['data'] as List);
    } catch (_) {
      return null;
    }
  }

  /// 오프라인 fallback: TTL 무시하고 마지막 캐시 반환
  List<Assignment>? _loadStaleCache(String currentIcalUrl) {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_kAssignmentsCache);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['icalUrl'] != currentIcalUrl) return null;
      return _parseAssignments(json['data'] as List);
    } catch (_) {
      return null;
    }
  }

  List<Assignment> _parseAssignments(List data) => data
      .map((e) => Assignment.fromJson(e as Map<String, dynamic>))
      .toList();

  void _saveCache(String icalUrl, List<Assignment> list) {
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setString(
      _kAssignmentsCache,
      jsonEncode({
        'icalUrl': icalUrl,
        'days': ref.read(assignmentDaysProvider),
        'cachedAt': DateTime.now().toIso8601String(),
        'data': list
            .map((a) => {
                  'etlId': a.etlId,
                  'title': a.title,
                  'courseName': a.courseName,
                  'dueDate': a.dueDate.toUtc().toIso8601String(),
                  'dateOnly': a.dateOnly,
                  'url': a.url,
                  if (a.courseId != null) 'courseId': a.courseId,
                  if (a.assignmentId != null) 'assignmentId': a.assignmentId,
                })
            .toList(),
      }),
    );
  }

  /// 과제 상세 정보 조회 (Canvas API)
  Future<AssignmentDetail> fetchDetail({
    required String courseId,
    required String assignmentId,
    required String apiToken,
  }) async {
    final response = await DioClient.instance.post(
      '/api/assignment-detail',
      data: {
        'courseId': courseId,
        'assignmentId': assignmentId,
        'apiToken': apiToken,
      },
    );
    return AssignmentDetail.fromJson(response.data as Map<String, dynamic>);
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
