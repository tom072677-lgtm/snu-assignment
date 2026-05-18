import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../domain/venue.dart';

class VenueRepository {
  List<Venue>? _cached;

  /// Load venues.json + merge live SNUCO menu + Instagram posts
  Future<List<Venue>> load() async {
    final venues = await _loadJson();

    // Parallel: SNUCO menu + Instagram posts (errors are silent)
    final results = await Future.wait<Map<String, dynamic>>([
      _fetchSnuco().catchError((_) => <String, dynamic>{}),
      _fetchInstagram().catchError((_) => <String, dynamic>{}),
    ]);

    final snucoData = results[0];
    final igData = results[1];

    // Apply SNUCO menu by snucoName mapping
    final snucoRestaurants = (snucoData['restaurants'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    for (final v in venues) {
      if (v.type == VenueType.snuco && v.snucoName != null) {
        final match = snucoRestaurants.where(
          (r) => (r['name'] as String?) == v.snucoName,
        ).firstOrNull;
        if (match != null) {
          v.snucoBreakfast = match['breakfast'] as String?;
          v.snucoLunch = match['lunch'] as String?;
          v.snucoDinner = match['dinner'] as String?;
        }
      }
      // Apply Instagram posts to instagram-type venue
      if (v.type == VenueType.instagram) {
        final posts = igData['posts'] as List?;
        if (posts != null) {
          v.instagramPosts = posts.cast<Map<String, dynamic>>();
        }
      }
    }

    _cached = venues;
    return venues;
  }

  List<Venue>? get cached => _cached;

  Future<List<Venue>> _loadJson() async {
    final raw = await rootBundle.loadString('assets/data/venues.json');
    final list = jsonDecode(raw) as List;
    return list.map((e) => Venue.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> _fetchSnuco() async {
    final res = await DioClient.instance.get('/api/restaurant/snuco');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _fetchInstagram() async {
    final res = await DioClient.instance.get('/api/restaurant/gangyeo');
    return res.data as Map<String, dynamic>;
  }
}

final venueRepositoryProvider = Provider<VenueRepository>((_) => VenueRepository());

final venuesProvider = FutureProvider.autoDispose<List<Venue>>((ref) {
  return ref.read(venueRepositoryProvider).load();
});
