import 'opportunity.dart';

/// 마감 지난 항목 제거 → (관심 매칭 우선) → 마감 임박순.
/// 마감일 없는 항목은 맨 뒤. region 필터는 전국(null) 항목을 항상 노출.
class OpportunityQuery {
  static List<Opportunity> process(
    List<Opportunity> items, {
    required DateTime now,
    Set<OppCategory> categories = const {},
    Set<String> interests = const {},
    String? region,
    String? query,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final list = items.where((o) {
      // 오늘 마감은 유지(D-day), 어제 이전만 제거.
      if (o.deadline != null && o.deadline!.isBefore(today)) return false;
      // 카테고리 복수 선택: 비어 있으면 전체, 아니면 선택된 것만.
      if (categories.isNotEmpty && !categories.contains(o.category)) return false;
      // region 필터: 지역 지정 항목이 내 지역과 다르면 제외. 전국(null)은 항상 노출.
      if (region != null && region.isNotEmpty && o.region != null && o.region != region) {
        return false;
      }
      if (query != null && query.trim().isNotEmpty) {
        final q = query.toLowerCase();
        final hay =
            '${o.title} ${o.organization} ${o.tags.join(" ")}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    bool matchesInterest(Opportunity o) =>
        interests.isNotEmpty && o.tags.any(interests.contains);

    list.sort((a, b) {
      final ai = matchesInterest(a), bi = matchesInterest(b);
      if (ai != bi) return ai ? -1 : 1; // 관심 매칭 우선
      if (a.deadline == null && b.deadline == null) return 0;
      if (a.deadline == null) return 1; // 마감 없는 건 뒤로
      if (b.deadline == null) return -1;
      return a.deadline!.compareTo(b.deadline!); // 임박순
    });
    return list;
  }

  static int? daysLeft(Opportunity o, DateTime now) {
    if (o.deadline == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return o.deadline!.difference(today).inDays;
  }
}
