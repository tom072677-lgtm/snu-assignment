import 'dart:io';
import 'package:dio/dio.dart';

/// 흔한 예외를 사용자 친화적인 한국어 메시지로 변환한다.
String friendlyError(Object e) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '서버 응답이 느려요. 잠시 후 다시 시도해 주세요.';
      case DioExceptionType.connectionError:
        return '인터넷 연결을 확인해 주세요.';
      default:
        break;
    }
  }
  if (e is SocketException) return '인터넷 연결을 확인해 주세요.';
  return '정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
}
