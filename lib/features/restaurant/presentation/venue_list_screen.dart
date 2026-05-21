import 'package:flutter/material.dart';
import '../domain/venue.dart';
import 'venue_detail_screen.dart';

class VenueListScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Open venues first, then alphabetical
    final sorted = [...venues]..sort((a, b) {
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

class _VenueRow extends StatelessWidget {
  final Venue venue;
  const _VenueRow({required this.venue});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isOpen = venue.isOpenAt(now);
    final timeLabel = venue.todayHoursText(now);
    final preview = venue.lunchPreview;

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
      title: Text(
        venue.name,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          // 건물 · 시간 한 줄
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: venue.building,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (timeLabel != null)
                TextSpan(
                  text: ' · $timeLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
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
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VenueDetailScreen(venue: venue)),
      ),
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
