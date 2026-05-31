import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';
import '../../../core/dio_client.dart';
import '../../../shared/providers/settings_provider.dart';
import '../domain/partner_restaurant.dart';

/// 하루 1회 갱신 기준 (초)
const int _kRefreshIntervalSeconds = 86400; // 24h
const int _kPartnerSeedVersion = 13;

/// 로컬 번들 seed 파일 경로 (서버 미가용 시 fallback).
const String _kPartnerSeedAsset = 'assets/data/partner_restaurants.json';

class PartnerRepository {
  PartnerRepository(this._prefs);

  final SharedPreferences _prefs;

  // ─── 캐시 읽기 ─────────────────────────────────────────────────────────────

  List<PartnerRestaurant> _loadCache() {
    final raw = _prefs.getString(kPartnerRestaurantsCache);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => PartnerRestaurant.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  bool _isCacheStale() {
    final seedVersion = _prefs.getInt(kPartnerRestaurantsSeedVersion) ?? 0;
    if (seedVersion != _kPartnerSeedVersion) return true;

    final fetchedAt = _prefs.getString(kPartnerRestaurantsFetchedAt);
    if (fetchedAt == null) return true;
    final ts = DateTime.tryParse(fetchedAt);
    if (ts == null) return true;
    return DateTime.now().difference(ts).inSeconds >= _kRefreshIntervalSeconds;
  }

  Future<void> _saveCache(List<PartnerRestaurant> list) async {
    final json = jsonEncode(list.map((r) => r.toJson()).toList());
    await _prefs.setString(kPartnerRestaurantsCache, json);
    await _prefs.setString(
      kPartnerRestaurantsFetchedAt,
      DateTime.now().toIso8601String(),
    );
    await _prefs.setInt(
      kPartnerRestaurantsSeedVersion,
      _kPartnerSeedVersion,
    );
  }

  // ─── 서버 fetch ────────────────────────────────────────────────────────────

  /// 서버 `/api/partner-restaurants` 엔드포인트에서 목록을 가져온다.
  /// 서버가 없거나 실패하면 빈 목록 반환 (캐시가 있으면 캐시 사용).
  Future<List<PartnerRestaurant>> _fetchFromServer() async {
    try {
      final res = await DioClient.instance
          .get('/api/partner-restaurants')
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final list = res.data as List;
      return list
          .map((e) => PartnerRestaurant.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 앱 번들에 포함된 로컬 seed 파일에서 제휴 식당 목록을 읽는다.
  /// 서버가 없을 때의 기본 데이터로 사용된다.
  Future<List<PartnerRestaurant>> _loadSeed() async {
    try {
      final raw = await rootBundle.loadString(_kPartnerSeedAsset);
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => PartnerRestaurant.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── 공개 API ──────────────────────────────────────────────────────────────

  /// 캐시가 만료된 경우 서버에서 새로 가져오고, 아니면 캐시를 반환.
  /// [forceRefresh] = true 이면 캐시 무시하고 항상 서버 호출.
  /// 서버·캐시 모두 비어 있으면 로컬 번들 seed를 사용한다.
  Future<List<PartnerRestaurant>> getAll({bool forceRefresh = false}) async {
    if (!forceRefresh && !_isCacheStale()) {
      final cached = _loadCache();
      if (cached.isNotEmpty) return cached;
    }
    final fresh = await _fetchFromServer();
    if (fresh.isNotEmpty) {
      await _saveCache(fresh);
      return fresh;
    }
    final seed = await _loadSeed();
    if (seed.isNotEmpty) {
      await _saveCache(seed);
      return seed;
    }
    // 서버 실패 시 캐시 반환 (오래됐어도)
    final cached = _loadCache();
    if (cached.isNotEmpty) return cached;
    // 캐시도 없으면 로컬 seed 사용
    return [];
  }

  /// 특정 사용자(단과대 코드, 학과 코드)에 해당하는 제휴 식당만 반환.
  Future<List<PartnerRestaurant>> getForUser({
    required String? collegeCode,
    required String? deptCode,
    bool forceRefresh = false,
  }) async {
    final all = await getAll(forceRefresh: forceRefresh);
    return all
        .where(
            (r) => r.matchesUser(collegeCode: collegeCode, deptCode: deptCode))
        .toList();
  }
}

// ─── Riverpod providers ────────────────────────────────────────────────────

final partnerRepositoryProvider = Provider<PartnerRepository>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return PartnerRepository(prefs);
});

/// 현재 사용자의 단과대/학과에 맞는 제휴 식당 목록 (AsyncValue).
final partnerRestaurantsProvider =
    FutureProvider.autoDispose<List<PartnerRestaurant>>((ref) async {
  final repo = ref.watch(partnerRepositoryProvider);
  final college = ref.watch(collegeCodeProvider);
  final dept = ref.watch(departmentCodeProvider);
  return repo.getForUser(collegeCode: college, deptCode: dept);
});

/// 강제 새로고침용 StateProvider — increment 시 partnerRestaurantsProvider 무효화.
final partnerRefreshCounterProvider = StateProvider<int>((ref) => 0);

/// 단과대 필터 없이 전체 제휴 매장 목록.
final partnerAllProvider =
    FutureProvider.autoDispose<List<PartnerRestaurant>>((ref) async {
  final repo = ref.watch(partnerRepositoryProvider);
  return repo.getAll();
});

/// 지도 마커 전용 — 만료 및 좌표 없는 매장 제외.
final partnerMapProvider =
    FutureProvider.autoDispose<List<PartnerRestaurant>>((ref) async {
  final all = await ref.watch(partnerAllProvider.future);
  return all.where((r) => !r.isExpired && r.lat != null && r.lng != null).toList();
});
