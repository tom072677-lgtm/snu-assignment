import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/venue_repository.dart';
import '../domain/venue.dart';
import 'venue_list_screen.dart';

class RestaurantScreen extends ConsumerWidget {
  const RestaurantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venuesAsync = ref.watch(venuesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('식당·카페', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: venuesAsync.when(
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
        data: (venues) => _CategoryGrid(venues: venues),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  final List<Venue> venues;
  const _CategoryGrid({required this.venues});

  @override
  Widget build(BuildContext context) {
    final categories = [
      (
        category: VenueCategory.restaurant,
        label: '음식점',
        icon: Icons.restaurant,
        color: const Color(0xFFFF6B35),
      ),
      (
        category: VenueCategory.cafe,
        label: '카페',
        icon: Icons.local_cafe,
        color: const Color(0xFF8B5E3C),
      ),
      (
        category: VenueCategory.convenience,
        label: '편의점',
        icon: Icons.store,
        color: const Color(0xFF2E7D32),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '서울대 캠퍼스 시설',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              children: categories.map((c) {
                final count = venues.where((v) => v.category == c.category).length;
                final openCount = venues
                    .where((v) =>
                        v.category == c.category &&
                        v.isOpenAt(DateTime.now()))
                    .length;
                return _CategoryCard(
                  label: c.label,
                  icon: c.icon,
                  color: c.color,
                  total: count,
                  openNow: openCount,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VenueListScreen(
                        category: c.category,
                        label: c.label,
                        venues: venues
                            .where((v) => v.category == c.category)
                            .toList(),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int total;
  final int openNow;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.total,
    required this.openNow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$total곳 · 지금 영업중 $openNow곳',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
