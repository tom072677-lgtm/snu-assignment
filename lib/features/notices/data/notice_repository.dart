import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/providers/settings_provider.dart';
import '../domain/notice.dart';

const _kSportsUrl =
    'https://sports.snu.ac.kr/category/board-185-GN-CsX1312K-20230828174851/';
const _kCacheTtlSeconds = 3600; // 1시간
const _kSportsCacheKey = 'notices_sports_cache';
const _kSportsFetchedAtKey = 'notices_sports_fetched_at';

class ScrapingException implements Exception {
  const ScrapingException(this.message);
  final String message;
  @override
  String toString() => 'ScrapingException: $message';
}

class NoticeRepository {
  NoticeRepository(this._prefs);

  final SharedPreferences _prefs;
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));

  // ─── 체육교육과 공지 ────────────────────────────────────────────────────────

  Future<List<Notice>> getSportsNotices({bool forceRefresh = false}) async {
    if (!forceRefresh && !_isSportsCacheStale()) {
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

  bool _isSportsCacheStale() {
    final fetchedAt = _prefs.getString(_kSportsFetchedAtKey);
    if (fetchedAt == null) return true;
    final ts = DateTime.tryParse(fetchedAt);
    if (ts == null) return true;
    return DateTime.now().difference(ts).inSeconds >= _kCacheTtlSeconds;
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
    final res = await _dio.get(_kSportsUrl);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return _parseSportsHtml(res.data as String);
  }

  /// 체육교육과 WordPress 테이블 파싱
  /// 구조: table > tbody > tr
  ///   td[0] = 번호, td[1] = 카테고리, td[2] = 제목(a 링크), td[3] = 작성자,
  ///   td[4] = 조회수, td[5] = 날짜
  List<Notice> _parseSportsHtml(String raw) {
    final notices = <Notice>[];
    final doc = html_parser.parse(raw);
    final rows = doc.querySelectorAll('table tbody tr');
    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 3) continue;

      final titleCell = cells.firstWhere(
        (td) => td.querySelector('a') != null,
        orElse: () => cells[2],
      );
      final anchor = titleCell.querySelector('a');
      if (anchor == null) continue;

      final title = anchor.text.trim();
      if (title.isEmpty) continue;

      final href = anchor.attributes['href'] ?? '';
      final url = href.startsWith('http') ? href : 'https://sports.snu.ac.kr$href';

      String? category;
      if (cells.length > 1) {
        final catText = cells[1].text.trim();
        if (catText.isNotEmpty && !RegExp(r'^\d+$').hasMatch(catText)) {
          category = catText;
        }
      }

      DateTime? date;
      final dateText = cells.last.text.trim();
      if (RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(dateText)) {
        date = DateTime.tryParse(dateText);
      }

      final id = url.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').isNotEmpty
          ? url.hashCode.toString()
          : title.hashCode.toString();

      notices.add(Notice(
        id: 'sports_$id',
        title: title,
        url: url,
        source: NoticeSource.sports,
        category: category,
        date: date,
      ));
    }
    if (notices.isEmpty) {
      throw const ScrapingException('공지 파싱 결과가 비어 있음 — 사이트 구조가 변경되었을 수 있습니다.');
    }
    return notices;
  }

  // ─── JSON 직렬화 ───────────────────────────────────────────────────────────

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

/// 비교과는 WebView 임베드 방식이므로 URL만 제공
const kExtraProgramsUrl = 'https://extra.snu.ac.kr/ptfol/pgm/index.do?currentPageNo=1&sort=0001';
