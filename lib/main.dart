import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/analytics.dart';
import 'core/constants.dart';
import 'firebase_options.dart';
import 'shared/providers/notification_service.dart' show handleBackgroundFcm, notificationServiceProvider;
import 'shared/providers/settings_provider.dart';

/// 백그라운드 FCM 메시지 핸들러 (top-level 함수여야 함)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM BG] type=${message.data["type"]} title=${message.notification?.title}');
  await handleBackgroundFcm(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Crashlytics: Flutter 프레임워크 에러 → Firebase로 전송
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  // Crashlytics: 비동기 에러 (Zone 에러) → Firebase로 전송
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // 네이버 지도 SDK 초기화 (NCP 신규 인증 방식)
  await FlutterNaverMap().init(
    clientId: naverMapClientId,
    onAuthFailed: (e) => debugPrint('[NaverMap] 인증 실패: $e'),
  );

  // 한국어 날짜 포맷 초기화
  await initializeDateFormatting('ko');

  // SharedPreferences 초기화
  final prefs = await SharedPreferences.getInstance();

  // 개발자 모드: 앱 시작 직후 Analytics/Crashlytics 수집 여부 결정
  final isDevMode = prefs.getBool(kDevMode) ?? false;
  await Analytics.setDevMode(isDevMode);

  // Canvas 토큰: SecureStorage에서 읽기 (기존 SharedPreferences 값 마이그레이션)
  const secureStorage = FlutterSecureStorage();
  String? canvasToken = await secureStorage.read(key: kCanvasToken);
  if (canvasToken == null) {
    final legacy = prefs.getString(kCanvasToken);
    if (legacy != null && legacy.isNotEmpty) {
      await secureStorage.write(key: kCanvasToken, value: legacy);
      await prefs.remove(kCanvasToken);
      canvasToken = legacy;
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        canvasTokenInitProvider.overrideWithValue(canvasToken),
      ],
      child: const _AppInit(),
    ),
  );
}

/// 알림 서비스 초기화를 앱 시작 시 한 번만 실행
class _AppInit extends ConsumerWidget {
  const _AppInit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 최초 빌드 시 알림 초기화 (한 번만)
    ref.listen<Object?>(
      _notifInitProvider,
      (_, __) {},
    );
    return const SharapApp();
  }
}

final _notifInitProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(notificationServiceProvider);
  await service.initialize();
});
