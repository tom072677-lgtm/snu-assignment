import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/analytics.dart';
import '../../../shared/providers/settings_provider.dart';
import '../domain/venue.dart';
import 'venue_detail_screen.dart';

class VenueListScreen extends ConsumerWidget {
  final VenueCategory category;
  final String label;
  final List<Venue> venues;

  const VenueListScreen({
    super.key,
    required this.category,
    required this.label,
    required this.venues,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favIds = ref.watch(favVenuesProvider);
    final now = DateTime.now();

    // 즐겨찾기 → 영업중 → 가나다 순
    final sorted = [...venues]..sort((a, b) {
        final aFav = favIds.contains(a.id) ? 0 : 1;
        final bFav = favIds.contains(b.id) ? 0 : 1;
        if (aFav != bFav) return aFav - bFav;
        final aOpen = a.isOpenAt(now) ? 0 : 1;
        final bOpen = b.isOpenAt(now) ? 0 : 1;
        if (aOpen != bOpen) return aOpen - bOpen;
        return a.name.compareTo(b.name);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        top: false,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (_, i) => _VenueRow(venue: sorted[i]),
        ),
      ),
    );
  }
}

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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
          // 즐겨찾기 별 아이콘
          GestureDetector(
            onTap: () {
              final willFav = !isFav;
              ref.read(favVenuesProvider.notifier).toggle(venue.id);
              Analytics.venueFavoriteToggled(
                venueName: venue.name,
                nowFavorite: willFav,
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
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: venue.building,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (timeLabel != null)
                TextSpan(
                  text: ' · $timeLabel',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
            ]),
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
