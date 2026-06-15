import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../domain/opportunity.dart';

/// ⚠️ 격리 모듈 — 공모전 온디바이스 스크래핑(위비티).
/// 위비티가 클라우드(Render) IP를 403으로 막아서, 폰의 국내 IP로 직접 받는다.
/// (sharap의 인류학과 공지 client-side scrape와 같은 패턴)
/// 공개 배포 전에는 제거하거나 합법 소스로 교체할 것.
///
/// 한계: 목록은 상대 D-day(D-45)만 제공 → deadline = 오늘+N일 근사.
class ContestScraper {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120 Mobile Safari/537.36';

  Future<List<Opportunity>> fetch() async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': _ua,
        'Accept-Language': 'ko-KR,ko;q=0.9',
        'Referer': 'https://www.wevity.com/',
      },
    ));

    final res = await dio.get('https://www.wevity.com/?c=find&s=1');
    final doc = html_parser.parse(res.data as String);
    final lis = doc.querySelectorAll('ul.list > li');
    final now = DateTime.now();
    final out = <Opportunity>[];

    for (final li in lis) {
      if (li.classes.contains('top')) continue;
      final a = li.querySelector('.tit a');
      if (a == null) continue;

      // 직접 텍스트 노드만 → SPECIAL 같은 배지(span) 제외
      final title = a.nodes
          .whereType<dom.Text>()
          .map((n) => n.text)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final href = (a.attributes['href'] ?? '').trim();
      if (title.isEmpty || href.isEmpty) continue;

      final link = 'https://www.wevity.com/${href.replaceFirst(RegExp(r'^/'), '')}';
      final field = (li.querySelector('.sub-tit')?.text ?? '')
          .replaceFirst(RegExp(r'^\s*분야\s*:\s*'), '')
          .trim();
      final organ =
          (li.querySelector('.organ')?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final dayText =
          (li.querySelector('.day')?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

      DateTime? deadline;
      final m = RegExp(r'D-(\d+)').firstMatch(dayText);
      if (m != null) {
        deadline = DateTime(now.year, now.month, now.day)
            .add(Duration(days: int.parse(m.group(1)!)));
      }
      final status = dayText.contains('접수예정')
          ? '접수예정'
          : (RegExp(r'마감|D-?day', caseSensitive: false).hasMatch(dayText)
              ? '마감임박'
              : '접수중');
      final ix = RegExp(r'ix=(\d+)').firstMatch(href)?.group(1);

      out.add(Opportunity(
        id: 'con_${ix ?? title.hashCode}',
        category: OppCategory.contest,
        title: title,
        organization: organ.isEmpty ? '주최 미상' : organ,
        url: link,
        source: '위비티',
        deadline: deadline,
        tags: field.isEmpty
            ? const []
            : field.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).take(4).toList(),
        extra: {
          if (field.isNotEmpty) 'field': field,
          'status': status,
          if (m != null) 'dday': 'D-${m.group(1)}',
        },
      ));
    }

    if (out.isEmpty) {
      // 빈 결과 = 구조 변경 가능. 조용히 삼키지 않고 로그 남김(rule 13).
      debugPrint('[ContestScraper] 위비티 0건 파싱 — 구조 변경 가능. '
          'HTML앞부분: ${(res.data as String).substring(0, 300).replaceAll(RegExp(r"\s+"), " ")}');
    }
    return out;
  }
}
