import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/analytics.dart';
import '../../../shared/providers/settings_provider.dart';
import '../data/venue_repository.dart';
import '../domain/venue.dart';
import 'venue_detail_screen.dart';
import '../../partner/data/partner_repository.dart';
import '../../partner/domain/partner_restaurant.dart';

// ── 상황 태그 (필터용) ─────────────────────────────────────────────
const _situationTags = ['가성비', '데이트', '혼밥', '술자리', '24시간', '학식'];

class RestaurantScreen extends ConsumerStatefulWidget {
  const RestaurantScreen({super.key});

  @override
  ConsumerState<RestaurantScreen> createState() => _RestaurantScreenState();
}

class _RestaurantScreenState extends ConsumerState<RestaurantScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // 필터 상태
  String? _selectedCategory; // null = 전체
  final Set<String> _selectedTags = {};
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  bool _isPartnerMode = false;

  static const _areas = ['전체', '교내', '서울대입구', '대학동'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _areas.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String? get _currentArea {
    final idx = _tabController.index;
    return idx == 0 ? null : _areas[idx];
  }

  List<Venue> _filter(List<Venue> all) {
    return all.where((v) {
      if (_currentArea != null && v.area != _currentArea) return false;
      if (_selectedCategory != null &&
          v.category.name != _selectedCategory) {
        return false;
      }
      for (final t in _selectedTags) {
        if (!v.tags.contains(t)) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatch = v.name.toLowerCase().contains(q);
        final tokenMatch = v.searchTokens?.toLowerCase().contains(q) ?? false;
        if (!nameMatch && !tokenMatch) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final now = DateTime.now();
        final aOpen = a.isOpenAt(now) ? 0 : 1;
        final bOpen = b.isOpenAt(now) ? 0 : 1;
        if (aOpen != bOpen) return aOpen - bOpen;
        return a.name.compareTo(b.name);
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('식당·카페', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: _isPartnerMode
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: _areas.map((a) => Tab(text: a)).toList(),
                onTap: (_) => setState(() {}),
              ),
      ),
      body: Column(
        children: [
          if (!_isPartnerMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: '식당·카페 검색',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          _FilterRow(
            selectedCategory: _selectedCategory,
            selectedTags: _selectedTags,
            isPartnerMode: _isPartnerMode,
            onPartnerModeToggled: () => setState(() {
              _isPartnerMode = !_isPartnerMode;
              _selectedCategory = null;
            }),
            onCategoryChanged: (c) => setState(() {
              _selectedCategory = c;
              _isPartnerMode = false;
            }),
            onTagToggled: (t) => setState(() {
              _isPartnerMode = false;
              if (_selectedTags.contains(t)) {
                _selectedTags.remove(t);
              } else {
                _selectedTags.add(t);
              }
            }),
          ),
          Expanded(
            child:
                _isPartnerMode ? _buildPartnerContent() : _buildVenueContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildVenueContent() {
    final venuesAsync = ref.watch(venuesProvider);
    return venuesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(e.toString(), style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.invalidate(venuesProvider),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
      data: (venues) {
        final filtered = _filter(venues);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${filtered.length}곳',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(
                            '검색 결과가 없어요',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) => _VenueRow(venue: filtered[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPartnerContent() {
    final async = ref.watch(partnerAllProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          '불러오기 실패\n$e',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
      ),
      data: (list) {
        final active = list.where((r) => !r.isExpired).toList();
        if (active.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_outlined,
                    size: 56, color: Color(0xFFCCCCCC)),
                SizedBox(height: 12),
                Text('제휴 매장 정보가 없습니다.',
                    style: TextStyle(color: Color(0xFF999999))),
              ],
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${active.length}곳',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: active.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (_, i) => _PartnerRow(restaurant: active[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── 필터 칩 행 ──────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final String? selectedCategory;
  final Set<String> selectedTags;
  final bool isPartnerMode;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onTagToggled;
  final VoidCallback onPartnerModeToggled;

  const _FilterRow({
    required this.selectedCategory,
    required this.selectedTags,
    required this.isPartnerMode,
    required this.onCategoryChanged,
    required this.onTagToggled,
    required this.onPartnerModeToggled,
  });

  @override
  Widget build(BuildContext context) {
    final categories = [
      (key: 'restaurant', label: '음식점', icon: Icons.restaurant),
      (key: 'cafe', label: '카페', icon: Icons.local_cafe),
      (key: 'convenience', label: '편의점', icon: Icons.store),
    ];

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // 카테고리 칩
          ...categories.map((c) {
            final sel = selectedCategory == c.key && !isPartnerMode;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(c.label),
                avatar: Icon(c.icon, size: 14),
                selected: sel,
                onSelected: (_) =>
                    onCategoryChanged(sel ? null : c.key),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 12),
              ),
            );
          }),
          // 제휴 매장 칩
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('제휴 매장'),
              avatar: const Icon(Icons.storefront_outlined, size: 14),
              selected: isPartnerMode,
              onSelected: (_) => onPartnerModeToggled(),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              labelStyle: const TextStyle(fontSize: 12),
              selectedColor: Colors.orange.withValues(alpha: 0.2),
            ),
          ),
          // 상황 태그 칩 (제휴 매장 모드일 때 숨김)
          if (!isPartnerMode) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: VerticalDivider(width: 1, color: Colors.grey[300]),
            ),
            ..._situationTags.map((t) {
              final sel = selectedTags.contains(t);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(t),
                  selected: sel,
                  onSelected: (_) => onTagToggled(t),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 12),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ── 제휴 식당 행 ────────────────────────────────────────────────────

class _PartnerRow extends ConsumerWidget {
  final PartnerRestaurant restaurant;
  const _PartnerRow({required this.restaurant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(favPartnersProvider).contains(restaurant.id);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: Colors.orange.withValues(alpha: 0.12),
        child:
            const Icon(Icons.storefront_outlined, color: Colors.orange, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              restaurant.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF3FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              restaurant.category,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF1A73E8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () =>
                ref.read(favPartnersProvider.notifier).toggle(restaurant.id),
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                size: 20,
                color: isFav ? Colors.red : Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          if (restaurant.address.isNotEmpty)
            Text(
              restaurant.address,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 2),
          Text(
            '🎁 ${restaurant.benefit}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── 식당 행 ────────────────────────────────────────────────────────

class _VenueRow extends ConsumerWidget {
  final Venue venue;
  const _VenueRow({required this.venue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final isOpen = venue.isOpenAt(now);
    final timeLabel = venue.todayHoursText(now);
    final preview = venue.lunchPreview;
    final isFav = ref.watch(favVenuesProvider).contains(venue.id);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: isOpen
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.12),
        child: Icon(
          _iconFor(venue.category),
          color: isOpen ? Colors.green[700] : Colors.grey,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              venue.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
          // 지역 배지 (교내가 아닌 경우만)
          if (venue.area != '교내')
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                venue.area,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF1A73E8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // 즐겨찾기
          GestureDetector(
            onTap: () {
              ref.read(favVenuesProvider.notifier).toggle(venue.id);
              Analytics.venueFavoriteToggled(
                venueName: venue.name,
                nowFavorite: !isFav,
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 20,
                color: isFav ? Colors.amber[600] : Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                venue.building,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (timeLabel != null)
                Text(
                  ' · $timeLabel',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              if (venue.priceLevel != null) ...[
                Text(
                  ' · ',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  _priceLevelText(venue.priceLevel!),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32)),
                ),
              ],
            ],
          ),
          if (preview != null && preview.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '오늘 점심: $preview',
              style: const TextStyle(fontSize: 12, color: Color(0xFF1565C0)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      trailing: _OpenBadge(isOpen: isOpen),
      onTap: () {
        Analytics.venueViewed(
          venueName: venue.name,
          category: venue.category.name,
          isOpen: isOpen,
        );
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VenueDetailScreen(venue: venue)),
        );
      },
    );
  }

  IconData _iconFor(VenueCategory category) {
    switch (category) {
      case VenueCategory.restaurant:
        return Icons.restaurant;
      case VenueCategory.cafe:
        return Icons.local_cafe;
      case VenueCategory.convenience:
        return Icons.store;
    }
  }

  String _priceLevelText(int level) {
    switch (level) {
      case 1:
        return '₩';
      case 2:
        return '₩₩';
      case 3:
        return '₩₩₩';
      default:
        return '';
    }
  }
}

class _OpenBadge extends StatelessWidget {
  final bool isOpen;
  const _OpenBadge({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOpen
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isOpen ? '영업중' : '준비중',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isOpen ? Colors.green[700] : Colors.grey[600],
        ),
      ),
    );
  }
}
