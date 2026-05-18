import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/restaurant_repository.dart';
import '../domain/restaurant.dart';

class RestaurantScreen extends ConsumerWidget {
  const RestaurantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantsAsync = ref.watch(restaurantProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('식당', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: restaurantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(restaurantProvider),
        ),
        data: (restaurants) {
          if (restaurants.isEmpty) {
            return const Center(
              child: Text('오늘 식당 정보가 없습니다',
                  style: TextStyle(color: Colors.grey)),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(restaurantProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: restaurants.length,
              itemBuilder: (_, i) =>
                  _RestaurantCard(restaurant: restaurants[i]),
            ),
          );
        },
      ),
    );
  }
}

class _RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  const _RestaurantCard({required this.restaurant});

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.name,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 16),
            if (r.breakfast.isNotEmpty)
              _MealRow(label: '조식', menu: r.breakfast),
            if (r.lunch.isNotEmpty)
              _MealRow(label: '중식', menu: r.lunch),
            if (r.dinner.isNotEmpty)
              _MealRow(label: '석식', menu: r.dinner),
          ],
        ),
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  final String label;
  final String menu;
  const _MealRow({required this.label, required this.menu});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              menu,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
