import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/opportunity.dart';
import '../domain/opportunity_query.dart';
import '../domain/pitfall_content.dart';
import 'opportunities_providers.dart';
import 'opportunity_card.dart';
import 'opportunity_detail_page.dart';
import 'my_scraps_page.dart';

class OpportunitiesPage extends ConsumerWidget {
  final bool embedded;
  const OpportunitiesPage({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAll = ref.watch(allOpportunitiesProvider);
    final asyncPrefs = ref.watch(userPrefsProvider);
    final cat = ref.watch(selectedCategoryProvider);
    final scraps = ref.watch(scrapsProvider);

    final body = Column(children: [
        _CategoryChips(
            selected: cat,
            onSelect: (c) =>
                ref.read(selectedCategoryProvider.notifier).state = c),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: '제목·주최·태그 검색',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                ref.read(searchQueryProvider.notifier).state = v,
          ),
        ),
        if (cat != null && kPitfalls[cat] != null)
          _PitfallBanner(pitfall: kPitfalls[cat]!.first),
        Expanded(
          child: asyncAll.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) {
              debugPrint('opportunities 로드 실패: $e');
              return Center(
                  child: Text('불러오지 못했어요\n$e', textAlign: TextAlign.center));
            },
            data: (all) {
              final prefs = asyncPrefs.asData?.value;
              final list = OpportunityQuery.process(
                all,
                now: DateTime.now(),
                category: cat,
                interests: prefs?.interests ?? const {},
                region: prefs?.region,
                query: ref.watch(searchQueryProvider),
              );
              if (list.isEmpty) {
                return const Center(child: Text('해당 조건의 기회가 없어요'));
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(allOpportunitiesProvider),
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final o = list[i];
                    final scrapped = scraps.any((e) => e.id == o.id);
                    return OpportunityCard(
                      opp: o,
                      scrapped: scrapped,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  OpportunityDetailPage(opp: o))),
                      onToggleScrap: () => toggleScrapWithNotif(ref, o),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]);
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('혜택·기회'), actions: [
        IconButton(
          icon: const Icon(Icons.star),
          tooltip: '내 스크랩',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MyScrapsPage())),
        ),
      ]),
      body: body,
    );
  }
}

class _CategoryChips extends StatelessWidget {
  final OppCategory? selected;
  final ValueChanged<OppCategory?> onSelect;
  const _CategoryChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final items = <(String, OppCategory?)>[
      ('전체', null),
      for (final c in OppCategory.values) (categoryLabel(c), c),
    ];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
              child: ChoiceChip(
                label: Text(it.$1),
                selected: selected == it.$2,
                onSelected: (_) => onSelect(it.$2),
              ),
            ),
        ],
      ),
    );
  }
}

class _PitfallBanner extends StatelessWidget {
  final Pitfall pitfall;
  const _PitfallBanner({required this.pitfall});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: Text('⚠️ ${pitfall.title} — ${pitfall.body}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF9A5B00))),
    );
  }
}
