import 'package:flutter/material.dart';
import '../domain/opportunity.dart';
import '../domain/opportunity_query.dart';

/// 컴팩트 카드(레이아웃 A). dumb 위젯 — 스크랩 상태는 부모가 주입.
class OpportunityCard extends StatelessWidget {
  final Opportunity opp;
  final bool scrapped;
  final VoidCallback onTap;
  final VoidCallback onToggleScrap;

  const OpportunityCard({
    super.key,
    required this.opp,
    required this.scrapped,
    required this.onTap,
    required this.onToggleScrap,
  });

  Color _catColor() {
    switch (opp.category) {
      case OppCategory.scholarship:
        return const Color(0xFF1A8F3C);
      case OppCategory.education:
        return const Color(0xFF7B3FF2);
      case OppCategory.intern:
        return const Color(0xFFE08600);
      case OppCategory.contest:
      case OppCategory.activity:
        return const Color(0xFF1C5FD6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = OpportunityQuery.daysLeft(opp, DateTime.now());
    final benefit = opp.extra['prize'] ??
        opp.extra['amount'] ??
        opp.extra['cost'] ??
        opp.extra['pay'];
    final color = _catColor();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(categoryLabel(opp.category),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
                const Spacer(),
                if (d != null)
                  Text(d <= 0 ? 'D-day' : 'D-$d',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: d <= 3
                              ? const Color(0xFFE5484D)
                              : Colors.grey)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: Text(opp.title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700))),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(scrapped ? Icons.star : Icons.star_border,
                      color: scrapped
                          ? const Color(0xFFFFB400)
                          : Colors.grey),
                  onPressed: onToggleScrap,
                ),
              ]),
              Text(
                  '${opp.organization}${opp.extra['target'] != null ? " · ${opp.extra['target']}" : ""}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (benefit != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(benefit,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1A8F3C),
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
