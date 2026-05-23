import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../domain/shuttle_models.dart';

class ShuttleRepository {
  final Dio _dio = DioClient.instance;

  Future<List<ShuttleRoute>> fetchRoutes() async {
    final res = await _dio.get<List<dynamic>>('/api/shuttle/routes');
    return (res.data ?? [])
        .map((e) => ShuttleRoute.fromJson(e as Map<String, dynamic>))
        .toList();
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
