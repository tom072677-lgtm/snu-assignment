import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/dio_client.dart';
import 'settings_provider.dart';

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

class NotificationService {
  static final _localNotif = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'sharap_alerts',
    '샤랍 알림',
    description: '과제 마감 알림',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    // 로컬 알림 초기화
    await _localNotif.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

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

  /// FCM 토큰을 서버에 전송 (서버는 FCM 발송에 사용)
  Future<void> _registerToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final old = prefs.getString(kFcmToken);
      if (old == token) return; // 변경 없으면 스킵
      await DioClient.instance.post('/api/fcm/register', data: {'token': token});
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
