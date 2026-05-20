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

  const RouteLeg({
    required this.type,
    required this.name,
    required this.color,
    required this.durationSeconds,
    required this.distanceMeters,
    this.startStation,
    this.endStation,
  });

  factory RouteLeg.fromJson(Map<String, dynamic> j) => RouteLeg(
        type: j['type'] as String? ?? 'walk',
        name: j['name'] as String? ?? '',
        color: j['color'] as String? ?? '#4CAF50',
        durationSeconds: (j['duration'] as num? ?? 0).toInt(),
        distanceMeters: (j['distance'] as num? ?? 0).toInt(),
        startStation: j['startStation'] as String?,
        endStation: j['endStation'] as String?,
      );
}

class RouteResult {
  final double durationSeconds;
  final double distanceMeters;
  final int fare;
  final List<(double lat, double lng)> path;
  final List<RouteLeg> legs;

  const RouteResult({
    required this.durationSeconds,
    required this.distanceMeters,
    this.fare = 0,
    required this.path,
    this.legs = const [],
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
      return _getTransitRoute(olat: olat, olng: olng, dlat: dlat, dlng: dlng);
    }

    final tmapMode = mode == RouteMode.car ? 'car' : 'pedestrian';
    final response = await DioClient.instance.post(
      '/api/route/tmap/$tmapMode',
      data: {'olat': olat, 'olng': olng, 'dlat': dlat, 'dlng': dlng},
    );
    final data = response.data as Map<String, dynamic>;
    final path = _parsePath(data['path'] as List);
    final distanceMeters = (data['distance'] as num).toDouble();

    final durationSeconds = mode == RouteMode.bike
        ? distanceMeters / (15000 / 3600)
        : (data['duration'] as num).toDouble();

    return RouteResult(
      durationSeconds: durationSeconds,
      distanceMeters: distanceMeters,
      path: path,
    );
  }

  Future<RouteResult> _getTransitRoute({
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
    final path = _parsePath(data['path'] as List);
    final legs = (data['legs'] as List? ?? [])
        .map((e) => RouteLeg.fromJson(e as Map<String, dynamic>))
        .toList();
    final fare = (data['fare'] as num? ?? 0).toInt();

    return RouteResult(
      durationSeconds: (data['duration'] as num).toDouble(),
      distanceMeters: (data['distance'] as num).toDouble(),
      fare: fare,
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
