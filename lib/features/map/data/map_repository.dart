import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import 'snu_places.dart';

enum RouteMode { walk, bike, transit, car }

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

class RouteLeg {
  final String type; // 'walk' | 'bus' | 'subway'
  final String name;
  final String color;
  final int durationSeconds;
  final int distanceMeters;
  final String? startStation;
  final String? endStation;
  final int? subwayCode;   // ODSAY 지하철 코드 (subway만 해당)
  final String? stId;      // 버스 정류장 내부 ID (bus만 해당, ODSAY startStationID)
  final String? busRouteId; // 버스 노선 ID (bus만 해당, ODSAY lane[0].busRouteId)

  const RouteLeg({
    required this.type,
    required this.name,
    required this.color,
    required this.durationSeconds,
    required this.distanceMeters,
    this.startStation,
    this.endStation,
    this.subwayCode,
    this.stId,
    this.busRouteId,
  });

  factory RouteLeg.fromJson(Map<String, dynamic> j) => RouteLeg(
        type: j['type'] as String? ?? 'walk',
        name: j['name'] as String? ?? '',
        color: j['color'] as String? ?? '#4CAF50',
        durationSeconds: (j['duration'] as num? ?? 0).toInt(),
        distanceMeters: (j['distance'] as num? ?? 0).toInt(),
        startStation: j['startStation'] as String?,
        endStation: j['endStation'] as String?,
        subwayCode: j['subwayCode'] as int?,
        stId: j['stId'] as String?,
        busRouteId: j['busRouteId'] as String?,
      );
}

class RouteStep {
  final String description;
  final int distanceMeters;
  final int turnType;

  const RouteStep({
    required this.description,
    required this.distanceMeters,
    required this.turnType,
  });

  factory RouteStep.fromJson(Map<String, dynamic> j) => RouteStep(
        description: j['description'] as String? ?? '',
        distanceMeters: (j['distance'] as num? ?? 0).toInt(),
        turnType: (j['turnType'] as num? ?? 0).toInt(),
      );
}

class RouteResult {
  final double durationSeconds;
  final double distanceMeters;
  final int fare;
  final List<(double lat, double lng)> path;
  final List<RouteLeg> legs;
  final List<RouteStep> steps;

  const RouteResult({
    required this.durationSeconds,
    required this.distanceMeters,
    this.fare = 0,
    required this.path,
    this.legs = const [],
    this.steps = const [],
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
    String norm(String s) => s
        .replaceAll('서울대학교', '')
        .replaceAll('서울대', '')
        .replaceAll(' ', '')
        .toLowerCase();
    final localNorms = local.map((r) => norm(r.name)).toSet();
    final deduped = server.where((r) => !localNorms.contains(norm(r.name))).toList();
    return [...local, ...deduped];
  }

  Future<RouteResult> getRoute({
    required RouteMode mode,
    required double olat,
    required double olng,
    required double dlat,
    required double dlng,
  }) async {
    if (mode == RouteMode.transit) {
      final routes = await getTransitRoutes(olat: olat, olng: olng, dlat: dlat, dlng: dlng);
      return routes.first;
    }

    final String endpoint = switch (mode) {
      RouteMode.bike => '/api/route/osrm/bike',
      RouteMode.car  => '/api/route/tmap/car',
      _              => '/api/route/tmap/pedestrian',
    };
    final response = await DioClient.instance.post(
      endpoint,
      data: {'olat': olat, 'olng': olng, 'dlat': dlat, 'dlng': dlng},
    );
    final data = response.data as Map<String, dynamic>;
    final path = _parsePath(data['path'] as List);
    final steps = (data['steps'] as List? ?? [])
        .map((e) => RouteStep.fromJson(e as Map<String, dynamic>))
        .toList();

    return RouteResult(
      durationSeconds: (data['duration'] as num).toDouble(),
      distanceMeters: (data['distance'] as num).toDouble(),
      path: path,
      steps: steps,
    );
  }

  /// 버스/지하철 실시간 도착 메시지 반환. 키 미설정/실패 시 null.
  Future<String?> getTransitArrival({
    required String legType,
    required String routeName,
    String? startStation,
    int? subwayCode,
    String? stId,
    String? busRouteId,
  }) async {
    try {
      final response = await DioClient.instance.post(
        '/api/transit/arrival',
        data: {
          'legType': legType,
          'routeName': routeName,
          if (startStation != null) 'startStation': startStation,
          if (subwayCode != null) 'subwayCode': subwayCode,
          if (stId != null) 'stId': stId,
          if (busRouteId != null) 'busRouteId': busRouteId,
        },
      );
      return response.data['arrmsg'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 대중교통 경로 최대 3개 반환 (첫 번째가 최적 경로)
  Future<List<RouteResult>> getTransitRoutes({
    required double olat,
    required double olng,
    required double dlat,
    required double dlng,
  }) async {
    final response = await DioClient.instance.get(
      '/api/route/odsay/transit',
      queryParameters: {'olat': olat, 'olng': olng, 'dlat': dlat, 'dlng': dlng},
    );
    final data = response.data as Map<String, dynamic>;

    // 새 서버 응답(routes 배열) 또는 구형 flat 응답 모두 처리
    final List<dynamic> rawRoutes = data.containsKey('routes')
        ? data['routes'] as List
        : [data];

    if (rawRoutes.isEmpty) throw Exception('경로 없음');

    return rawRoutes.map((r) => _routeFromJson(r as Map<String, dynamic>)).toList();
  }

  RouteResult _routeFromJson(Map<String, dynamic> r) {
    final path = _parsePath(r['path'] as List);
    final legs = (r['legs'] as List? ?? [])
        .map((e) => RouteLeg.fromJson(e as Map<String, dynamic>))
        .toList();
    return RouteResult(
      durationSeconds: (r['duration'] as num).toDouble(),
      distanceMeters: (r['distance'] as num).toDouble(),
      fare: (r['fare'] as num? ?? 0).toInt(),
      path: path,
      legs: legs,
    );
  }

  List<(double, double)> _parsePath(List raw) => raw.map((p) {
        final pair = p as List;
        return ((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
      }).toList();
}

final mapRepositoryProvider = Provider<MapRepository>((_) => MapRepository());
