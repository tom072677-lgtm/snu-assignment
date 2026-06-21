import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/opportunity.dart';
import '../domain/pitfall_content.dart';
import 'opportunities_providers.dart';

class OpportunityDetailPage extends ConsumerWidget {
  final Opportunity opp;
  const OpportunityDetailPage({super.key, required this.opp});

  Future<void> _openUrl(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(opp.url);
    if (uri == null || opp.url.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('열 수 있는 링크가 없어요')));
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(const SnackBar(content: Text('링크를 열지 못했어요')));
      }
    } catch (e) {
      debugPrint('opportunity launchUrl 실패: $e');
      messenger.showSnackBar(const SnackBar(content: Text('링크를 열지 못했어요')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrapped = ref.watch(scrapsProvider).any((e) => e.id == opp.id);
    final pitfalls = kPitfalls[opp.category] ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(categoryLabel(opp.category)), actions: [
        IconButton(
          icon: Icon(scrapped ? Icons.star : Icons.star_border,
              color: scrapped ? const Color(0xFFFFB400) : null),
          onPressed: () => toggleScrapWithNotif(ref, opp),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(opp.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(opp.organization, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        for (final e in opp.extra.entries) _row(_extraLabel(e.key), e.value),
        if (opp.deadline != null)
          _row('마감',
              '${opp.deadline!.year}.${opp.deadline!.month}.${opp.deadline!.day}'),
        if (opp.region != null) _row('지역', opp.region!),
        if (opp.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(spacing: 6, children: [
              for (final t in opp.tags) Chip(label: Text(t)),
            ]),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _openUrl(context),
          icon: const Icon(Icons.open_in_new),
          label: const Text('원문 보기'),
        ),
        if (pitfalls.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('⚠️ 신청 전 확인하세요',
              style: TextStyle(fontWeight: FontWeight.w800)),
          for (final p in pitfalls)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('• ${p.title}\n  ${p.body}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF9A5B00))),
            ),
        ],
      ]),
    );
  }

  // extra 키(영문)를 한글 라벨로. 전 카테고리(장학·교육·공모전·청년정책) 공용.
  static String _extraLabel(String key) =>
      const {
        'support': '지원내용',
        'amount': '지원금액',
        'prize': '시상',
        'cost': '비용',
        'capacity': '정원',
        'grade': '성적기준',
        'eligibility': '소득기준',
        'restriction': '자격제한',
        'univType': '대학구분',
        'residency': '거주요건',
        'target': '대상',
        'period': '기간',
        'field': '분야',
        'status': '상태',
        'dday': 'D-day',
        'applyPeriod': '신청기간',
        'ageMin': '최소연령',
        'ageMax': '최대연령',
      }[key] ??
      key;

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 84,
              child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(
              child: Text(v,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
