import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/club.dart';

/// 번들 seed 경로. (서버 fetch는 MVP 범위 밖 — 추후 /api/clubs)
const String _kClubsSeedAsset = 'assets/data/clubs.json';

class ClubRepository {
  /// 앱 번들의 동아리 seed를 읽어 목록으로 반환.
  /// 실패 시 빈 목록 + 실제 예외 로그(규칙11).
  Future<List<Club>> loadAll() async {
    try {
      final raw = await rootBundle.loadString(_kClubsSeedAsset);
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Club.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ClubRepository.loadAll] error: $e');
      return [];
    }
  }
}

final clubRepositoryProvider = Provider<ClubRepository>((ref) {
  return ClubRepository();
});

/// 전체 동아리 목록.
final clubsProvider = FutureProvider<List<Club>>((ref) {
  return ref.watch(clubRepositoryProvider).loadAll();
});
