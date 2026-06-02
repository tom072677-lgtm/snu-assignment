import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/dio_client.dart';

/// 백그라운드/종료 상태 FCM — 공지사항·새 과제 data-only 메시지 처리.
/// top-level 함수 필요 (main.dart 에서 등록).
Future<void> handleBackgroundFcm(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'] as String? ?? '';

  // notification payload가 있으면 Android가 자동으로 표시함.
  // 사용자가 해당 타입을 비활성화한 경우 자동 표시된 알림을 취소한다.
  if (message.notification != null) {
    final prefs = await SharedPreferences.getInstance();
    final shouldSuppress =
        (type == 'new_assignment' && !(prefs.getBool(kNewAssignmentNotif) ?? true)) ||
        (type == 'announcement' && !(prefs.getBool(kNewAnnouncementNotif) ?? true));
    if (shouldSuppress) {
      final localNotif = FlutterLocalNotificationsPlugin();
      await localNotif.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      final android = localNotif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // FCM 알림 메시지는 서버가 notification_id를 지정하지 않으면 ID=0이 기본값.
      await android?.cancel(0, tag: message.notification?.android?.tag);
    }
    return;
  }

  // data-only 메시지: 직접 로컬 알림 표시
  final localNotif = FlutterLocalNotificationsPlugin();
  await localNotif.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  if (type == 'announcement') {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(kNewAnnouncementNotif) ?? true)) return;
    final announcementId = data['announcementId'] ?? data['id'] ?? '';
    await localNotif.show(
      NotificationService._stableId(
          'announcement:${announcementId.isNotEmpty ? announcementId : 'ann_${data['title']?.hashCode}'}'),
      data['title'] ?? '새 공지사항',
      data['body'] ?? '과제 탭을 확인해 주세요',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.announcementChannelId,
          NotificationService.announcementChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  } else if (type == 'new_assignment') {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(kNewAssignmentNotif) ?? true)) return;
    final etlId = data['etlId'] ?? '';
    await localNotif.show(
      NotificationService._stableId('assignment:${etlId.isNotEmpty ? etlId : 'new_assign'}'),
      data['title'] ?? '새 과제',
      data['body'] ?? '과제 탭을 확인해 주세요',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.alertChannelId,
          NotificationService.alertChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

class NotificationService {
  static final _localNotif = FlutterLocalNotificationsPlugin();

  // FCM 토큰 등록 전에 subscribeEtl이 호출된 경우 URL 보관 → 토큰 등록 후 재시도
  String? _pendingEtlUrl;

  // ── 채널 ID 상수 (외부에서 참조 가능) ────────────────────────────────────
  static const alertChannelId   = 'sharap_alerts';
  static const alertChannelName = '샤랍 알림';
  static const announcementChannelId   = 'sharap_announcements';
  static const announcementChannelName = '샤랍 공지사항 알림';

  // 일반 알림 채널 (FCM 포그라운드 / 새 과제)
  static const _channel = AndroidNotificationChannel(
    alertChannelId,
    alertChannelName,
    description: '새 과제 및 마감 알림',
    importance: Importance.high,
  );

  // 공지사항 알림 채널
  static const _announcementChannel = AndroidNotificationChannel(
    announcementChannelId,
    announcementChannelName,
    description: '교수님 공지사항 알림',
    importance: Importance.high,
  );

  // ongoing 고정 알림 채널 (24h 이내 과제 — 스와이프 삭제 불가)
  static const _ongoingChannel = AndroidNotificationChannel(
    'sharap_ongoing',
    '샤랍 마감 임박 알림',
    description: '24시간 이내 마감 과제 고정 알림',
    importance: Importance.high,
  );

  // 폭탄 긴급 알림 채널 (heads-up 팝업 보장 — Importance.max)
  static const _bombChannelId   = 'sharap_bomb';
  static const _bombChannelName = '샤랍 폭탄 알림';
  static const _bombChannel = AndroidNotificationChannel(
    _bombChannelId,
    _bombChannelName,
    description: '24시간 이내 마감 과제 긴급 팝업 알림',
    importance: Importance.max,
  );

  /// etlId → 안정적인 정수 알림 ID (앱 재시작 후에도 동일)
  /// Dart의 String.hashCode는 실행마다 달라질 수 있으므로
  /// djb2 해시로 결정적(deterministic) ID를 보장함
  static int _stableId(String etlId) {
    var h = 5381;
    for (final c in etlId.codeUnits) {
      h = ((h << 5) + h + c) & 0x7FFFFFFF; // 양수 31비트 유지
    }
    return h == 0 ? 1 : h;
  }

  Future<void> initialize() async {
    // 로컬 알림 초기화
    await _localNotif.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    final androidPlugin = _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.createNotificationChannel(_announcementChannel);
    await androidPlugin?.createNotificationChannel(_ongoingChannel);
    await androidPlugin?.createNotificationChannel(_bombChannel);

    // FCM 권한 요청
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] 권한: ${settings.authorizationStatus}');

    // 포그라운드 알림 표시 설정
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 포그라운드 메시지 수신
    FirebaseMessaging.onMessage.listen((message) {
      _handleForegroundMessage(message);
    });

    // FCM 토큰 서버에 등록
    final token = await messaging.getToken();
    if (token != null) {
      await _registerToken(token);
    }
    // 토큰 갱신 시: 서버 재등록 + 기존 구독 재시도
    messaging.onTokenRefresh.listen((newToken) async {
      await _registerToken(newToken);
      // eTL 구독 상태 복원 (과제 또는 공지사항 알림 중 하나라도 ON이면 재구독)
      final prefs = await SharedPreferences.getInstance();
      final icalUrl = prefs.getString(kIcalUrl);
      final assignmentOn = prefs.getBool(kNewAssignmentNotif) ?? true;
      final announcementOn = prefs.getBool(kNewAnnouncementNotif) ?? true;
      if (icalUrl != null && (assignmentOn || announcementOn)) {
        await subscribeEtl(icalUrl: icalUrl);
      }
    });
  }

  /// 포그라운드 FCM 메시지 처리 — type별 분기 + 로컬 설정 가드
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'] as String? ?? '';
    final prefs = await SharedPreferences.getInstance();

    // deadline 타입 → ongoing 알림 갱신 (설정 무관)
    if (type == 'deadline' && data['etlId'] != null) {
      try {
        final dueDate = DateTime.parse(data['dueDate']!);
        final remaining = dueDate.difference(DateTime.now());
        if (remaining.inSeconds > 0) {
          await showOngoingNotification(
            etlId: data['etlId']!,
            title: data['title'] ?? '',
            courseName: data['courseName'] ?? '',
            remaining: remaining,
          );
        }
      } catch (e) {
        debugPrint('[FCM] ongoing 알림 생성 실패: $e');
      }
      return;
    }

    // 새 과제 알림 (로컬 설정 가드)
    if (type == 'new_assignment') {
      if (!(prefs.getBool(kNewAssignmentNotif) ?? true)) return;
      final etlId = data['etlId'] ?? '';
      final n = message.notification;
      await _localNotif.show(
        _stableId('assignment:${etlId.isNotEmpty ? etlId : 'new_assign'}'),
        n?.title ?? data['title'] ?? '새 과제',
        n?.body ?? data['body'] ?? '과제 탭을 확인해 주세요',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id, _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      return;
    }

    // 공지사항 알림 (로컬 설정 가드)
    if (type == 'announcement') {
      if (!(prefs.getBool(kNewAnnouncementNotif) ?? true)) return;
      final announcementId = data['announcementId'] ?? data['id'] ?? '';
      final n = message.notification;
      await _localNotif.show(
        _stableId('announcement:${announcementId.isNotEmpty ? announcementId : 'ann_${data['title']?.hashCode}'}'),
        n?.title ?? data['title'] ?? '새 공지사항',
        n?.body ?? data['body'] ?? '공지사항을 확인해 주세요',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _announcementChannel.id,
            _announcementChannel.name,
            channelDescription: _announcementChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      return;
    }

    // 기타 notification payload 표시
    final notification = message.notification;
    final android = message.notification?.android;
    if (notification != null && android != null) {
      await _localNotif.show(
        _stableId(notification.title ?? 'sys'),
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id, _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    }
  }

  /// 텍스트 진행바 생성 (남은 시간 비율 시각화)
  static String _progressBar(Duration remaining) {
    const total = 24 * 3600;
    final secs = remaining.inSeconds.clamp(0, total);
    // 경과 비율 (0 = 24h 남음, 1 = 마감)
    final ratio = 1.0 - (secs / total);
    const bars = 12;
    final filled = (ratio * bars).round().clamp(0, bars);
    final empty = bars - filled;
    return '[${'█' * filled}${'░' * empty}]';
  }

  /// 24h 이내 과제용 고정 알림 (스와이프 삭제 불가)
  /// [headsUp] true: 폭탄 채널로 팝업 알림(non-ongoing) + ongoing 알림 동시 발송
  ///           false: ongoing 알림만 조용히 갱신
  Future<void> showOngoingNotification({
    required String etlId,
    required String title,
    required String courseName,
    required Duration remaining,
    bool headsUp = false,
  }) async {
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final timeStr = h > 0 ? '$h시간 $m분 후 마감' : '$m분 후 마감';
    final notifTitle = '💣 ${courseName.isNotEmpty ? courseName : title}';
    final bar = _progressBar(remaining);
    final body = '$bar  $timeStr\n$title';

    // ① ongoing 알림 — 알림 바에 항상 고정 (스와이프 불가)
    await _localNotif.show(
      _stableId('deadline:$etlId'),
      notifTitle,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _ongoingChannel.id,
          _ongoingChannel.name,
          channelDescription: _ongoingChannel.description,
          importance: Importance.low,   // 채널은 high이지만 업데이트 시 소리 없음
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          styleInformation: BigTextStyleInformation(body, contentTitle: notifTitle),
        ),
      ),
    );

    if (!headsUp) return;

    // ② heads-up 팝업 전용 알림 — non-ongoing, 별도 ID
    // fullScreenIntent: Samsung Edge Lighting 우회 → 화면 위에 팝업 카드 표시
    // Android 14+에서는 USE_FULL_SCREEN_INTENT 권한이 필요 (앱 설정에서 허가)
    final bombId = _stableId('bomb:$etlId');
    await _localNotif.show(
      bombId,
      notifTitle,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _bombChannelId,
          _bombChannelName,
          importance: Importance.max,
          priority: Priority.max,
          ongoing: false,
          autoCancel: true,
          onlyAlertOnce: false,
          fullScreenIntent: true,   // Samsung Edge Lighting 우회
          styleInformation: BigTextStyleInformation(body, contentTitle: notifTitle),
        ),
      ),
    );

    // [Codex P2 수정] 30초 후 자동 취소 — 팝업 역할만 하고 알림 바에서 제거
    // ongoing 알림(deadline:)이 계속 남아 있으므로 중복 표시 방지
    Future.delayed(const Duration(seconds: 30), () {
      _localNotif.cancel(bombId);
    });
  }

  /// heads-up 팝업 전용 알림만 취소 (bomb: prefix)
  static Future<void> cancelBombNotification(String etlId) async {
    await _localNotif.cancel(_stableId('bomb:$etlId'));
  }

  /// Samsung 기기에서 폭탄 알림 채널 설정 페이지 열기
  /// → 사용자가 Edge Lighting 대신 "팝업으로 표시" 선택 가능
  static Future<void> openBombChannelSettings() async {
    const ch = MethodChannel('com.tom07.sharap/settings');
    try {
      await ch.invokeMethod('openChannelSettings', {'channelId': _bombChannelId});
    } catch (e) {
      debugPrint('[Notif] 채널 설정 열기 실패: $e');
    }
  }

  /// 앱 포그라운드에서 urgent 목록 변경 시 알림 동기화
  /// [newEtlIds] 현재 urgent 과제 ID 집합 — 없어진 ID는 알림 취소
  Future<void> syncUrgentNotifications({
    required List<({String etlId, String title, String courseName, Duration remaining})> assignments,
    required Set<String> previousEtlIds,
  }) async {
    final currentIds = assignments.map((a) => a.etlId).toSet();

    // 새로 추가된 과제 → heads-up 팝업
    for (final a in assignments) {
      final isNew = !previousEtlIds.contains(a.etlId);
      if (a.remaining.inSeconds > 0) {
        await showOngoingNotification(
          etlId: a.etlId,
          title: a.title,
          courseName: a.courseName,
          remaining: a.remaining,
          headsUp: isNew,
        );
      }
    }

    // 더 이상 urgent 아닌 과제 → ongoing + bomb 알림 모두 취소
    for (final oldId in previousEtlIds) {
      if (!currentIds.contains(oldId)) {
        await cancelOngoingNotification(oldId); // ongoing + bomb 둘 다 취소
      }
    }
  }

  /// 과제 완료/만료 시 고정 알림 + 팝업 알림 모두 취소
  static Future<void> cancelOngoingNotification(String etlId) async {
    await _localNotif.cancel(_stableId('deadline:$etlId'));
    await _localNotif.cancel(_stableId('bomb:$etlId'));
  }

  /// FCM 토큰을 서버에 전송
  Future<void> _registerToken(String token) async {
    try {
      await DioClient.instance.post('/api/fcm/register', data: {'token': token});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kFcmToken, token);
      debugPrint('[FCM] 토큰 등록 완료');
      // 토큰 없어서 보류됐던 eTL 구독 재시도
      final pending = _pendingEtlUrl;
      if (pending != null) {
        _pendingEtlUrl = null;
        await subscribeEtl(icalUrl: pending);
      }
    } catch (e) {
      debugPrint('[FCM] 토큰 등록 실패: $e');
    }
  }

  /// 새 과제 감지를 위해 eTL URL을 서버에 등록 (새 알림 구독)
  /// 성공하면 true, 실패하면 false 반환 (토큰 미발급 시 pending 처리 후 true 반환)
  Future<bool> subscribeEtl({
    required String icalUrl,
    String? canvasToken, // 서버에 전송하지 않음 (보안) — 파라미터는 호환성 유지
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(kFcmToken);
    if (token == null) {
      // 아직 토큰 미발급 — 등록 후 자동 재시도
      _pendingEtlUrl = icalUrl;
      return true; // pending 처리됐으므로 사용자 입장에선 성공으로 처리
    }
    try {
      await DioClient.instance.post('/api/fcm/subscribe-etl', data: {
        'token': token,
        'icalUrl': icalUrl,
      });
      debugPrint('[FCM] eTL 구독 등록 완료');
      return true;
    } catch (e) {
      debugPrint('[FCM] eTL 구독 실패: $e');
      return false;
    }
  }

  /// 새 과제 감지 구독 해제
  Future<void> unsubscribeEtl() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(kFcmToken);
    if (token == null) return;
    try {
      await DioClient.instance.post('/api/fcm/unsubscribe-etl', data: {'token': token});
      debugPrint('[FCM] eTL 구독 해제 완료');
    } catch (e) {
      debugPrint('[FCM] eTL 구독 해제 실패: $e');
    }
  }

  /// 과제 목록 서버에 동기화 (FCM 알림 스케줄용)
  Future<void> syncTasksForNotification(
      List<Map<String, dynamic>> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(kFcmToken);
    if (token == null) return;
    try {
      await DioClient.instance.post('/api/fcm/sync-tasks', data: {
        'token': token,
        'tasks': tasks,
      });
    } catch (e) {
      debugPrint('[FCM] 과제 동기화 실패: $e');
    }
  }
}
