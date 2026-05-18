import 'package:flutter/material.dart';

class MapFilterBar extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const MapFilterBar({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const filters = [
      ('all', '전체'),
      ('restaurant', '🍽️ 식당'),
      ('cafe', '☕ 카페'),
      ('building', '🏛️ 건물'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: filters.map((f) {
          final isSelected = current == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(f.$2),
              selected: isSelected,
              onSelected: (_) => onChanged(f.$1),
              backgroundColor: Colors.white,
              selectedColor: Colors.blue.withOpacity(0.2),
              elevation: isSelected ? 0 : 2,
            ),
          );
        }).toList(),
      ),
    );
  }
}
