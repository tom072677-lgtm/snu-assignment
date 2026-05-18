import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../../../shared/providers/settings_provider.dart';
import '../domain/restaurant.dart';

const _kRestaurantCache = 'cache_restaurant_v1';

class RestaurantNotifier
    extends AutoDisposeAsyncNotifier<List<Restaurant>> {
  @override
  Future<List<Restaurant>> build() async {
    final cached = _loadCache();
    if (cached != null) {
      // 캐시 즉시 반환 + 백그라운드 갱신
      Future.microtask(_backgroundRefresh);
      return cached;
    }
    return _fetch();
  }

  Future<void> _backgroundRefresh() async {
    try {
      final fresh = await _fetch();
      state = AsyncData(fresh);
    } catch (_) {
      // 실패 시 캐시 유지
    }
  }

  Future<List<Restaurant>> _fetch() async {
    final response = await DioClient.instance.get('/api/restaurant/snuco');
    final data = response.data as Map<String, dynamic>;
    final list = (data['restaurants'] as List)
        .map((e) => Restaurant.fromJson(e as Map<String, dynamic>))
        .toList();
    _saveCache(list);
    return list;
  }

  List<Restaurant>? _loadCache() {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_kRestaurantCache);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (json['date'] != today) return null; // 날짜 바뀌면 캐시 무효
      return (json['data'] as List)
          .map((e) => Restaurant.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  void _saveCache(List<Restaurant> list) {
    final prefs = ref.read(sharedPrefsProvider);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    prefs.setString(
      _kRestaurantCache,
      jsonEncode({
        'date': today,
        'data': list
            .map((r) => {
                  'name': r.name,
                  'breakfast': r.breakfast,
                  'lunch': r.lunch,
                  'dinner': r.dinner,
                })
            .toList(),
      }),
    );
  }

  /// pull-to-refresh: 로딩 스피너 없이 조용히 갱신
  Future<void> refresh() async {
    try {
      final fresh = await _fetch();
      state = AsyncData(fresh);
    } catch (e, st) {
      if (state is! AsyncData) state = AsyncError(e, st);
    }
  }
}

final restaurantProvider =
    AsyncNotifierProvider.autoDispose<RestaurantNotifier, List<Restaurant>>(
  RestaurantNotifier.new,
);
