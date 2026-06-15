import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/scrap_entry.dart';

/// 스크랩 항목의 영속 저장(기기 로컬 전용, 서버 미전송).
class ScrapStore {
  static const _key = 'opp_scraps_v1';

  Future<List<ScrapEntry>> all() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => ScrapEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<ScrapEntry> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<bool> isScrapped(String id) async =>
      (await all()).any((e) => e.id == id);

  Future<void> add(ScrapEntry e) async {
    final list = await all();
    if (list.any((x) => x.id == e.id)) return;
    list.add(e);
    await _save(list);
  }

  Future<void> remove(String id) async {
    final list = await all()..removeWhere((e) => e.id == id);
    await _save(list);
  }

  Future<void> setStatus(String id, ScrapStatus s) async {
    final list = await all();
    final i = list.indexWhere((e) => e.id == id);
    if (i == -1) return;
    list[i] = list[i].copyWith(status: s);
    await _save(list);
  }
}
