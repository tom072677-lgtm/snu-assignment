import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'constants.dart';

class DioClient {
  DioClient._();
  static final Dio _instance = _createDio();

  static Dio get instance => _instance;

  /// 타임아웃이 다른 엔드포인트용 (셔틀 등 Render cold start 고려)
  static Dio withTimeout({int connectSeconds = 30, int receiveSeconds = 60}) =>
      _createDio(connectSeconds: connectSeconds, receiveSeconds: receiveSeconds);

  static Dio _createDio({int connectSeconds = 30, int receiveSeconds = 60}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: serverUrl,
        connectTimeout: Duration(seconds: connectSeconds),
        receiveTimeout: Duration(seconds: receiveSeconds),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          debugPrint('[Dio] ${e.requestOptions.path} → ${e.message}');
          handler.next(e);
        },
      ),
    );
    return dio;
  }
}
