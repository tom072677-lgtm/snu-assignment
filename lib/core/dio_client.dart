import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
          debugPrint('[Dio] ${e.requestOptions.path} → ${e.message}');
          handler.next(e);
        },
      ),
    );
    return dio;
  }
}
