import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import 'snu_places.dart';

class PlaceResult {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String category;

  const PlaceResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.category,
  });

  factory PlaceResult.fromJson(Map<String, dynamic> json) => PlaceResult(
        name: json['name'] as String,
        address: json['address'] as String? ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        category: json['category'] as String? ?? '',
      );
}

class RouteResult {
  final double durationSeconds;
  final double distanceMeters;
  final List<(double lat, double lng)> path;

  const RouteResult({
    required this.durationSeconds,
    required this.distanceMeters,
    required this.path,
  });
}

class MapRepository {
  Future<List<PlaceResult>> searchPlace(
      String query, double? lat, double? lng) async {
    // 1) 로컬 SNU DB에서 먼저 매칭
    final local = searchSnuLocal(query);

    // 2) 서버(Kakao 이중 검색) 호출
    final params = <String, dynamic>{'q': query};
    if (lat != null && lng != null) {
      params['x'] = lng.toString();
      params['y'] = lat.toString();
    }
    final response =
        await DioClient.instance.get('/api/search-place', queryParameters: params);
    final server = (response.data as List)
        .map((e) => PlaceResult.fromJson(e as Map<String, dynamic>))
        .toList();

    // 3) 로컬 결과 우선, 서버 결과 중복 제거 후 병합
    // 정규화: "서울대학교", "서울대", 공백 제거 후 비교
    String _norm(String s) => s
        .replaceAll('서울대학교', '')
        .replaceAll('서울대', '')
        .replaceAll(' ', '')
        .toLowerCase();
    final localNorms = local.map((r) => _norm(r.name)).toSet();
    final deduped = server.where((r) => !localNorms.contains(_norm(r.name))).toList();
    return [...local, ...deduped];
  }

  Future<RouteResult> getOsrmRoute({
    required String profile, // walking | cycling
    required double olat,
    required double olng,
    required double dlat,
    required double dlng,
  }) async {
    final response = await DioClient.instance.get(
      '/api/route/osrm',
      queryParameters: {
        'profile': profile,
        'olat': olat,
        'olng': olng,
        'dlat': dlat,
        'dlng': dlng,
      },
    );
    final data = response.data as Map<String, dynamic>;
    // path는 [[lat, lng], ...] 형태
    final pathList = (data['path'] as List).map((p) {
      final pair = p as List;
      return ((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
    }).toList();

    return RouteResult(
      durationSeconds: (data['duration'] as num).toDouble(),
      distanceMeters: (data['distance'] as num).toDouble(),
      path: pathList,
    );
  }
}

final mapRepositoryProvider = Provider<MapRepository>((_) => MapRepository());
