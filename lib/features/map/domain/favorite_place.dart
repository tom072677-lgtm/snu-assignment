import 'dart:convert';

class FavoritePlace {
  final String name;
  final double lat;
  final double lng;

  const FavoritePlace({
    required this.name,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lng': lng};

  factory FavoritePlace.fromJson(Map<String, dynamic> j) => FavoritePlace(
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );

  static FavoritePlace? tryDecode(String? raw) {
    if (raw == null) return null;
    try {
      return FavoritePlace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
