import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../domain/shuttle_models.dart';

class ShuttleRepository {
  // 셔틀 전용 Dio — Render cold start를 고려해 receive timeout 90초
  final Dio _dio = DioClient.withTimeout(receiveSeconds: 90);

  List<ShuttleRoute>? _routesCache;
  DateTime? _routesCachedAt;
  static const _routesCacheTtl = Duration(minutes: 10);

  Future<List<ShuttleRoute>> fetchRoutes() async {
    final now = DateTime.now();
    if (_routesCache != null &&
        _routesCachedAt != null &&
        now.difference(_routesCachedAt!) < _routesCacheTtl) {
      return _routesCache!;
    }
    // Render 무료 플랜 cold start 대응 — 실패 시 3초 후 1회 재시도
    try {
      return await _doFetchRoutes();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        await Future.delayed(const Duration(seconds: 3));
        return await _doFetchRoutes();
      }
      rethrow;
    }
  }

  Future<List<ShuttleRoute>> _doFetchRoutes() async {
    final res = await _dio.get<List<dynamic>>('/api/shuttle/routes');
    final routes = (res.data ?? [])
        .map((e) => ShuttleRoute.fromJson(e as Map<String, dynamic>))
        .toList();
    _routesCache = routes;
    _routesCachedAt = DateTime.now();
    return routes;
  }

  Future<ShuttleArrival> fetchArrival(int routeId, int stationCode) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/shuttle/arrival',
        queryParameters: {
          'route_id': routeId,
          'station_code': stationCode,
        },
      );
      return ShuttleArrival.fromJson(res.data!);
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map<String, dynamic>) return ShuttleArrival.fromJson(body);
      return ShuttleArrival(first: '조회 실패', error: e.message);
    }
  }
}

final shuttleRepositoryProvider = Provider((_) => ShuttleRepository());
