import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/providers/settings_provider.dart';
import '../domain/extra_program.dart';
import '../domain/notice.dart';

const _kSportsUrl =
    'https://sports.snu.ac.kr/category/board-185-GN-CsX1312K-20230828174851/';
const _kSportsCacheTtlSeconds = 3600; // 1시간
const _kSportsCacheKey = 'notices_sports_cache';
const _kSportsFetchedAtKey = 'notices_sports_fetched_at';

const _kExtraApiBase = 'https://extra.snu.ac.kr/ptfol/pgm/index.do';
const _kExtraCacheTtlSeconds = 1800; // 30분
const _kExtraCacheKey = 'notices_extra_cache';
const _kExtraFetchedAtKey = 'notices_extra_fetched_at';
const _kExtraMaxPages = 5;

class ScrapingException implements Exception {
  const ScrapingException(this.message);
  final String message;
  @override
  String toString() => 'ScrapingException: $message';
}

class NoticeRepository {
  NoticeRepository(this._prefs);

  final SharedPreferences _prefs;

  final _sportsDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));

  final _extraDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));

  // ─── 체육교육과 공지 ────────────────────────────────────────────────────────

  Future<List<Notice>> getSportsNotices({bool forceRefresh = false}) async {
    if (!forceRefresh && !_isCacheStale(_kSportsFetchedAtKey, _kSportsCacheTtlSeconds)) {
      final cached = _loadSportsCache();
      if (cached.isNotEmpty) return cached;
    }
    try {
      final fresh = await _fetchSportsNotices();
      await _saveSportsCache(fresh);
      return fresh;
    } catch (_) {
      final cached = _loadSportsCache();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  bool _isCacheStale(String key, int ttlSeconds) {
    final fetchedAt = _prefs.getString(key);
    if (fetchedAt == null) return true;
    final ts = DateTime.tryParse(fetchedAt);
    if (ts == null) return true;
    return DateTime.now().difference(ts).inSeconds >= ttlSeconds;
  }

  List<Notice> _loadSportsCache() {
    final raw = _prefs.getString(_kSportsCacheKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => _noticeFromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveSportsCache(List<Notice> notices) async {
    final json = jsonEncode(notices.map(_noticeToMap).toList());
    await _prefs.setString(_kSportsCacheKey, json);
    await _prefs.setString(_kSportsFetchedAtKey, DateTime.now().toIso8601String());
  }

  Future<List<Notice>> _fetchSportsNotices() async {
    final res = await _sportsDio.get(_kSportsUrl);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return _parseSportsHtml(res.data as String);
  }

  /// 체육교육과 WordPress 리스트 파싱
  /// 구조: div.board_type_list > ul.body > li
  ///   span.type = 카테고리, div.subject > a > strong = 제목, span.date = 날짜
  List<Notice> _parseSportsHtml(String raw) {
    final notices = <Notice>[];
    final doc = html_parser.parse(raw);
    final rows = doc.querySelectorAll('ul.body li');
    for (final row in rows) {
      final titleEl = row.querySelector('div.subject a strong') ??
          row.querySelector('div.subject a');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;

      final catText = row.querySelector('span.type')?.text.trim() ?? '';
      final category = catText.isEmpty ? null : catText;

      final dateText = row.querySelector('span.date')?.text.trim() ?? '';
      final date = DateTime.tryParse(dateText);

      // djb2 stable hash — Dart hashCode is not persistent across runs
      final id = 'sports_${_stableHash(title + dateText)}';

      notices.add(Notice(
        id: id,
        title: title,
        url: _kSportsUrl,
        source: NoticeSource.sports,
        category: category,
        date: date,
      ));
    }
    if (notices.isEmpty) {
      throw const ScrapingException(
          '공지 파싱 결과가 비어 있음 — 사이트 구조가 변경되었을 수 있습니다.');
    }
    return notices;
  }

  static int _stableHash(String s) {
    var h = 5381;
    for (final c in s.codeUnits) {
      h = ((h << 5) + h + c) & 0xFFFFFFFF;
    }
    return h;
  }

  // ─── JSON 직렬화 (sports) ──────────────────────────────────────────────────

  Map<String, dynamic> _noticeToMap(Notice n) => {
        'id': n.id,
        'title': n.title,
        'url': n.url,
        'source': n.source.name,
        'category': n.category,
        'status': n.status,
        'dDay': n.dDay,
        'date': n.date?.toIso8601String(),
        'description': n.description,
        'imageUrl': n.imageUrl,
      };

  Notice _noticeFromMap(Map<String, dynamic> m) => Notice(
        id: m['id'] as String,
        title: m['title'] as String,
        url: m['url'] as String,
        source: NoticeSource.values.firstWhere(
          (e) => e.name == m['source'],
          orElse: () => NoticeSource.sports,
        ),
        category: m['category'] as String?,
        status: m['status'] as String?,
        dDay: m['dDay'] as int?,
        date: m['date'] != null ? DateTime.tryParse(m['date'] as String) : null,
        description: m['description'] as String?,
        imageUrl: m['imageUrl'] as String?,
      );

  // ─── SNU 비교과 ────────────────────────────────────────────────────────────

  Future<List<ExtraProgram>> getExtraPrograms({bool forceRefresh = false}) async {
    // Use cache (even empty list) when fresh — empty result is valid data.
    if (!forceRefresh && !_isCacheStale(_kExtraFetchedAtKey, _kExtraCacheTtlSeconds)) {
      if (_prefs.containsKey(_kExtraCacheKey)) return _loadExtraCache();
    }
    try {
      final fresh = await _fetchExtraPrograms();
      await _saveExtraCache(fresh);
      return fresh;
    } catch (_) {
      // Fall back to cache (including empty) rather than surfacing an error.
      if (_prefs.containsKey(_kExtraCacheKey)) return _loadExtraCache();
      rethrow;
    }
  }

  List<ExtraProgram> _loadExtraCache() {
    final raw = _prefs.getString(_kExtraCacheKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ExtraProgram.fromCacheJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveExtraCache(List<ExtraProgram> list) async {
    final json = jsonEncode(list.map((p) => p.toJson()).toList());
    await _prefs.setString(_kExtraCacheKey, json);
    await _prefs.setString(_kExtraFetchedAtKey, DateTime.now().toIso8601String());
  }

  Future<List<ExtraProgram>> _fetchExtraPrograms() async {
    final now = DateTime.now();
    final result = <ExtraProgram>[];
    for (int page = 1; page <= _kExtraMaxPages; page++) {
      final res = await _extraDio.get<Map<String, dynamic>>(
        _kExtraApiBase,
        queryParameters: {'currentPageNo': page, 'sort': '0001'},
      );
      if (res.statusCode != 200) break;
      final data = res.data;
      if (data == null) break;
      final list = (data['result'] as Map<String, dynamic>?)?['list'] as List?;
      if (list == null || list.isEmpty) break;
      for (final item in list) {
        final p = ExtraProgram.fromJson(item as Map<String, dynamic>);
        if (shouldShowProgram(p, now)) result.add(p);
      }
      // Last page if fewer than 10 items returned
      if (list.length < 10) break;
    }
    return result;
  }
}

// ─── Riverpod providers ────────────────────────────────────────────────────

final noticeRepositoryProvider = Provider<NoticeRepository>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return NoticeRepository(prefs);
});

final sportsNoticesProvider =
    FutureProvider.autoDispose<List<Notice>>((ref) async {
  final repo = ref.watch(noticeRepositoryProvider);
  return repo.getSportsNotices();
});

final extraProgramsProvider =
    FutureProvider.autoDispose<List<ExtraProgram>>((ref) async {
  final repo = ref.watch(noticeRepositoryProvider);
  return repo.getExtraPrograms();
});
