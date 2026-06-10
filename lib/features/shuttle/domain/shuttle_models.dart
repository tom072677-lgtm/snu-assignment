class ShuttleStation {
  const ShuttleStation({required this.code, required this.name});
  final int code;
  final String name;

  factory ShuttleStation.fromJson(Map<String, dynamic> j) => ShuttleStation(
        code: (j['code'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
      );
}

class ShuttleRoute {
  const ShuttleRoute({
    required this.id,
    required this.name,
    required this.type,
    required this.stations,
  });
  final int id;
  final String name;
  final String type; // '교내' | '통학' | '야간' | '심야'
  final List<ShuttleStation> stations;

  factory ShuttleRoute.fromJson(Map<String, dynamic> j) => ShuttleRoute(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? '',
        stations: (j['stations'] as List? ?? const [])
            .map((s) => ShuttleStation.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class ShuttleArrival {
  const ShuttleArrival({required this.first, this.second, this.error});
  final String first;       // "3분 후", "곧 도착", "운행정보없음" 등
  final String? second;
  final String? error;

  bool get hasInfo => first != '운행정보없음' && first.isNotEmpty && error == null;

  factory ShuttleArrival.fromJson(Map<String, dynamic> j) => ShuttleArrival(
        first: j['first'] as String? ?? '운행정보없음',
        second: j['second'] as String?,
        error: j['error'] as String?,
      );
}
