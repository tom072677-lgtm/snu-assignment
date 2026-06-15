import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/club_repository.dart';
import '../domain/club.dart';

/// 동아리 목록 화면.
/// - 기본: 전체 노출(결정1-B). 가입 자격은 숨김이 아니라 표시 + 선택 필터.
/// - 활동 분야 6분류 칩 필터 + 가입자격 필터 + 이름/활동 검색.
class ClubListScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const ClubListScreen({super.key, this.embedded = false});

  @override
  ConsumerState<ClubListScreen> createState() => _ClubListScreenState();
}

class _ClubListScreenState extends ConsumerState<ClubListScreen> {
  String _category = '전체';
  String _tier = '전체'; // 전체 | 중앙 | 단과대 | 기숙사
  String _query = '';
  final _searchCtrl = TextEditingController();

  static const _categoryChips = ['전체', ...kClubCategories];
  // 라벨 → tier 값 매핑 ('전체'는 필터 없음).
  static const _tierChips = <String, String?>{
    '전체': null,
    '중앙': kTierCentral,
    '단과대': kTierCollege,
    '기숙사': kTierDorm,
  };

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(clubsProvider);

    final body = Column(
        children: [
          // 검색 바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: '동아리명, 활동 검색',
                hintStyle: const TextStyle(fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
              ),
            ),
          ),
          // 활동 분야 칩
          _ChipRow(
            items: _categoryChips,
            selected: _category,
            onTap: (c) => setState(() => _category = c),
          ),
          // 가입 자격 칩
          _ChipRow(
            items: _tierChips.keys.toList(),
            selected: _tier,
            onTap: (t) => setState(() => _tier = t),
          ),
          const Divider(height: 1),
          // 목록
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('불러오기 실패\n$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)),
              ),
              data: (list) {
                final tierVal = _tierChips[_tier];
                var filtered = list.where((c) {
                  if (_category != '전체' && c.category != _category) return false;
                  if (tierVal != null && c.tier != tierVal) return false;
                  if (_query.isNotEmpty) {
                    final q = _query.toLowerCase();
                    if (!c.name.toLowerCase().contains(q) &&
                        !c.activity.toLowerCase().contains(q)) {
                      return false;
                    }
                  }
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.groups_outlined,
                            size: 56, color: Color(0xFFCCCCCC)),
                        const SizedBox(height: 12),
                        Text(
                          list.isEmpty
                              ? '동아리 정보가 없습니다.\n앱 업데이트 후 다시 확인해주세요.'
                              : '조건에 맞는 동아리가 없습니다.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFF999999), fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: filtered.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('${filtered.length}개 동아리',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF999999))),
                      );
                    }
                    return _ClubCard(club: filtered[i - 1]);
                  },
                );
              },
            ),
          ),
        ],
      );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('동아리', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: body,
    );
  }
}

/// 가로 스크롤 칩 행 (분야/가입자격 공용).
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.items,
    required this.selected,
    required this.onTap,
  });
  final List<String> items;
  final String selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final item = items[i];
          final sel = selected == item;
          return GestureDetector(
            onTap: () => onTap(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFF1A73E8) : const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : const Color(0xFF555555),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.club});
  final Club club;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    club.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                // 활동 분야 뱃지
                _Badge(
                  text: club.category,
                  fg: const Color(0xFF1A73E8),
                  bg: const Color(0xFFEEF3FF),
                ),
              ],
            ),
            if (club.activity.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                club.activity,
                style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
              ),
            ],
            const SizedBox(height: 8),
            // 가입자격 + 등록 뱃지
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final label in club.eligibilityLabels)
                  _Badge(
                    text: label,
                    fg: const Color(0xFF2E7D32),
                    bg: const Color(0xFFE8F5E9),
                  ),
                if (club.registration == '가')
                  const _Badge(
                    text: '가등록',
                    fg: Color(0xFF9E9E9E),
                    bg: Color(0xFFF0F0F0),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.fg, required this.bg});
  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
