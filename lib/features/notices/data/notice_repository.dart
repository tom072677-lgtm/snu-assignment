import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../../../shared/providers/settings_provider.dart';
import '../domain/department_notice_source.dart';
import '../domain/extra_program.dart';
import '../domain/notice.dart';

const _kSportsUrl =
    'https://sports.snu.ac.kr/category/board-185-GN-CsX1312K-20230828174851/';
const _kSportsCacheTtlSeconds = 3600; // 1시간
const _kSportsCacheKey = 'notices_sports_cache';
const _kSportsFetchedAtKey = 'notices_sports_fetched_at';

const _kDeptCacheTtlSeconds = 3600; // 1시간
const _kDeptFeedMaxItems = 50;

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
    } catch (e) {
      debugPrint('[NoticeRepository._loadSportsCache] error: $e');
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

  // ─── 학과별 공지 (RSS/Atom 피드) ───────────────────────────────────────────

  /// 사용자 학과(deptCode)의 공지 피드를 가져온다.
  /// 소스 없음/RSS 없음이면 빈 리스트 반환(UI에서 분기). 1시간 캐시 + 오프라인 fallback.
  Future<List<Notice>> getDepartmentNotices(String? deptCode,
      {bool forceRefresh = false}) async {
    final feedUrl = noticeSourceFor(deptCode)?.rssFeedUrl;
    if (deptCode == null || feedUrl == null) return [];

    final cacheKey = 'notices_dept_${deptCode}_cache';
    final fetchedKey = 'notices_dept_${deptCode}_at';

    if (!forceRefresh && !_isCacheStale(fetchedKey, _kDeptCacheTtlSeconds)) {
      final cached = _loadDeptCache(cacheKey);
      if (cached.isNotEmpty) return cached;
    }
    try {
      final res = await _sportsDio.get<String>(
        feedUrl,
        options: Options(responseType: ResponseType.plain),
      );
      if (res.statusCode != 200 || res.data == null || res.data!.isEmpty) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final list = parseFeed(res.data!, deptCode: deptCode);
      await _saveDeptCache(cacheKey, fetchedKey, list);
      return list;
    } catch (e) {
      debugPrint('[NoticeRepository.getDepartmentNotices] $deptCode error: $e');
      final cached = _loadDeptCache(cacheKey);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  List<Notice> _loadDeptCache(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => _noticeFromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[NoticeRepository._loadDeptCache] error: $e');
      return [];
    }
  }

  Future<void> _saveDeptCache(
      String cacheKey, String fetchedKey, List<Notice> notices) async {
    await _prefs.setString(
        cacheKey, jsonEncode(notices.map(_noticeToMap).toList()));
    await _prefs.setString(fetchedKey, DateTime.now().toIso8601String());
  }

  /// RSS 또는 Atom 피드를 파싱해 Notice 목록으로 변환 (순수 함수).
  /// 날짜 내림차순 정렬, 날짜 없는 항목은 뒤로(피드 순서 유지).
  static List<Notice> parseFeed(String xmlStr,
      {required String deptCode, int limit = _kDeptFeedMaxItems}) {
    final doc = XmlDocument.parse(xmlStr);
    var nodes = doc.findAllElements('item').toList();
    final isAtom = nodes.isEmpty;
    if (isAtom) nodes = doc.findAllElements('entry').toList();

    final out = <Notice>[];
    final seen = <String>{};
    for (final n in nodes) {
      final title = _feedText(n, 'title');
      final link = isAtom ? _atomLink(n) : _feedText(n, 'link');
      if (title.isEmpty || link.isEmpty) continue;
      final norm = _normalizeLink(link);
      if (!seen.add(norm)) continue;

      final dateStr = _firstNonEmpty([
        _feedText(n, 'pubDate'),
        _feedText(n, 'dc:date'),
        _feedText(n, 'updated'),
        _feedText(n, 'published'),
      ]);

      out.add(Notice(
        id: 'dept_${deptCode}_${_stableHash(norm)}',
        title: title,
        url: link,
        source: NoticeSource.sports,
        category: _bracketCategory(title),
        date: parseFeedDate(dateStr),
      ));
      if (out.length >= limit) break;
    }

    final dated = out.where((n) => n.date != null).toList()
      ..sort((a, b) => b.date!.compareTo(a.date!));
    final undated = out.where((n) => n.date == null).toList();
    return [...dated, ...undated];
  }

  static String _feedText(XmlElement n, String tag) =>
      n.getElement(tag)?.innerText.trim() ?? '';

  static String _atomLink(XmlElement entry) {
    for (final l in entry.findElements('link')) {
      final href = l.getAttribute('href');
      if (href != null && href.isNotEmpty) return href.trim();
    }
    return _feedText(entry, 'link');
  }

  static String _firstNonEmpty(List<String> xs) =>
      xs.firstWhere((s) => s.isNotEmpty, orElse: () => '');

  /// 제목 앞 "[학생]","[장학]" 같은 접두사를 카테고리로 추출.
  static String? _bracketCategory(String title) {
    final m = RegExp(r'^\s*\[([^\]]{1,12})\]').firstMatch(title);
    return m?.group(1)?.trim();
  }

  /// 중복 판정용 링크 정규화 (scheme/query/fragment 무시, host 소문자, trailing slash 제거).
  static String _normalizeLink(String url) {
    try {
      final u = Uri.parse(url.trim());
      final path = u.path.replaceAll(RegExp(r'/+$'), '');
      return '${u.host}$path'.toLowerCase();
    } catch (_) {
      return url.trim().toLowerCase();
    }
  }

  /// RFC822(pubDate) 및 ISO8601(dc:date/updated/published) 모두 파싱. 실패 시 null.
  static DateTime? parseFeedDate(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    final iso = DateTime.tryParse(t);
    if (iso != null) return iso.toLocal();
    final m = RegExp(
            r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?')
        .firstMatch(t);
    if (m == null) return null;
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final mo = months[m.group(2)!.toLowerCase()];
    if (mo == null) return null;
    return DateTime(
      int.parse(m.group(3)!),
      mo,
      int.parse(m.group(1)!),
      int.parse(m.group(4) ?? '0'),
      int.parse(m.group(5) ?? '0'),
      int.parse(m.group(6) ?? '0'),
    );
  }

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
    } catch (e) {
      debugPrint('[NoticeRepository._loadExtraCache] error: $e');
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
      final res = await _extraDio.get<String>(
        _kExtraApiBase,
        queryParameters: {'currentPageNo': page, 'sort': '0001'},
        options: Options(responseType: ResponseType.plain),
      );
      if (res.statusCode != 200) break;
      final html = res.data;
      if (html == null || html.isEmpty) break;
      final programs = parseExtraHtml(html);
      if (programs.isEmpty) break;
      for (final p in programs) {
        if (shouldShowProgram(p, now)) result.add(p);
      }
      if (programs.length < 10) break;
    }
    return result;
  }

  static List<ExtraProgram> parseExtraHtml(String raw) {
    final doc = html_parser.parse(raw);
    final items = doc.querySelectorAll('div.lica_wrap ul li');
    final programs = <ExtraProgram>[];
    for (final item in items) {
      if (item.querySelector('div.lica_gp') == null) continue;

      final title = item.querySelector('a.tit')?.text.trim() ?? '';
      if (title.isEmpty) continue;

      // pgmSeq from data-params attribute
      final dataParams =
          item.querySelector('[data-params]')?.attributes['data-params'] ?? '';
      final seqMatch =
          RegExp(r'"pgmSeq"\s*:\s*"(\d+)"').firstMatch(dataParams);
      final seq = seqMatch?.group(1) ?? '';

      final status = item.querySelector('.btn01 span')?.text.trim() ?? '';

      final majorType = item.querySelectorAll('ul.major_type li');
      final organizer =
          majorType.isNotEmpty ? majorType[0].text.trim() : null;
      final category = majorType.length > 1
          ? majorType[1].text.trim()
          : (organizer ?? '기타');

      final aplRange =
          parseDateRange(item.querySelector('dl.apl_date dd')?.text.trim());
      final eduRange =
          parseDateRange(item.querySelector('dl.edu_date dd')?.text.trim());
      final mode = item.querySelector('dl.class_cd dd')?.text.trim();

      final ddayText = item.querySelector('.dday')?.text.trim() ?? '';
      final ddayMatch = RegExp(r'D-(\d+)').firstMatch(ddayText);
      final dday =
          ddayMatch != null ? int.tryParse(ddayMatch.group(1) ?? '') : null;

      final targetOrg =
          item.querySelector('dl.org_name dd')?.text.trim() ?? '';
      final targetStatus = item
          .querySelectorAll('dl.user_cd dd div.cdDiv')
          .map((e) => e.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      programs.add(ExtraProgram(
        seq: seq,
        name: title,
        category: category,
        status: status,
        aplFrom: aplRange?.$1,
        aplTo: aplRange?.$2,
        eduFrom: eduRange?.$1,
        eduTo: eduRange?.$2,
        organizer: organizer,
        mode: mode,
        dday: dday,
        targetOrg: targetOrg,
        targetStatus: targetStatus,
      ));
    }
    return programs;
  }

  static (DateTime, DateTime)? parseDateRange(String? text) {
    if (text == null || text.isEmpty) return null;
    final parts = text.split('~');
    if (parts.length < 2) return null;
    final from = parseHtmlDate(parts[0].trim());
    final to = parseHtmlDate(parts[1].trim());
    if (from == null || to == null) return null;
    return (from, to);
  }

  static DateTime? parseHtmlDate(String s) {
    // "2026.06.01." or "2026.06.15. 09:00" → "2026-06-01"
    final datePart = s.split(' ')[0];
    final cleaned = datePart.replaceAll(RegExp(r'\.$'), '').replaceAll('.', '-');
    return DateTime.tryParse(cleaned);
  }

  /// 제목에서 마감일을 추출한다.
  /// 지원 패턴: ~YYYY.MM.DD / ~MM.DD / MM월 DD일까지 / MM.DD까지
  /// 연도 없는 패턴은 now.year 기준으로 해석한다.
  static DateTime? extractDeadline(String title, DateTime now) {
    // ~YYYY.MM.DD
    var m = RegExp(r'~(\d{4})[./](\d{1,2})[./](\d{1,2})').firstMatch(title);
    if (m != null) {
      return DateTime.tryParse(
        '${m[1]!}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}',
      );
    }

    // ~MM.DD (연도 없음)
    m = RegExp(r'~(\d{1,2})[./](\d{1,2})').firstMatch(title);
    if (m != null) {
      final month = int.tryParse(m[1]!) ?? 0;
      final day   = int.tryParse(m[2]!) ?? 0;
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      return DateTime(now.year, month, day);
    }

    // MM월 DD일까지
    m = RegExp(r'(\d{1,2})월\s*(\d{1,2})일\s*까지').firstMatch(title);
    if (m != null) {
      final month = int.tryParse(m[1]!) ?? 0;
      final day   = int.tryParse(m[2]!) ?? 0;
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      return DateTime(now.year, month, day);
    }

    // MM.DD까지
    m = RegExp(r'(\d{1,2})[./](\d{1,2})\s*까지').firstMatch(title);
    if (m != null) {
      final month = int.tryParse(m[1]!) ?? 0;
      final day   = int.tryParse(m[2]!) ?? 0;
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      return DateTime(now.year, month, day);
    }

    return null;
  }
}

// ─── 체육교육과 공지 노출 판단 ────────────────────────────────────────────────

/// 체육교육과 공지를 현재 기준으로 보여줄지 판단한다.
/// - 제목에서 마감일 추출 가능 → 마감일이 오늘 이후면 표시
/// - 마감일 없음 → 게시일 기준 90일 이내면 표시
/// - 날짜 정보 없음 → 항상 표시
bool shouldShowSportsNotice(Notice notice, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);

  final deadline = NoticeRepository.extractDeadline(notice.title, now);
  if (deadline != null) return !deadline.isBefore(today);

  if (notice.date != null) {
    final postDate =
        DateTime(notice.date!.year, notice.date!.month, notice.date!.day);
    return today.difference(postDate).inDays <= 90;
  }

  return true;
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

/// 사용자 학과(deptCode) 기반 공지 피드.
/// deptCode가 바뀌면 자동 rebuild(autoDispose)되어 항상 현재 학과 결과만 반환.
final departmentNoticesProvider =
    FutureProvider.autoDispose<List<Notice>>((ref) async {
  final deptCode = ref.watch(departmentCodeProvider);
  final repo = ref.watch(noticeRepositoryProvider);
  return repo.getDepartmentNotices(deptCode);
});

final extraProgramsProvider =
    FutureProvider.autoDispose<List<ExtraProgram>>((ref) async {
  final repo = ref.watch(noticeRepositoryProvider);
  return repo.getExtraPrograms();
});
