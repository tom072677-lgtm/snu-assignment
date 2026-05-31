import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/partner_repository.dart';
import '../domain/partner_restaurant.dart';
import '../../../shared/providers/settings_provider.dart';

/// 제휴 식당 목록 화면.
/// - 카테고리 필터 (전체 / 음식점 / 카페 / 편의점 / 기타)
/// - 하루 1회 자동 갱신, 수동 새로고침 지원
class PartnerListScreen extends ConsumerStatefulWidget {
  const PartnerListScreen({super.key});

  @override
  ConsumerState<PartnerListScreen> createState() => _PartnerListScreenState();
}

class _PartnerListScreenState extends ConsumerState<PartnerListScreen> {
  String _selectedCategory = '전체';
  bool _showExpired = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  static const _categories = ['전체', '음식점', '카페', '편의점', '기타'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final repo = ref.read(partnerRepositoryProvider);
    await repo.getAll(forceRefresh: true);
    ref.invalidate(partnerRestaurantsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(partnerRestaurantsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('제휴 매장', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          // 검색 바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: '매장명, 주소, 혜택 검색',
                hintStyle: const TextStyle(fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
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
          // 카테고리 칩 필터
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final selected = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF1A73E8) : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : const Color(0xFF555555),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 만료 혜택 토글
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text('만료된 혜택 보기',
                    style:
                        TextStyle(fontSize: 12, color: Color(0xFF888888))),
                const Spacer(),
                Switch(
                  value: _showExpired,
                  onChanged: (v) => setState(() => _showExpired = v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 목록
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('불러오기 실패\n$e',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _refresh,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
              data: (list) {
                final favIds = ref.watch(favPartnersProvider);
                var filtered = _selectedCategory == '전체'
                    ? list
                    : list.where((r) => r.category == _selectedCategory).toList();
                if (!_showExpired) {
                  filtered = filtered.where((r) => !r.isExpired).toList();
                }
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  filtered = filtered.where((r) =>
                      r.name.toLowerCase().contains(q) ||
                      r.address.toLowerCase().contains(q) ||
                      r.benefit.toLowerCase().contains(q)).toList();
                }
                // 즐겨찾기 항목 최상단 고정 (기존 순서 유지)
                filtered = [
                  ...filtered.where((r) => favIds.contains(r.id)),
                  ...filtered.where((r) => !favIds.contains(r.id)),
                ];

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.storefront_outlined,
                            size: 56, color: Color(0xFFCCCCCC)),
                        const SizedBox(height: 12),
                        Text(
                          list.isEmpty
                              ? '제휴 매장 정보가 없습니다.\n앱 업데이트 후 다시 확인해주세요.'
                              : '해당 카테고리의 제휴 매장이 없습니다.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF999999), fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _PartnerCard(restaurant: filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerCard extends ConsumerWidget {
  const _PartnerCard({required this.restaurant});
  final PartnerRestaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(favPartnersProvider).contains(restaurant.id);
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
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 이미지 또는 플레이스홀더
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: restaurant.imageUrl != null
                  ? Image.network(
                      restaurant.imageUrl!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 이름 + D-day 배지 + 카테고리 + 즐겨찾기
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => ref
                            .read(favPartnersProvider.notifier)
                            .toggle(restaurant.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            isFav ? Icons.favorite : Icons.favorite_border,
                            color: isFav ? Colors.red : Colors.grey[400],
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // D-day 배지 (7일 이내 만료)
                      if (() {
                        final d = restaurant.daysUntilExpiry;
                        return d != null && d >= 0 && d <= 7;
                      }())
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'D-${restaurant.daysUntilExpiry}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: restaurant.isExpired
                              ? Colors.grey[200]
                              : const Color(0xFFEEF3FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          restaurant.category,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: restaurant.isExpired
                                ? Colors.grey
                                : const Color(0xFF1A73E8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 주소
                  if (restaurant.address.isNotEmpty)
                    Text(
                      restaurant.address,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  // 혜택 배너
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFE082)),
                    ),
                    child: Row(
                      children: [
                        const Text('🎁', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            restaurant.benefit,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF5D4037),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 쿠폰코드
                  if (restaurant.couponCode?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    _CouponCodeRow(code: restaurant.couponCode!),
                  ],
                  // 전화번호
                  if (restaurant.phone != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined, size: 13, color: Color(0xFFAAAAAA)),
                        const SizedBox(width: 4),
                        Text(
                          restaurant.phone!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 64,
      height: 64,
      color: const Color(0xFFF0F0F0),
      child: const Icon(Icons.storefront_outlined, color: Color(0xFFCCCCCC), size: 30),
    );
  }
}

/// 쿠폰코드 표시 + 복사 버튼 공통 위젯.
class _CouponCodeRow extends StatelessWidget {
  final String code;
  const _CouponCodeRow({required this.code});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('쿠폰코드가 복사됐어요'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF81C784)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.confirmation_num_outlined,
                size: 13, color: Color(0xFF388E3C)),
            const SizedBox(width: 5),
            Text('코드: $code',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF388E3C))),
            const SizedBox(width: 8),
            const Icon(Icons.copy, size: 12, color: Color(0xFF388E3C)),
          ],
        ),
      ),
    );
  }
}
