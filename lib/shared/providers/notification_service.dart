import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/dio_client.dart';

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

class NotificationService {
  static final _localNotif = FlutterLocalNotificationsPlugin();

  // 일반 알림 채널 (FCM 포그라운드)
  static const _channel = AndroidNotificationChannel(
    'sharap_alerts',
    '샤랍 알림',
    description: '과제 마감 알림',
    importance: Importance.high,
  );

  // ongoing 고정 알림 채널 (24h 이내 과제 — 스와이프 삭제 불가)
  static const _ongoingChannel = AndroidNotificationChannel(
    'sharap_ongoing',
    '샤랍 마감 임박 알림',
    description: '24시간 이내 마감 과제 고정 알림',
    importance: Importance.high,
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
    await androidPlugin?.createNotificationChannel(_ongoingChannel);

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
      final data = message.data;

      // deadline 타입이면 ongoing 알림 갱신
      if (data['type'] == 'deadline' && data['etlId'] != null) {
        try {
          final dueDate = DateTime.parse(data['dueDate']!);
          final remaining = dueDate.difference(DateTime.now());
          if (remaining.inSeconds > 0) {
            showOngoingNotification(
              etlId: data['etlId']!,
              title: data['title'] ?? '',
              courseName: data['courseName'] ?? '',
              remaining: remaining,
            ).ignore();
          }
        } catch (e) {
          debugPrint('[FCM] ongoing 알림 생성 실패: $e');
        }
      }

      // 시스템 알림도 표시
      final notification = message.notification;
      final android = message.notification?.android;
      if (notification != null && android != null) {
        _localNotif.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
    });

    // FCM 토큰 서버에 등록
    final token = await messaging.getToken();
    if (token != null) {
      await _registerToken(token);
    }
    messaging.onTokenRefresh.listen(_registerToken);
  }

  /// 24h 이내 과제용 고정 알림 (스와이프 삭제 불가)
  Future<void> showOngoingNotification({
    required String etlId,
    required String title,
    required String courseName,
    required Duration remaining,
  }) async {
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final timeStr = h > 0 ? '$h시간 $m분 후 마감' : '$m분 후 마감';
    final notifTitle = courseName.isNotEmpty ? courseName : title;

    await _localNotif.show(
      _stableId(etlId),
      notifTitle,
      '$title  ·  $timeStr',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _ongoingChannel.id,
          _ongoingChannel.name,
          channelDescription: _ongoingChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
        ),
      ),
    );
  }

  /// 과제 완료/만료 시 고정 알림 취소 (static — CompletedTasksNotifier에서도 호출)
  static Future<void> cancelOngoingNotification(String etlId) async {
    await _localNotif.cancel(_stableId(etlId));
  }

  /// FCM 토큰을 서버에 전송
  Future<void> _registerToken(String token) async {
    try {
      await DioClient.instance.post('/api/fcm/register', data: {'token': token});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kFcmToken, token);
      debugPrint('[FCM] 토큰 등록 완료');
    } catch (e) {
      debugPrint('[FCM] 토큰 등록 실패: $e');
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
