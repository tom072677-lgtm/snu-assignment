import 'package:dio/dio.dart';
import 'constants.dart';

class DioClient {
  DioClient._();
  static final Dio _instance = _createDio();

  static Dio get instance => _instance;

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: serverUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 45),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          // 네트워크 오류 로깅 (release에선 생략 가능)
          // ignore: avoid_print
          print('[Dio] ${e.requestOptions.path} → ${e.message}');
          handler.next(e);
        },
      ),
    );
    return dio;
  }
}
